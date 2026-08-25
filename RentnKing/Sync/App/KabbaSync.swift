//
//  KabbaSync.swift
//  RentnKing — Sync App layer (UIKit + BackgroundTasks)
//
//  Bootstraps the ONE Sync Engine for the app, wires its triggers, and bridges
//  its events to NotificationCenter on the main queue for the UI.
//
//  Triggers (the queue on disk is the truth; each of these only calls kick()):
//   • app launch (bootstrap)                  • app became active
//   • connectivity restored (AppDelegate)     • a new operation was enqueued
//   • BGAppRefreshTask (opportunistic)        • login completed (sessionDidStart)
//

import UIKit
import BackgroundTasks

extension Notification.Name {
    /// userInfo: ["operationId": String, "state": String]
    static let kabbaSyncOperationChanged = Notification.Name("ai.kabba.sync.operationChanged")
    static let kabbaSyncQueueChanged     = Notification.Name("ai.kabba.sync.queueChanged")
    /// userInfo: ["pause": String]
    static let kabbaSyncPauseChanged     = Notification.Name("ai.kabba.sync.pauseChanged")
}

enum KabbaSync {

    static let backgroundRefreshIdentifier = "com.RentnKingNew.app.sync.refresh"

    private(set) static var engine: SyncEngine?
    private(set) static var client: KabbaAPIClient?
    private(set) static var installation: InstallationIdentity?
    private(set) static var contextStore: ChecklistContextStore?
    private(set) static var checklistContexts: ChecklistContextClient?

    private static var observers: [NSObjectProtocol] = []
    private static var sessionExpiredHandler: (() -> Void)?

    static var isReady: Bool { engine != nil }

    /// Idempotent. Call from application(_:didFinishLaunchingWithOptions:) — BGTask
    /// registration must happen before the app finishes launching.
    static func bootstrap(baseURL: @escaping () -> URL?,
                          accessToken: @escaping () -> String?,
                          language: @escaping () -> String,
                          legacyMigrations: [() -> Void] = [],
                          onSessionExpired: (() -> Void)? = nil) {
        guard engine == nil else { return }

        do {
            let root = try FileSyncOperationStore.defaultRootDirectory()
            let store = try FileSyncOperationStore(rootDirectory: root)
            let installation = InstallationIdentity(directory: root)

            let configuration = KabbaAPIClientConfiguration(
                baseURL: baseURL,
                accessToken: accessToken,
                language: language,
                metadata: { MobileClientMetadata.current(installation: installation) }
            )
            let client = KabbaAPIClient.configure(configuration)

            let hasSession: () -> Bool = { accessToken().map { !$0.isEmpty } ?? false && baseURL() != nil }
            client.assetsDirectory = store.assetsDirectory
            let engine = SyncEngine(store: store,
                                    httpClient: client,
                                    handlers: [
                                        DriverChecklistSyncHandler(hasSession: hasSession),
                                        // Phase 3 — canonical checklist contract
                                        ChecklistCompleteSyncHandler(leg: .delivery, hasSession: hasSession),
                                        ChecklistCompleteSyncHandler(leg: .return, hasSession: hasSession),
                                        ChecklistPrepareSyncHandler(leg: .delivery, hasSession: hasSession),
                                        ChecklistPrepareSyncHandler(leg: .return, hasSession: hasSession),
                                        LegacyChecklistSubmitSyncHandler(hasSession: hasSession),
                                        FulfillmentInputsSyncHandler(hasSession: hasSession),
                                    ])

            let contextStore = try ChecklistContextStore(rootDirectory: root)
            KabbaSync.contextStore = contextStore
            KabbaSync.checklistContexts = ChecklistContextClient(client: client, store: contextStore)

            engine.logger = { line in
                #if DEBUG
                print(line)
                #endif
            }
            engine.eventHandler = { event in
                DispatchQueue.main.async { publish(event) }
            }

            KabbaSync.engine = engine
            KabbaSync.client = client
            KabbaSync.installation = installation
            KabbaSync.sessionExpiredHandler = onSessionExpired

            // Old MMKV queues → durable operations. Runs once per launch; each migration clears its source.
            legacyMigrations.forEach { $0() }

            registerBackgroundRefresh()
            observeLifecycle()
            engine.pruneSynced()
            engine.kick(reason: "launch")
        } catch {
            // The engine stays nil; legacy code paths keep working exactly as before.
            #if DEBUG
            print("[sync] bootstrap failed: \(error)")
            #endif
        }
    }

    // MARK: - Triggers

    static func kick(_ reason: String, ignoreBackoff: Bool = false) {
        engine?.kick(reason: reason, ignoreBackoff: ignoreBackoff)
    }

    /// Login succeeded: lift an authentication pause and drain what accumulated while signed out.
    static func sessionDidStart() {
        engine?.authenticationRestored()
    }

    /// Explicit logout: stop sending (operations stay stored for the next session).
    static func sessionDidEnd() {
        engine?.authenticationLost()
    }

    // MARK: - Background refresh (opportunistic; the queue never depends on it)

    private static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundRefresh(refresh)
        }
    }

    static func scheduleBackgroundRefresh() {
        guard let engine = engine, engine.summary().outstanding > 0 else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[sync] background refresh not scheduled: \(error)")
            #endif
        }
    }

    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        guard let engine = engine else {
            task.setTaskCompleted(success: false)
            return
        }

        var finished = false
        let finish: (Bool) -> Void = { success in
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = { finish(false) }

        engine.kick(reason: "background refresh", ignoreBackoff: true)

        // Poll briefly; the system gives us ~30 s. Whatever did not finish stays queued.
        let deadline = Date().addingTimeInterval(25)
        func check() {
            let summary = engine.summary()
            if summary.outstanding == 0 || summary.pause != .none || Date() >= deadline {
                finish(summary.outstanding == 0)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { check() }
    }

    // MARK: - Lifecycle + auth

    private static func observeLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            kick("didBecomeActive")
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            scheduleBackgroundRefresh()
        })
        observers.append(center.addObserver(forName: .kabbaAuthenticationExpired, object: nil, queue: .main) { _ in
            engine?.authenticationLost()
            sessionExpiredHandler?()
        })
    }

    // MARK: - Event bridging

    private static func publish(_ event: SyncEngineEvent) {
        let center = NotificationCenter.default
        switch event {
        case .operationChanged(let op):
            center.post(name: .kabbaSyncOperationChanged, object: nil,
                        userInfo: ["operationId": op.id, "state": op.state.rawValue])
            center.post(name: .kabbaSyncQueueChanged, object: nil)
        case .pauseChanged(let pause):
            center.post(name: .kabbaSyncPauseChanged, object: nil, userInfo: ["pause": pause.rawValue])
            center.post(name: .kabbaSyncQueueChanged, object: nil)
        case .drainFinished:
            center.post(name: .kabbaSyncQueueChanged, object: nil)
        }
    }
}
