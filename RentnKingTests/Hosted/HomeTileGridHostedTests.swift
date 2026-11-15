//
//  HomeTileGridHostedTests.swift
//  RentnKingHostedTests — Home's eight tiles (mobile issue #10, 2026-11-15)
//
//  The real Home scene from Home.storyboard, laid out at each supported iPhone
//  size: the owner's four rows in order, every tile the same size inside the
//  area between the navigation bar and the tab bar, each tile's own button
//  under the finger wherever the tile now sits, and that button opening the
//  tile's feature.
//

import XCTest
@testable import RentnKing

final class HomeTileGridHostedTests: XCTestCase {

    /// iPhone SE (3rd gen), 13 mini, 17, 17 Pro Max — portrait points (Home is portrait-only).
    private let sizes: [(name: String, size: CGSize)] = [
        ("iPhone SE", CGSize(width: 375, height: 667)),
        ("iPhone 13 mini", CGSize(width: 375, height: 812)),
        ("iPhone 17", CGSize(width: 393, height: 852)),
        ("iPhone 17 Pro Max", CGSize(width: 440, height: 956)),
    ]

    private let destinations: [HomeTile: UIViewController.Type] = [
        .queueLine: QueueLineViewController.self,
        .dispatch: DispatchListViewController.self,
        .orders: OrderListViewController.self,
        .schedule: ScheduleListViewController.self,
        .equipmentAudit: EquipmentAuditListViewController.self,
        .equipment: MachineProfileViewController.self,
        .crm: CRMListViewController.self,
        .suppliers: SupplierListViewController.self,
    ]

    private func home(_ size: CGSize = CGSize(width: 393, height: 852)) throws -> (HomeViewController, UINavigationController) {
        let home = try XCTUnwrap(UIStoryboard(name: "Home", bundle: nil).instantiateViewController(withIdentifier: "HomeViewController") as? HomeViewController)
        let nav = UINavigationController(rootViewController: home)
        home.loadViewIfNeeded()
        home.setTheView()
        home.view.frame = CGRect(origin: .zero, size: size)
        for _ in 0..<3 { home.view.setNeedsLayout(); home.view.layoutIfNeeded() }   // the tile size settles in viewDidLayoutSubviews
        return (home, nav)
    }

    private func frame(_ tile: HomeTile, in home: HomeViewController, file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        let view = try XCTUnwrap(home.homeTileView(tile), "\(tile) is on Home", file: file, line: line)
        return view.convert(view.bounds, to: home.view)
    }

    private func labels(in view: UIView) -> [String] {
        ((view as? UILabel)?.text.map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    func testTheOrderIsTheOwnersFourRows() {
        XCTAssertEqual(HomeTile.rows, [[.queueLine, .dispatch], [.orders, .schedule], [.equipmentAudit, .equipment], [.crm, .suppliers]])
        XCTAssertEqual(Set(HomeTile.rows.joined()), Set(HomeTile.allCases), "every tile once")
        XCTAssertEqual(HomeTile.rows.joined().count, 8)
    }

    func testAtEverySupportedSizeTheEightTilesSitInTheirRowsSameSizeBetweenTheBars() throws {
        for (name, size) in sizes {
            let (home, _) = try home(size)
            var previousBottom = -CGFloat.infinity
            var tileSize: CGSize?
            for (r, row) in HomeTile.rows.enumerated() {
                let left = try frame(row[0], in: home), right = try frame(row[1], in: home)
                XCTAssertEqual(left.minY, right.minY, accuracy: 0.5, "\(name) row \(r + 1): one row")
                XCTAssertLessThan(left.maxX, right.minX, "\(name) row \(r + 1): \(row[0]) left of \(row[1])")
                XCTAssertGreaterThan(left.minY, previousBottom, "\(name) row \(r + 1) below row \(r)")
                previousBottom = left.maxY
                for f in [left, right] {
                    XCTAssertGreaterThan(f.width, 60, "\(name): a real tile")
                    if let tileSize { XCTAssertEqual(f.size.width, tileSize.width, accuracy: 0.5); XCTAssertEqual(f.size.height, tileSize.height, accuracy: 0.5) }
                    tileSize = f.size
                    XCTAssertGreaterThanOrEqual(f.minX, 0, name)
                    XCTAssertLessThanOrEqual(f.maxX, size.width, "\(name): nothing off the side")
                }
            }
            let navigationBar = try XCTUnwrap(home.con_NavigationBar.firstItem as? UIView)
            let top = navigationBar.convert(navigationBar.bounds, to: home.view).maxY
            XCTAssertGreaterThanOrEqual(try frame(.queueLine, in: home).minY, top, "\(name): below the navigation bar")
            XCTAssertLessThanOrEqual(previousBottom, size.height, "\(name): all four rows on screen")
        }
    }

    func testEachTileKeepsItsLabelIconAndLook() throws {
        let (home, _) = try home()
        let border = try XCTUnwrap(home.homeTileView(.queueLine)).layer
        for tile in HomeTile.allCases {
            let view = try XCTUnwrap(home.homeTileView(tile))
            XCTAssertTrue(labels(in: view).contains(tile.title), "\(tile) is labelled \(tile.title)")
            XCTAssertFalse(view.isHidden)
            XCTAssertEqual(view.layer.cornerRadius, 15, "\(tile)")
            XCTAssertEqual(view.layer.borderWidth, border.borderWidth, "\(tile)")
            XCTAssertEqual(view.layer.borderColor, border.borderColor, "\(tile): the same cyan border")
            let icon = try XCTUnwrap(view.subviews.compactMap { $0 as? UIStackView }.first?.arrangedSubviews.first as? UIImageView, "\(tile) icon")
            XCTAssertNotNil(icon.image, "\(tile) keeps its icon")
            XCTAssertEqual(icon.tintColor, UIColor.secondary, "\(tile)")
        }
        XCTAssertTrue(home.viewChecking.isHidden, "the retired Time Clock tile stays out of sight")
    }

    func testEachTilesOwnButtonIsUnderTheFingerAndOpensItsFeature() throws {
        for (name, size) in sizes {
            let (home, nav) = try home(size)
            for tile in HomeTile.allCases {
                let tileFrame = try frame(tile, in: home)
                let button = try XCTUnwrap(home.homeTileButton(tile), "\(name): \(tile) has a button")
                XCTAssertEqual(button.convert(button.bounds, to: home.view), tileFrame, "\(name): \(tile)'s button covers the whole tile")
                for point in [CGPoint(x: tileFrame.midX, y: tileFrame.midY), CGPoint(x: tileFrame.minX + 6, y: tileFrame.minY + 6),
                              CGPoint(x: tileFrame.maxX - 6, y: tileFrame.maxY - 6)] {
                    XCTAssertTrue(home.view.hitTest(point, with: nil) === button, "\(name): a tap on \(tile) at \(point) reaches \(tile)'s button")
                }
                XCTAssertEqual(button.accessibilityIdentifier, tile.buttonIdentifier, "\(name): stable id")
                XCTAssertEqual(button.accessibilityLabel, tile.title)

                button.sendActions(for: .touchUpInside)
                let opened = try XCTUnwrap(nav.topViewController, "\(name): \(tile) opened something")
                XCTAssertTrue(type(of: opened) == destinations[tile], "\(name): \(tile) opened \(type(of: opened))")
                nav.popToRootViewController(animated: false)
            }
        }
    }

    func testTheIdsTestsAndPhonesAlreadyUseAreUnchanged() throws {
        let (home, _) = try home()
        XCTAssertEqual(home.homeTileButton(.equipmentAudit)?.accessibilityIdentifier, "home.equipmentAudit")
        XCTAssertEqual(home.homeTileButton(.suppliers)?.accessibilityIdentifier, "home.suppliers")
        XCTAssertEqual(home.homeTileView(.suppliers)?.accessibilityIdentifier, "home.suppliers.tile")
    }

    func testInstallingAgainChangesNothing() throws {
        let (home, _) = try home()
        let grid = try XCTUnwrap(home.viewInStore.superview?.superview as? UIStackView)
        let snapshot = { grid.arrangedSubviews.map { row in [ObjectIdentifier(row)] + ((row as? UIStackView)?.arrangedSubviews.map(ObjectIdentifier.init) ?? []) } }
        let before = snapshot()
        home.installHomeTiles()
        XCTAssertEqual(snapshot(), before)
        func count(_ tag: Int) -> Int {
            func walk(_ v: UIView) -> Int { (v.tag == tag ? 1 : 0) + v.subviews.reduce(0) { $0 + walk($1) } }
            return walk(home.view)
        }
        XCTAssertEqual(count(70_106), 1, "one Suppliers tile")
        XCTAssertEqual(count(70_105), 1, "one Equipment Audit button")
        XCTAssertEqual(grid.arrangedSubviews.filter { !$0.isHidden }.count, 4, "four rows on screen")
    }
}
