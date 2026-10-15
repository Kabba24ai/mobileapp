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
//  Phase 4: after every committed run (and once at launch / login for the
//  packages already on disk) the field bridge preloads the caches the screens
//  read — checklist contexts, Order Details, the checklist order, Assembly
//  Review — for the signed-in company only. After a run that reached the
//  server on launch / login / foreground / network restored, the reference
//  lists the offline screens read are refreshed when empty or older than 12 h
//  (P4-D6) — through their existing endpoints, never on a wake or a timer.
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
        if trigger == .launch || trigger == .loginCompleted {
            // Offline relaunch, or a bridge a previous launch did not finish: the packages on disk
            // are bridged before (and whether or not) the server answers. Idempotent (ledger).
            reconciler.bridgeStoredPackages()
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
                warmReferenceLists(after: trigger, result: result, tenantKey: tenantKey)
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

    // MARK: - Live screen saves (Phase 4 §4.3)

    /// A screen got a live Order Details / checklist order / Assembly Review answer to a request it
    /// sent at `askedAt` for `tenantKey`. `save` runs only while that company is still signed in and
    /// when no newer copy (a package asked later) is on this phone — atomically with the bridge.
    @discardableResult
    static func saveLiveCopy(_ cache: DispatchOfflineOrderCache, orderUniqueId: String, askedAt: Date,
                             tenantKey: String, save: () -> Bool) -> Bool {
        if let reconciler = reconciler() {
            guard reconciler.store.tenantKey == tenantKey else { return false } // another company signed in since
            return reconciler.store.saveLiveCopy(cache, orderUniqueId: orderUniqueId, askedAt: askedAt, save: save)
        }
        // No offline store (the Sync bootstrap failed): today's behavior, for the company still signed in.
        guard KabbaTenantScope.currentKey == tenantKey else { return false }
        return save()
    }

    /// When Laravel was asked for the order copy this phone holds in `cache` (a live answer's
    /// request time, or a mission package's) for the signed-in company; nil when unknown.
    static func observedAt(_ cache: DispatchOfflineOrderCache, orderUniqueId: String) -> Date? {
        guard !orderUniqueId.isEmpty else { return nil }
        return reconciler()?.store.loadFieldLedger().observed(cache, orderUniqueId)
    }

    // MARK: - Reference lists (P4-D6)

    /// Refreshes, through their existing endpoints, the lists the offline checklist and Order
    /// Details read — only after the listed triggers reached the server, only for the company the
    /// run was for, and only a list that is empty or older than 12 h. Each list is stamped when its
    /// answer was saved for that company.
    private static func warmReferenceLists(after trigger: DispatchOfflineTrigger, result: DispatchOfflineReconcileResult,
                                           tenantKey: String) {
        guard DispatchOfflineReferenceWarmup.runs(after: trigger, result: result),
              KabbaTenantScope.currentKey == tenantKey else { return }
        let now = Date()
        for list in DispatchOfflineReferenceWarmup.List.allCases {
            guard DispatchOfflineReferenceWarmup.isDue(isEmpty: ReferenceLists.isEmpty(list),
                                                       lastWarmedAt: ReferenceLists.warmedAt(list, tenantKey: tenantKey),
                                                       now: now) else { continue }
            ReferenceLists.refresh(list) { saved in
                if saved { ReferenceLists.stamp(list, tenantKey: tenantKey, at: now) }
            }
        }
    }

    /// The signed-in user as a checklist context employee (P4-D5); nil keeps the stored one. A
    /// profile saved before the login stored `unique_id` has none: that same user downloaded the
    /// packages, so the stored employee is already them (any other user logs in again first).
    static func signedInEmployee() -> ChecklistContext.Employee? {
        guard let user = UserDefaults.standard.user, let id = Int(user.id ?? ""), id > 0,
              let uniqueId = user.unique_id, !uniqueId.isEmpty, uniqueId != "0" else { return nil }
        return ChecklistContext.Employee(userId: id, uniqueId: uniqueId, fullName: user.full_name ?? "")
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
            if let contexts = KabbaSync.contextStore {
                // Phase 4: preload the screens' caches from each package, for THIS company only.
                reconciler.fieldBridge = DispatchOfflineFieldBridge(
                    store: store, contexts: contexts, agreements: KabbaSync.termsAgreements,
                    writer: DispatchOfflineOrderBridge.shared,
                    operations: { KabbaSync.engine?.snapshot() ?? [] },
                    currentEmployee: { DispatchOfflineSync.signedInEmployee() })
            }
            #if DEBUG
            reconciler.logger = { print($0) }
            #endif
            current = (key, reconciler)
            return reconciler
        }
    }

    /// The reference lists' existing loaders and their company-scoped caches.
    private enum ReferenceLists {
        static func isEmpty(_ list: DispatchOfflineReferenceWarmup.List) -> Bool {
            switch list {
            case .employees:  return getEmployeeData().isEmpty
            case .drivers:    return getDriverEmployeeData().isEmpty
            case .equipment:  return getEquipmentData().isEmpty
            case .stores:     return getStoreListData().isEmpty
            case .categories: return getCatData().isEmpty
            case .prices:     return getPriceData().isEmpty || getProductSettingData().isEmpty
            case .users:      return (SDKUserDefault.getMappableArray(UserListModel.self, for: kFileStorageName.kOrderDetailUserData.rawValue) ?? []).isEmpty
            }
        }

        static func refresh(_ list: DispatchOfflineReferenceWarmup.List, completion: @escaping (Bool) -> Void) {
            switch list {
            case .employees:  CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater(), completion: completion)
            case .drivers:    CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater(is_driver: true), completion: completion)
            case .equipment:  CallAPIforGetEquipmentList(EquipmentParameater: EquipmentParameater(type: "Checklist", search: "", store_id: "", currently_assigned: 1),
                                                         completion: completion)
            case .stores:     CallAPIforStoreList(completion: completion)
            case .categories: callAPIforCategoryList(CatrgoryParameater: CatrgoryParameater(), completion: completion)
            case .prices:     getPriceListAPI(completion: completion)
            case .users:      callAPIforUsersList(completion: completion)
            }
        }

        static func warmedAt(_ list: DispatchOfflineReferenceWarmup.List, tenantKey: String) -> Date? {
            guard let key = DispatchOfflineTenantStorage.storageKey(DispatchOfflineReferenceWarmup.stampKey(list), tenantKey: tenantKey) else { return nil }
            return UserDefaults.standard.object(forKey: key) as? Date
        }

        static func stamp(_ list: DispatchOfflineReferenceWarmup.List, tenantKey: String, at date: Date) {
            guard let key = DispatchOfflineTenantStorage.storageKey(DispatchOfflineReferenceWarmup.stampKey(list), tenantKey: tenantKey) else { return }
            UserDefaults.standard.set(date, forKey: key)
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
