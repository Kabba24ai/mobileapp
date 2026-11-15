//
//  StagingTestHarness.swift
//  RentnKing — DEBUG ONLY
//
//  Phase 6A device acceptance. A UI test (RentnKingUITests) drives the real
//  sign-in / sign-out / session-recovery flows on a physical iPhone against a
//  controlled STAGING backend. The production company-code bootstrap
//  (LoginModel.getCustomerDataAPI → https://api.rentnking.com/api/admin/v1/clients)
//  cannot resolve a staging tenant, so — and ONLY when the app is launched with
//  the `-KabbaBaseURL` argument, which nothing but the UI test passes — this
//  seam points the app straight at the staging base URL and pre-fills the login
//  fields. It is compiled out of Release entirely (`#if DEBUG`) and is inert in
//  every normal Debug run (no `-KabbaBaseURL` ⇒ `isActive == false`). It never
//  weakens auth, never stores a credential, and changes nothing the server sees
//  beyond the base URL the operator's own login would have used.
//

#if DEBUG
import UIKit
import UserNotifications

enum StagingTestHarness {

    /// True only under a UI test that passed `-KabbaBaseURL <url>`.
    static var isActive: Bool { argument("KabbaBaseURL") != nil }

    /// `-Key Value` launch arguments land in the NSArgumentDomain of UserDefaults.
    static func argument(_ key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key), !value.isEmpty else { return nil }
        return value
    }

    /// Point the app at the staging base URL and pre-fill the login fields so a single
    /// Login tap authenticates — bypassing the production `clients` lookup. No-op unless active.
    static func applyToLogin(company: UITextField?, email: UITextField?, password: UITextField?) {
        guard isActive, let base = argument("KabbaBaseURL") else { return }
        UserDefaults.standard.baseURL = base
        company?.text  = argument("KabbaCompanyCode") ?? "KABBA"
        email?.text    = argument("KabbaEmail") ?? ""
        password?.text = argument("KabbaPassword") ?? ""
        print("[test-harness] staging base URL applied; company/email/password pre-filled")
    }

    /// The staging credentials the UI test passed. When present, the login must use THESE and
    /// the staging base URL directly — never the on-screen fields (a person may touch the device
    /// mid-test) and never the production company-code lookup.
    static func credentials() -> (email: String, password: String)? {
        guard isActive, let email = argument("KabbaEmail"), let password = argument("KabbaPassword") else { return nil }
        return (email, password)
    }

    /// Called at launch (AppDelegate) BEFORE the "already signed in?" routing. Under a UI test
    /// (`-KabbaBaseURL` present) it clears any prior session so the app always starts at the
    /// staging Login — never on a session left over from a manual production sign-in.
    static func resetSessionIfActive() {
        guard isActive else { return }
        UserDefaults.standard.user = nil
        UserDefaults.standard.accessToken = nil   // clears the shared Keychain item too
        UserDefaults.standard.baseURL = ""
        print("[test-harness] prior session cleared for a clean staging login")
    }

    // MARK: - Order notification taps (mobile issue #9)

    enum NotificationTrigger: String { case launch, home }

    /// The value after `-Key` exactly as passed: the arguments domain parses a value that starts
    /// with `{` as a property list, which a JSON payload is not.
    static func rawArgument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-" + key), index + 1 < args.count, !args[index + 1].isEmpty else { return nil }
        return args[index + 1]
    }
    private static var scheduledOrderNotification = false

    /// UI tests only: `-KabbaTestOrderNotification '<json>'` schedules a LOCAL notification that
    /// carries exactly a Kabba new-order push's data (`order_unique_id`, `order_id`,
    /// `order_number`). Tapping it reaches the same `userNotificationCenter(_:didReceive:)` a real
    /// push reaches, so the tests drive the real tap path with the app open, in the background or
    /// closed — on a simulator or an iPhone, with no APNs credentials. Options:
    /// `-KabbaTestNotificationAt launch|home` (default home: after sign-in),
    /// `-KabbaTestNotificationDelay <s>` (default 5), `-KabbaTestNotificationCount <n>` (default 1;
    /// several = the same order's notification arriving more than once),
    /// `-KabbaTestNotificationSpacing <s>` between them (default 2). Once per process.
    static func scheduleOrderNotificationIfRequested(trigger: NotificationTrigger) {
        guard !scheduledOrderNotification,
              let json = rawArgument("KabbaTestOrderNotification"),
              (argument("KabbaTestNotificationAt") ?? NotificationTrigger.home.rawValue) == trigger.rawValue,
              let data = json.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        scheduledOrderNotification = true
        let delay = max(1, Double(argument("KabbaTestNotificationDelay") ?? "") ?? 5)
        let count = max(1, min(5, Int(argument("KabbaTestNotificationCount") ?? "") ?? 1))
        let spacing = max(1, Double(argument("KabbaTestNotificationSpacing") ?? "") ?? 2)
        var userInfo: [String: String] = [:]
        for (key, value) in payload { userInfo[key] = "\(value)" }
        for index in 0..<count {
            let content = UNMutableNotificationContent()
            content.title = "New Order Placed \(userInfo["order_number"] ?? "")"
            content.body = userInfo["body"] ?? "Kabba UI test notification"
            content.userInfo = userInfo
            content.sound = .default
            let request = UNNotificationRequest(identifier: "kabba-test-order-\(index)-\(UUID().uuidString)",
                                                content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay + Double(index) * spacing, repeats: false))
            UNUserNotificationCenter.current().add(request) { error in
                print("[test-harness] order notification \(index + 1)/\(count) in \(delay)s: \(error.map { "\($0)" } ?? "scheduled")")
            }
        }
    }
}
#endif
