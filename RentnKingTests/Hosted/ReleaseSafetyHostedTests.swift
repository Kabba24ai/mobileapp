//
//  ReleaseSafetyHostedTests.swift
//  RentnKingHostedTests — release review 2026-09-30 (1.0.23): the three screen findings, and the
//  security finding.
//
//  1. Offline Dispatch while nothing was ever downloaded (always the case while the server has
//     no offline endpoints) shows the last live list, not "Dispatch isn't downloaded".
//  2. A Dispatch card button's tag can outlive the list it indexed (a feed answer replaces the
//     list before the table reloads): Call, Map, Assign Driver and the driver update never
//     index past the list.
//  3. The Orders list's sync redraw never reloads rows against a row count the table has not
//     seen yet.
//  4. The app bundle carries no private key (an APNs auth key shipped in every IPA through 1.0.22).
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class ReleaseSafetyHostedTests: XCTestCase {

    private var savedBaseURL: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://release-safety.invalid/api/admin/v1/"   // no real server
    }

    override func tearDown() {
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    /// A real Dispatch row, from the shared Laravel contract fixture.
    private func fixtureRow() throws -> SchedulesModel {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/dispatch_offline_packages.json")
        let root = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        let package = try XCTUnwrap(root["data"]?["packages"]?.arrayValue?.first)
        return try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: try XCTUnwrap(package["dispatch"]?["row"])))
    }

    private func dispatchScreen(online: Bool, snapshot: [SchedulesModel]) throws -> DispatchListViewController {
        let storyboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
        let vc = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "DispatchListViewController") as? DispatchListViewController)
        vc.isReachable = { online }
        vc.offlinePresentation = { _ in .notDownloaded }        // nothing ever downloaded (a server without the endpoints)
        vc.feedSnapshotOverride = { _ in snapshot }
        vc.operationsSnapshot = { [] }
        vc.cachedAssemblyReview = { _ in nil }
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return vc
    }

    // MARK: 1. Offline, nothing downloaded

    func testOfflineWithNothingDownloadedDispatchShowsTheLastLiveList() throws {
        let row = try fixtureRow()
        let vc = try dispatchScreen(online: false, snapshot: [row])

        vc.reloadDispatch(reconcile: nil)

        XCTAssertEqual(vc.arrDispatchList.map { $0.unique_id }, [row.unique_id], "the last live list, not an empty screen")
        XCTAssertTrue(vc.isFeedFallback)
    }

    func testOfflineWithNothingAtAllOnThePhoneStillSaysNotDownloaded() throws {
        let vc = try dispatchScreen(online: false, snapshot: [])

        vc.reloadDispatch(reconcile: nil)

        XCTAssertTrue(vc.arrDispatchList.isEmpty)
        XCTAssertFalse(vc.isFeedFallback, "no list to fall back to: the not-downloaded message stands")
    }

    /// Review of the fix: an offline reconcile outcome that lands on the snapshot fallback must keep
    /// the screen listening, so the next outcome — once the connection is back — reaches the live feed.
    func testAnOfflineOutcomeOnTheSnapshotKeepsListeningSoReconnectingReachesTheLiveFeed() throws {
        let row = try fixtureRow()
        let vc = try dispatchScreen(online: false, snapshot: [row])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        vc.reloadDispatch(reconcile: nil)
        XCTAssertTrue(vc.isShowingOfflineCache, "the snapshot fallback still listens for outcomes")

        vc.applyReconcileOutcome(failed: true)                    // the offline .foreground run fails
        XCTAssertTrue(vc.isShowingOfflineCache, "an offline outcome keeps the screen listening")
        XCTAssertEqual(vc.arrDispatchList.map { $0.unique_id }, [row.unique_id], "the snapshot stays on screen")

        vc.isReachable = { true }                                 // connection back; the .networkRestored run fails (404)
        vc.applyReconcileOutcome(failed: true)
        XCTAssertTrue(vc.feedReplacedCache, "online, the live feed replaces the snapshot")
        XCTAssertFalse(vc.isShowingOfflineCache)
    }

    // MARK: 2. Stale card tags

    func testACardTagThatOutlivedItsListNeverIndexesPastIt() throws {
        let vc = DispatchListViewController()
        vc.arrDispatchList = [try fixtureRow()]
        let stale = UIButton()
        stale.tag = 3                                             // built from a longer (company-wide) list

        vc.btnCallClicked(stale)
        vc.btnMapClicked(stale)
        vc.btnAssingDriverClicked(stale)
        vc.strAssignDriver(index: -1)

        // The driver update checks the index, then writes one main-queue hop later: a feed answer
        // can empty the list in between.
        vc.updateDriver(delivery_employee: nil, pickup_employee: nil, index: 0)
        vc.arrDispatchList = []
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        // Reaching this line is the proof: before the guards each call above trapped (index out of range).
        XCTAssertTrue(vc.arrDispatchList.isEmpty)
    }

    // MARK: 3. Orders list redraw

    func testTheOrdersRedrawNeverReloadsRowsAgainstAnUnseenRowCount() throws {
        let storyboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        let vc = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        vc.isLoading = false
        vc.arrOrderList = (1...3).compactMap { OrdersListModel(JSON: ["unique_id": "ORD-SAFE-\($0)", "order_number": "#\($0)"]) }
        vc.tblView.reloadData()
        vc.tblView.layoutIfNeeded()
        XCTAssertEqual(vc.tblView.numberOfRows(inSection: 0), 3)

        XCTAssertFalse((vc.tblView.indexPathsForVisibleRows ?? []).isEmpty, "precondition: rows are visible, so the redraw runs")
        // A page load begins: the data source now answers 10 placeholder rows, the table has not reloaded.
        vc.isLoading = true
        vc.redrawVisibleRows()                                    // before the fix: reloadRows against 3 vs 10

        XCTAssertEqual(vc.tblView.numberOfRows(inSection: 0), 3, "a mismatched table is left for the reload on its way")
        vc.tblView.reloadData()                                   // what setTheView does when the page settles
        XCTAssertEqual(vc.tblView.numberOfRows(inSection: 0), 10)
    }

    // MARK: 4. No private key in the app bundle

    /// Security review 2026-09-30: an APNs auth key (AuthKey_J9CRR5GHT3.p8) sat in Copy Bundle
    /// Resources and shipped inside every IPA. The app never reads a signing key — push goes
    /// through Firebase, which holds the APNs credential. What ships (the app and its extension,
    /// not the test bundles this run injects) carries no key file and no PEM private-key block.
    func testTheAppBundleCarriesNoPrivateKey() throws {
        let app = Bundle.main.bundleURL.standardizedFileURL
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey]))
        var scanned: [String] = []
        var offenders: [String] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "xctest" { enumerator.skipDescendants(); continue }   // injected by the test run, never shipped
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(app.path.count + 1))
            scanned.append(relative)
            if ["p8", "p12", "pfx"].contains(url.pathExtension.lowercased()) {
                offenders.append(relative)
                continue
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            if let head = try? handle.read(upToCount: 4096), let text = String(data: head, encoding: .utf8),
               text.range(of: "-----BEGIN [A-Z ]*PRIVATE KEY-----", options: .regularExpression) != nil {
                offenders.append(relative)
            }
        }

        XCTAssertTrue(scanned.contains("Info.plist"), "precondition: the scan walked the app bundle")
        XCTAssertEqual(offenders, [], "private key material in the app bundle")
    }
}
