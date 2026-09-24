//
//  DispatchWake.swift
//  Dispatch offline mission cache — Phase 2 (installation registry + silent wake).
//
//  Pure, Foundation-only rules (unit-tested by KabbaSyncCoreTests):
//   • DispatchInstallationRegistration — registers THIS installation (X-Device-Id,
//     added by the API client to every request) with its FCM token so Laravel can
//     silently wake it when company Dispatch changes. Installation-scoped: logout
//     and user switching never unregister; there is no unregister request.
//   • DispatchWake — recognises a silent Dispatch wake among incoming pushes. The
//     payload is only a hint; reconciliation (Phase 3) always reads the live
//     manifest. A wake is invisible: no badge, no UI.
//   • DispatchWakeCompletion (Phase 3) — answers iOS's background-fetch handler
//     exactly once: with the reconciliation's result, or at the deadline with
//     newData if a commit already changed the working set, else failed.
//

import Foundation

enum DispatchInstallationRegistration {
    static let path = "mobile/installations"

    /// When the app (re)registers. The server upserts, so repeating is harmless.
    enum Trigger: String, CaseIterable {
        case launch
        case loginCompleted
        case tokenRefresh
    }

    enum Outcome: Equatable {
        case registered(wakeEnabled: Bool)
        case rejected(statusCode: Int)
    }

    /// The endpoint is authenticated, so registration needs a signed-in session and a real token.
    static func shouldRegister(fcmToken: String?, hasSession: Bool) -> Bool {
        guard hasSession, let token = fcmToken?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !token.isEmpty
    }

    /// Identity is deliberately NOT in the body — the server takes it only from X-Device-Id.
    static func request(fcmToken: String, operationId: String) -> SyncHTTPRequest {
        SyncHTTPRequest(
            method: "POST",
            path: path,
            jsonBody: .object(["fcm_token": .string(fcmToken)]),
            operationId: operationId
        )
    }

    static func outcome(of response: SyncHTTPResponse) -> Outcome {
        guard response.isSuccessStatus,
              let data = response.envelope?.data,
              data["registered"]?.boolValue == true else {
            return .rejected(statusCode: response.statusCode)
        }
        return .registered(wakeEnabled: data["wake_enabled"]?.boolValue ?? false)
    }
}

enum DispatchWake {
    static let messageType = "dispatch_changed"

    /// How a Dispatch wake is handled: invisible; the fetch result is the reconciliation's (Phase 3).
    struct Handling: Equatable {
        let adjustsBadge: Bool
        let presentsUI: Bool
        let reportsReconciliationResult: Bool
    }

    static let handling = Handling(adjustsBadge: false, presentsUI: false, reportsReconciliationResult: true)

    /// iOS gives a background push about 30 s; answer before then.
    static let backgroundDeadline: TimeInterval = 25

    /// The reconciliation a push asks for (nil for every other push). An empty hint carries no revision.
    static func trigger(fromPushUserInfo userInfo: [AnyHashable: Any]) -> DispatchOfflineTrigger? {
        guard let revision = revision(fromPushUserInfo: userInfo) else { return nil }
        return .wake(revision: revision.isEmpty ? nil : revision)
    }

    /// The wake's manifest revision when `userInfo` is a silent Dispatch wake (empty if the
    /// hint carries none); nil for every other push.
    static func revision(fromPushUserInfo userInfo: [AnyHashable: Any]) -> String? {
        guard (userInfo["type"] as? String) == messageType else { return nil }
        return (userInfo["dispatch_revision"] as? String) ?? ""
    }

    static func isDispatchWake(_ userInfo: [AnyHashable: Any]) -> Bool {
        revision(fromPushUserInfo: userInfo) != nil
    }
}

/// Calls the background-fetch completion exactly once — the reconciliation's own result,
/// or at the deadline (newData if a commit already changed the set, else failed). The run
/// itself may continue after the deadline: it is crash-safe.
final class DispatchWakeCompletion {
    private let lock = NSLock()
    private var delivered = false
    private var changed = false
    private let deliver: (DispatchOfflineBackgroundResult) -> Void

    init(deadline: TimeInterval,
         schedule: (TimeInterval, @escaping () -> Void) -> Void,
         deliver: @escaping (DispatchOfflineBackgroundResult) -> Void) {
        self.deliver = deliver
        // Strong on purpose: the deadline must fire even if nothing else holds this object.
        schedule(deadline) { self.expire() }
    }

    func noteChanged() { lock.withLock { changed = true } }

    func finish(_ result: DispatchOfflineBackgroundResult) {
        guard claim() else { return }
        deliver(result)
    }

    private func expire() {
        let changedSoFar = lock.withLock { changed }
        guard claim() else { return }
        deliver(changedSoFar ? .newData : .failed)
    }

    private func claim() -> Bool {
        lock.withLock {
            guard !delivered else { return false }
            delivered = true
            return true
        }
    }
}
