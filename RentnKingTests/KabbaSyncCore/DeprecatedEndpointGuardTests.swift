import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 5 — the new build must not call retired routes for migrated workflows. Two layers:
/// the engine refuses at runtime (parks visibly), and a structural scan of the Sync sources.
final class DeprecatedEndpointGuardTests: XCTestCase {

    private struct RetiredPathHandler: SyncOperationHandler {
        static let type = "test.retired"
        let path: String
        let body: JSONValue?
        let allowed: Bool
        var operationType: String { RetiredPathHandler.type }
        var mayUseDeprecatedEndpoint: Bool { allowed }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            SyncHTTPRequest(method: "POST", path: path, headers: [:], jsonBody: body ?? operation.payload, operationId: operation.id)
        }
    }

    private var dir: URL!
    private var client: FakeSyncHTTPClient!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
        client.defaultResult = Fixtures.ok()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func run(path: String, body: JSONValue? = nil, allowed: Bool = false) throws -> SyncOperation? {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let e = SyncEngine(store: store, httpClient: client, handlers: [RetiredPathHandler(path: path, body: body, allowed: allowed)],
                           policy: SyncRetryPolicy(backoffSchedule: [0.05]))
        let op = try e.enqueue(type: RetiredPathHandler.type, payload: Fixtures.payload, identity: SyncBusinessIdentity(), capturedAt: Date())
        waitUntil("settled") { [.synced, .needsAttention].contains(e.operation(id: op.id)?.state ?? .pending) }
        return e.operation(id: op.id)
    }

    func testTheEngineParksAnOperationThatTargetsARetiredRouteWithoutSendingIt() throws {
        for path in ["orders/customer-checklists/save-delivery", "/orders/customer-checklists/save-return", "orders/upload-media?x=1"] {
            let op = try run(path: path)
            XCTAssertEqual(op?.state, .needsAttention, path)
            XCTAssertTrue(op?.attentionReason?.contains("retired API route") ?? false, path)
            XCTAssertEqual(client.requestCount, 0, "\(path) must never reach the network")
            try? FileManager.default.removeItem(at: dir); dir = Fixtures.tempDirectory()
        }
    }

    func testTheOneLegacyMigrationAdapterMayStillDrainOldQueuedItems() throws {
        let op = try run(path: "orders/customer-checklists/save-delivery", allowed: true)
        XCTAssertEqual(op?.state, .synced)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testOnlyTheCompletionClaimOfDeliveryPickupInputsIsRetired() throws {
        let canonical = try run(path: "orders/schedules/update-delivery-pickup-inputs", body: .object(["order_product_unique_id": .string("X"), "complete_leg": .bool(false)]))
        XCTAssertEqual(canonical?.state, .synced, "complete_leg=false is the canonical inputs-only use")
        XCTAssertEqual(client.requestCount, 1)

        try? FileManager.default.removeItem(at: dir); dir = Fixtures.tempDirectory()
        let completing = try run(path: "orders/schedules/update-delivery-pickup-inputs", body: .object(["order_product_unique_id": .string("X")]))
        XCTAssertEqual(completing?.state, .needsAttention, "an absent complete_leg is the legacy completion claim")
        XCTAssertEqual(client.requestCount, 1, "not sent")
    }

    func testTheCanonicalRequestFactoriesNeverProduceARetiredPath() {
        XCTAssertFalse(DeprecatedMobileEndpoints.isDeprecated(path: MediaRequestFactory.path, jsonBody: nil))
        XCTAssertFalse(DeprecatedMobileEndpoints.isDeprecated(path: "orders/checklists/ORD-CHK-1/complete", jsonBody: nil))
        XCTAssertFalse(DeprecatedMobileEndpoints.isDeprecated(path: "queue-line/ORD-SCH-1/mark-staged", jsonBody: nil))
        XCTAssertTrue(DeprecatedMobileEndpoints.isDeprecated(path: LegacyChecklistQueueMigration.path(for: .delivery), jsonBody: nil))
        XCTAssertTrue(DeprecatedMobileEndpoints.isDeprecated(path: LegacyChecklistQueueMigration.path(for: .return), jsonBody: nil))
    }

    // MARK: Structural — the sources themselves

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func swiftFiles(under relative: String) -> [URL] {
        let base = repoRoot.appendingPathComponent(relative)
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testNoSyncSourceOutsideTheMigrationAdapterNamesARetiredRouteLiteral() throws {
        let files = swiftFiles(under: "RentnKing/Sync")
        try XCTSkipIf(files.isEmpty, "sources not available in this checkout")
        let allowed: Set<String> = ["DeprecatedEndpoints.swift", "LegacyChecklistQueueMigration.swift"]
        let literals = DeprecatedMobileEndpoints.paths.map { "\"\($0)\"" }
        for file in files where !allowed.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file)
            for literal in literals {
                XCTAssertFalse(source.contains(literal), "\(file.lastPathComponent) names \(literal) — migrated workflows must use the canonical route")
            }
        }
    }

    func testTheOldAPIURLFamilyIsGoneFromTheClient() throws {
        let global = repoRoot.appendingPathComponent("RentnKing/GlobalMain.swift")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: global.path), "sources not available in this checkout")
        let source = try String(contentsOf: global)
        XCTAssertFalse(source.contains("func oldAPI("), "Url.oldAPI must not come back")
        let retired = ["categoryProducts", "searchProducts", "productsDetaisl", "placeORder", "timeClockSetting", "statusList", "employeeStatus",
                       "updateEmployeeStatus", "maintenanceProfile", "inventoryClass", "inventoryStatus", "inventoryService"]
        for member in retired {
            XCTAssertFalse(source.contains("static var \(member): NSURL"), "Url.\(member) was retired")
        }
        // …and no screen still requests one (comments excluded).
        for file in swiftFiles(under: "RentnKing") where file.lastPathComponent != "GlobalMain.swift" {
            let lines = try String(contentsOf: file).split(separator: "\n")
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for member in retired where line.contains("Url.\(member).") {
                    XCTFail("\(file.lastPathComponent):\(index + 1) still requests the retired Url.\(member)")
                }
            }
        }
    }
}
