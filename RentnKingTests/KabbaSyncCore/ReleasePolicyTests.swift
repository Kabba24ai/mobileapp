import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 5 — the server's release policy on the phone: decoding, header advice, build comparison,
/// and the persisted Update Required verdict that survives relaunch and clears itself the moment a
/// compatible build runs.
final class ReleasePolicyTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func body426(min: String = "1001", recommended: String? = "1002") -> Data {
        var data: [String: Any] = ["platform": "ios", "state": "update_required", "client_build": "1000", "client_version": "1.0.17",
                                   "minimum_supported_build": min, "recommended_version": "1.0.19",
                                   "update_message": "Please update the Kabba app to keep syncing.",
                                   "store_url": "https://apps.apple.com/us/app/kabba-ai/id6751110122", "update_required": true, "update_recommended": false]
        if let r = recommended { data["recommended_build"] = r }
        return Fixtures.json(["success": false, "message": "Please update the Kabba app to keep syncing.",
                              "error": ["code": "APP_UPDATE_REQUIRED", "message": "Please update.", "retryable": false],
                              "errors": [String: Any](), "error_code": "APP_UPDATE_REQUIRED", "data": data, "request_id": "srv-426"])
    }

    func testA426BodyDecodesIntoAPolicy() throws {
        let policy = try XCTUnwrap(ReleasePolicy.decode(envelopeData: body426()))
        XCTAssertEqual(policy.state, "update_required")
        XCTAssertTrue(policy.updateRequired)
        XCTAssertEqual(policy.minimumSupportedBuild, "1001")
        XCTAssertEqual(policy.recommendedBuild, "1002")
        XCTAssertEqual(policy.recommendedVersion, "1.0.19")
        XCTAssertEqual(policy.storeURL, "https://apps.apple.com/us/app/kabba-ai/id6751110122")
        XCTAssertEqual(policy.employeeMessage, "Please update the Kabba app to keep syncing.")
        XCTAssertTrue(policy.stillRequiresUpdate(forBuild: "1000"))
        XCTAssertFalse(policy.stillRequiresUpdate(forBuild: "1001"))
        XCTAssertFalse(policy.stillRequiresUpdate(forBuild: "1002"))
    }

    func testALoginReleaseBlockAndAnAppReleaseBodyDecodeToo() throws {
        let login = Fixtures.json(["success": true, "user": ["id": 1], "release": ["platform": "ios", "state": "no_policy", "update_required": false, "update_recommended": false]])
        let policy = try XCTUnwrap(ReleasePolicy.decode(envelopeData: login))
        XCTAssertEqual(policy.state, "no_policy")
        XCTAssertFalse(policy.updateRequired)
        XCTAssertFalse(policy.stillRequiresUpdate(forBuild: "1"), "no minimum, not required → nothing blocks")

        let release = Fixtures.json(["success": true, "data": ["platform": "ios", "state": "update_recommended", "minimum_supported_build": "1000", "recommended_build": "1002"]])
        let advice = try XCTUnwrap(ReleasePolicy.decode(envelopeData: release))
        XCTAssertTrue(advice.updateRecommended)
        XCTAssertFalse(advice.updateRequired)
        XCTAssertNil(ReleasePolicy.decode(envelopeData: Fixtures.json(["success": true, "data": ["items": []]])))
    }

    func testPolicyHeadersBecomeNonBlockingAdvice() {
        XCTAssertNil(UpdateAdvice.from(headers: ["X-Request-Id": "x"]), "no active policy → no advice")
        let advice = UpdateAdvice.from(headers: ["x-mobile-update": "recommended", "X-Mobile-Minimum-Build": "1000", "X-Mobile-Recommended-Build": "1002", "X-Mobile-Recommended-Version": "1.0.19"])
        XCTAssertEqual(advice?.level, .recommended)
        XCTAssertEqual(advice?.minimumBuild, "1000")
        XCTAssertEqual(advice?.recommendedBuild, "1002")
        XCTAssertEqual(UpdateAdvice.from(headers: ["X-Mobile-Update": "none", "X-Mobile-Minimum-Build": "1000"])?.level, .notNeeded)
        XCTAssertEqual(UpdateAdvice.from(headers: ["X-Mobile-Update": "required"])?.level, .required)
    }

    func testBuildNumbersCompareNumericallyBySegment() {
        XCTAssertEqual(BuildNumber.compare("1000", "1001"), -1)
        XCTAssertEqual(BuildNumber.compare("999", "1000"), -1)
        XCTAssertEqual(BuildNumber.compare("1001", "1001"), 0)
        XCTAssertEqual(BuildNumber.compare("1.0", "1.0.0"), 0)
        XCTAssertEqual(BuildNumber.compare("1.0.17", "1.0.18"), -1)
        XCTAssertEqual(BuildNumber.compare("2.0", "1.9.9"), 1)
        XCTAssertTrue(BuildNumber.isBelow("1001-beta", "1002"))
        XCTAssertTrue(BuildNumber.isAtLeast("1001", "1001"))
        XCTAssertEqual(MobileClientMetadata.sanitize("1.0.18 (dev)"), "1.0.18dev")
        XCTAssertEqual(MobileClientMetadata.sanitize(""), "0")
        XCTAssertEqual(Set(MobileClientMetadata(platform: "ios", version: "1.0.18", build: "1001", deviceId: "install-x").headers.keys),
                       ["X-Mobile-Platform", "X-Mobile-Version", "X-Mobile-Build", "X-Device-Id"])
    }

    // MARK: Persisted verdict

    func testTheUpdateRequiredVerdictSurvivesRelaunchWhileTheBuildIsStillTooOld() throws {
        let store = UpdateRequiredStore(directory: dir)
        XCTAssertEqual(store.resolution(currentBuild: "1000"), .none)

        let policy = try XCTUnwrap(ReleasePolicy.decode(envelopeData: body426()))
        let state = UpdateRequiredState(policy: policy, receivedAt: Date(timeIntervalSince1970: 1_700_000_000), blockedBuild: "1000", requestId: "srv-426")
        try store.save(state)

        // Relaunch of the SAME build: still required.
        let relaunched = UpdateRequiredStore(directory: dir)
        XCTAssertEqual(relaunched.resolution(currentBuild: "1000"), .stillRequired(state))
        // Nothing else lives in the file (queue and assets are elsewhere) — and no token.
        XCTAssertFalse(try Data(contentsOf: store.fileURL).isEmpty)

        // Relaunch after installing a compatible build: resolved → the gate clears and resumes.
        XCTAssertEqual(relaunched.resolution(currentBuild: "1001"), .resolved(state))
        relaunched.clear()
        XCTAssertEqual(UpdateRequiredStore(directory: dir).resolution(currentBuild: "1000"), .none)
    }

    func testAVerdictWithoutAMinimumFallsBackToTheBlockedBuild() throws {
        let policy = ReleasePolicy(platform: "ios", state: "update_required", clientBuild: "1000", clientVersion: nil, minimumSupportedBuild: nil,
                                   recommendedBuild: nil, recommendedVersion: nil, updateMessage: nil, storeURL: nil, updateRequired: true, updateRecommended: false)
        let store = UpdateRequiredStore(directory: dir)
        try store.save(UpdateRequiredState(policy: policy, receivedAt: Date(), blockedBuild: "1000", requestId: nil))
        XCTAssertTrue(policy.stillRequiresUpdate(forBuild: "1000"))
        XCTAssertFalse(policy.stillRequiresUpdate(forBuild: "1001"))
        if case .stillRequired = store.resolution(currentBuild: "1000") {} else { XCTFail("same build stays blocked") }
        if case .resolved = store.resolution(currentBuild: "1001") {} else { XCTFail("a newer build resolves") }
        XCTAssertEqual(policy.employeeMessage, "This version of the Kabba app is no longer supported. Please update.")
    }
}
