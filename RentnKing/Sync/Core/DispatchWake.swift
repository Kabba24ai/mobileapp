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

    /// How a Dispatch wake is handled: invisible, and "no data" until Phase 3 reconciles.
    struct Handling: Equatable {
        let adjustsBadge: Bool
        let presentsUI: Bool
        let reportsNewData: Bool
    }

    static let handling = Handling(adjustsBadge: false, presentsUI: false, reportsNewData: false)

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
