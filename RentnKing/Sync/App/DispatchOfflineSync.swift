//
//  DispatchOfflineSync.swift
//  RentnKing — Sync App layer (UIKit)
//
//  Dispatch offline mission cache — Phase 3. Wires the ONE reconciliation
//  coordinator (Sync Core: DispatchOfflineReconciler) into the app:
//
//    • silent Dispatch wake (NotificaiotnFile)      → .wake(revision)
//    • launch (KabbaSync.bootstrap)                 → .launch
//    • login completed (LoginModel)                 → .loginCompleted
//    • app became active (KabbaSync)                → .foreground
//    • Dispatch opened / pull-to-refresh            → .dispatchScreenOpened / .manualRefresh
//    • connectivity restored (AppDelegate)          → .networkRestored
//
//  No timer, no polling, no socket, no location. The cache is per tenant (the
//  login's api_url) and survives logout / 401: nothing here ever deletes it.
//  With no session there is nothing to reconcile and no request is made.
//

import UIKit

extension Notification.Name {
    /// Posted on the main queue when the presentable offline Dispatch working set changed on disk.
    static let kabbaDispatchOfflineChanged = Notification.Name("ai.kabba.dispatchOffline.changed")
    /// Posted on the main queue when a reconciliation run finished (whatever triggered it) —
    /// never for a skip, never for a run stopped by a session change (review F3).
    /// userInfo: ["failed": Bool, "tenantKey": String] — failed or partial means the shown list
    /// may not be current; only the company signed in NOW applies it.
    static let kabbaDispatchOfflineReconciled = Notification.Name("ai.kabba.dispatchOffline.reconciled")
}

enum DispatchOfflineSync {

    private static var rootDirectory: URL?
    private static var client: SyncHTTPClient?
    private static var baseURL: () -> URL? = { nil }
    private static var accessToken: () -> String? = { nil }

    private static let lock = NSLock()
    private static var current: (tenantKey: String, reconciler: DispatchOfflineReconciler)?

    /// Called once from KabbaSync.bootstrap (same protected root and API client as the Sync Engine).
    static func configure(rootDirectory: URL, client: SyncHTTPClient,
                          baseURL: @escaping () -> URL?, accessToken: @escaping () -> String?) {
        lock.withLock {
            self.rootDirectory = rootDirectory
            self.client = client
            self.baseURL = baseURL
            self.accessToken = accessToken
        }
    }

    /// The signed-in session as the reconciler binds it: the tenant (api_url) and an opaque
    /// hash of the credential — a run started under one session never writes after another
    /// begins (logout, another company, another employee). The token itself is never kept.
    static func currentSession() -> DispatchOfflineSession? {
        let (url, token) = lock.withLock { (baseURL(), accessToken()) }
        guard let url = url, let host = url.host, !host.isEmpty, let token = token, !token.isEmpty else { return nil }
        return DispatchOfflineSession(tenantKey: DispatchOfflineTenant.key(baseURL: url),
                                      credential: String(format: "%016llx", DispatchOfflineTenant.fnv1a64(token)))
    }

    // MARK: - Triggers

    static func trigger(_ trigger: DispatchOfflineTrigger, completion: ((DispatchOfflineReconcileResult) -> Void)? = nil) {
        guard let reconciler = reconciler() else {
            // Signed out (no tenant): nothing to reconcile, nothing requested, cache kept.
            completion?(DispatchOfflineReconcileResult(status: .skipped(.noSession)))
            return
        }

        // A run started while the app is in use keeps going briefly if the employee leaves the app.
        let task = BackgroundTask.begin()
        let tenantKey = reconciler.store.tenantKey
        reconciler.request(trigger) { result in
            DispatchQueue.main.async {
                task.end()
                if DispatchOfflineScreenPolicy.postsReconcileOutcome(result) {
                    NotificationCenter.default.post(name: .kabbaDispatchOfflineReconciled, object: nil,
                                                    userInfo: ["failed": DispatchOfflineScreenPolicy.indicatesFailure(result),
                                                               "tenantKey": tenantKey])
                }
                completion?(result)
            }
        }
    }

    /// A silent Dispatch wake: reconcile, then answer iOS exactly once (DispatchWakeCompletion).
    static func handleWake(_ trigger: DispatchOfflineTrigger,
                           completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let completion = DispatchWakeCompletion(
            deadline: DispatchWake.backgroundDeadline,
            schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
            deliver: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .newData: completionHandler(.newData)
                    case .noData:  completionHandler(.noData)
                    case .failed:  completionHandler(.failed)
                    }
                }
            }
        )
        let observer = NotificationCenter.default.addObserver(forName: .kabbaDispatchOfflineChanged, object: nil, queue: .main) { _ in
            completion.noteChanged()
        }
        Self.trigger(trigger) { result in
            NotificationCenter.default.removeObserver(observer)
            completion.finish(result.backgroundResult)
        }
    }

    // MARK: - Presentation

    /// The Dispatch screen's local source for the signed-in tenant; nil when signed out.
    static func presentation(for query: DispatchOfflineQuery, now: Date = Date()) -> DispatchOfflinePresentation? {
        guard let reconciler = reconciler() else { return nil }
        return DispatchOfflineWorkingSet.present(store: reconciler.store,
                                                 query: query,
                                                 operations: KabbaSync.engine?.snapshot() ?? [],
                                                 today: DispatchOfflineWorkingSet.localDateString(now))
    }

    // MARK: - Tenant-bound reconciler

    private static func reconciler() -> DispatchOfflineReconciler? {
        lock.withLock {
            guard let root = rootDirectory, let client = client,
                  let url = baseURL(), let host = url.host, !host.isEmpty else { return nil }
            let key = DispatchOfflineTenant.key(baseURL: url)
            if let current = current, current.tenantKey == key { return current.reconciler }
            guard let store = try? DispatchOfflineMissionStore(rootDirectory: root, baseURL: url) else { return nil }

            let reconciler = DispatchOfflineReconciler(
                httpClient: client,
                store: store,
                session: { DispatchOfflineSync.currentSession() },
                // D7: an order product with ANY Sync Engine operation keeps its package on disk.
                retainedOrderProducts: {
                    Set((KabbaSync.engine?.snapshot() ?? []).compactMap { $0.identity.orderProductUniqueId })
                }
            )
            var lastSignature = store.loadIndex().presentableSignature
            reconciler.onCommit = { index in
                // On the reconciler's queue.
                let signature = index.presentableSignature
                guard signature != lastSignature else { return }
                lastSignature = signature
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .kabbaDispatchOfflineChanged, object: nil)
                }
            }
            #if DEBUG
            reconciler.logger = { print($0) }
            #endif
            current = (key, reconciler)
            return reconciler
        }
    }

    /// UIApplication background task, safe to end once from any path.
    private final class BackgroundTask {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        private let lock = NSLock()

        static func begin() -> BackgroundTask {
            let task = BackgroundTask()
            let start = {
                task.identifier = UIApplication.shared.beginBackgroundTask(withName: "dispatch-offline-reconcile") { task.end() }
            }
            if Thread.isMainThread { start() } else { DispatchQueue.main.sync(execute: start) }
            return task
        }

        func end() {
            let id: UIBackgroundTaskIdentifier = lock.withLock {
                let id = identifier
                identifier = .invalid
                return id
            }
            guard id != .invalid else { return }
            if Thread.isMainThread { UIApplication.shared.endBackgroundTask(id) }
            else { DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(id) } }
        }
    }
}
