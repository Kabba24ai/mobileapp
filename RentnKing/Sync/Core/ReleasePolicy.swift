//
//  ReleasePolicy.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 5 — the server's mobile release policy as the phone sees it.
//
//   • ReleasePolicy       the `data` block of a 426 APP_UPDATE_REQUIRED, of
//                         GET app/release, or the `release` block of a login.
//   • UpdateAdvice        the additive X-Mobile-Update / X-Mobile-Minimum-Build
//                         / X-Mobile-Recommended-* response headers.
//   • UpdateRequiredStore a 426 verdict persisted in the protected KabbaSync
//                         directory so it survives relaunch: while the RUNNING
//                         build is still below the minimum the engine stays
//                         paused and the Update Required screen shows; the
//                         moment a compatible build launches, the verdict is
//                         cleared and the queue resumes. Nothing queued is ever
//                         touched by a version verdict.
//

import Foundation

struct ReleasePolicy: Codable, Equatable {
    var platform: String
    var state: String
    var clientBuild: String?
    var clientVersion: String?
    var minimumSupportedBuild: String?
    var recommendedBuild: String?
    var recommendedVersion: String?
    var updateMessage: String?
    var storeURL: String?
    var updateRequired: Bool
    var updateRecommended: Bool

    static func decode(_ json: JSONValue?) -> ReleasePolicy? {
        guard let json = json, case .object = json, let state = json["state"]?.stringValue else { return nil }
        return ReleasePolicy(
            platform: json["platform"]?.stringValue ?? "ios",
            state: state,
            clientBuild: json["client_build"]?.stringValue,
            clientVersion: json["client_version"]?.stringValue,
            minimumSupportedBuild: json["minimum_supported_build"]?.stringValue,
            recommendedBuild: json["recommended_build"]?.stringValue,
            recommendedVersion: json["recommended_version"]?.stringValue,
            updateMessage: json["update_message"]?.stringValue,
            storeURL: json["store_url"]?.stringValue,
            updateRequired: json["update_required"]?.boolValue ?? (state == "update_required"),
            updateRecommended: json["update_recommended"]?.boolValue ?? (state == "update_recommended")
        )
    }

    /// 426 body / GET app/release → `data`; login → `release`.
    static func decode(envelopeData data: Data?) -> ReleasePolicy? {
        guard let root = JSONValue.parse(data) else { return nil }
        return decode(root["data"]) ?? decode(root["release"])
    }

    /// Does this verdict still apply to the build that is running now?
    func stillRequiresUpdate(forBuild build: String) -> Bool {
        if let minimum = minimumSupportedBuild { return BuildNumber.isBelow(build, minimum) }
        if let blocked = clientBuild { return BuildNumber.compare(build, blocked) <= 0 }
        return updateRequired
    }

    var employeeMessage: String {
        updateMessage?.isEmpty == false ? updateMessage! : "This version of the Kabba app is no longer supported. Please update."
    }
}

struct UpdateAdvice: Equatable {
    /// `notNeeded` carries the wire value "none" (an enum case named `none` is ambiguous with Optional.none).
    enum Level: String { case notNeeded = "none", recommended, required }

    let level: Level
    let minimumBuild: String?
    let recommendedBuild: String?
    let recommendedVersion: String?

    /// nil when the server sent no policy headers (no active policy).
    static func from(headers: [String: String]) -> UpdateAdvice? {
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        guard let raw = header("X-Mobile-Update") else { return nil }
        return UpdateAdvice(level: Level(rawValue: raw.lowercased()) ?? .notNeeded,
                            minimumBuild: header("X-Mobile-Minimum-Build"),
                            recommendedBuild: header("X-Mobile-Recommended-Build"),
                            recommendedVersion: header("X-Mobile-Recommended-Version"))
    }
}

struct UpdateRequiredState: Codable, Equatable {
    var policy: ReleasePolicy
    var receivedAt: Date
    /// The build that was refused.
    var blockedBuild: String
    var requestId: String?
}

final class UpdateRequiredStore {
    static let filename = "update_required.json"

    enum Resolution: Equatable {
        /// Nothing stored.
        case none
        /// Stored verdict still applies to the running build → stay paused, show Update Required.
        case stillRequired(UpdateRequiredState)
        /// The running build satisfies the stored minimum → clear and resume.
        case resolved(UpdateRequiredState)
    }

    let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent(UpdateRequiredStore.filename)
        self.fileManager = fileManager
    }

    func load() -> UpdateRequiredState? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? KabbaISO8601.makeDecoder().decode(UpdateRequiredState.self, from: data)
        }
    }

    func save(_ state: UpdateRequiredState) throws {
        try lock.withLock {
            try FileSyncOperationStore.ensureProtectedDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
            try FileSyncOperationStore.writeProtected(try KabbaISO8601.makeEncoder().encode(state), to: fileURL)
        }
    }

    func clear() {
        lock.withLock { try? fileManager.removeItem(at: fileURL) }
    }

    func resolution(currentBuild: String) -> Resolution {
        guard let state = load() else { return .none }
        return state.policy.stillRequiresUpdate(forBuild: currentBuild) ? .stillRequired(state) : .resolved(state)
    }
}
