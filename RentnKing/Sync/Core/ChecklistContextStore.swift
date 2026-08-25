//
//  ChecklistContextStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Durable cache of ChecklistContext snapshots, keyed by order product + leg,
//  under the protected KabbaSync directory (same protection/backup policy as
//  operations). The employee loads an order while connected, loses coverage at
//  the job site, and still has identity + questions + requirements to finish.
//

import Foundation

final class ChecklistContextStore {

    let directory: URL
    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.directory = rootDirectory.appendingPathComponent("checklist-contexts", isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(directory, fileManager: fileManager)
    }

    static func key(orderProductUniqueId: String, leg: ChecklistLeg) -> String {
        let safe = orderProductUniqueId.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(safe)) + "__" + leg.rawValue
    }

    func save(_ context: ChecklistContext, cachedAt: Date = Date()) throws {
        var copy = context
        copy.cachedAt = cachedAt
        let data = try encoder.encode(copy)
        try lock.withLock {
            try FileSyncOperationStore.writeProtected(data, to: url(orderProductUniqueId: context.identity.orderProductUniqueId, leg: context.leg))
        }
    }

    func load(orderProductUniqueId: String, leg: ChecklistLeg) -> ChecklistContext? {
        lock.withLock {
            let url = self.url(orderProductUniqueId: orderProductUniqueId, leg: leg)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ChecklistContext.self, from: data)
        }
    }

    func remove(orderProductUniqueId: String, leg: ChecklistLeg) {
        lock.withLock {
            try? fileManager.removeItem(at: url(orderProductUniqueId: orderProductUniqueId, leg: leg))
        }
    }

    /// Every cached snapshot, for diagnostics.
    func all() -> [ChecklistContext] {
        lock.withLock {
            let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "json" }.compactMap { url in
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ChecklistContext.self, from: $0) }
            }
        }
    }

    private func url(orderProductUniqueId: String, leg: ChecklistLeg) -> URL {
        directory.appendingPathComponent(ChecklistContextStore.key(orderProductUniqueId: orderProductUniqueId, leg: leg) + ".json")
    }
}
