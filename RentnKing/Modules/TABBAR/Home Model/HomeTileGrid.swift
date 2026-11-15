//
//  HomeTileGrid.swift
//  RentnKing
//
//  Home's eight tiles in one place (mobile issue #10, 2026-11-15). The
//  storyboard lays out the original tiles in three rows; Equipment Audit (the
//  storyboard's spare Inventory tile) and Suppliers (built in code) were each
//  added by moving views after the fact. Now the order is one table,
//  `HomeTile.rows`, and `installHomeTiles()` puts every tile in its row from
//  it, once, in viewDidLoad. Each tile moves as a whole — its icon, label,
//  border and the button that covers it — so a tap always reaches the tile it
//  lands on.
//
//  Four rows have to fit between the navigation bar and the tab bar on every
//  phone, so the grid is centred in that area (not the whole screen) and the
//  tile size is the smaller of the usual size and what four rows allow.
//

import UIKit

enum HomeTile: String, CaseIterable {
    case queueLine, dispatch, orders, schedule, equipmentAudit, equipment, crm, suppliers

    /// Home, top to bottom, left to right.
    static let rows: [[HomeTile]] = [
        [.queueLine, .dispatch],
        [.orders, .schedule],
        [.equipmentAudit, .equipment],
        [.crm, .suppliers],
    ]

    /// The tile's button (UI tests and VoiceOver). home.equipmentAudit and home.suppliers predate this table.
    var buttonIdentifier: String { "home.\(rawValue)" }

    var title: String {
        switch self {
        case .queueLine: return str.strInStore
        case .dispatch: return str.strDispatch
        case .orders: return str.strOrders
        case .schedule: return str.strSchedule
        case .equipmentAudit: return "Equipment Audit"
        case .equipment: return str.strEquipment
        case .crm: return str.strCRM
        case .suppliers: return "Suppliers"
        }
    }
}

extension HomeViewController {

    private static let tileSpacing: CGFloat = 16
    private static let gridIdentifier = "home.grid"

    /// The view that is `tile` on screen (the storyboard's outlets, plus the Suppliers tile once built).
    func homeTileView(_ tile: HomeTile) -> UIView? {
        switch tile {
        case .queueLine: return viewInStore
        case .dispatch: return viewDispatch
        case .orders: return viewEcommerce
        case .schedule: return viewSchedule
        case .equipmentAudit: return viewInventory
        case .equipment: return viewProducts
        case .crm: return viewCRM
        case .suppliers: return supplierDirectoryTile
        }
    }

    /// The button that covers `tile` — the control a tap on the tile actually reaches.
    func homeTileButton(_ tile: HomeTile) -> UIButton? {
        homeTileView(tile)?.subviews.compactMap { $0 as? UIButton }.last
    }

    /// viewDidLoad: every tile in its row from `HomeTile.rows`, once.
    func installHomeTiles() {
        guard let firstRow = viewInStore.superview as? UIStackView,
              let grid = firstRow.superview as? UIStackView,
              grid.accessibilityIdentifier != Self.gridIdentifier else { return }
        grid.accessibilityIdentifier = Self.gridIdentifier

        prepareEquipmentAuditTile()
        let suppliers = makeSupplierDirectoryTile()

        // Strong references while tiles change rows (the outlets are weak).
        var views: [HomeTile: UIView] = [.suppliers: suppliers]
        for tile in HomeTile.allCases where tile != .suppliers { views[tile] = homeTileView(tile) }
        let placed = Set(views.values.map(ObjectIdentifier.init))

        // The storyboard's rows, top to bottom; a row the table needs beyond them is added below the last.
        var rows = grid.arrangedSubviews.compactMap { $0 as? UIStackView }
            .filter { row in row.arrangedSubviews.contains { placed.contains(ObjectIdentifier($0)) } }
        for (index, tiles) in HomeTile.rows.enumerated() {
            if index == rows.count, let last = rows.last, let position = grid.arrangedSubviews.firstIndex(of: last) {
                let row = UIStackView()
                row.axis = firstRow.axis
                row.distribution = firstRow.distribution
                row.alignment = firstRow.alignment
                row.spacing = firstRow.spacing
                grid.insertArrangedSubview(row, at: position + 1)
                rows.append(row)
            }
            for (column, tile) in tiles.enumerated() {
                guard let view = views[tile] else { continue }
                rows[index].insertArrangedSubview(view, at: column)   // moves it out of its old row
                view.isHidden = false
            }
        }
        // Anything else the storyboard left in these rows (the retired Time Clock tile) stays out of sight.
        for row in rows {
            for view in row.arrangedSubviews where !placed.contains(ObjectIdentifier(view)) { view.isHidden = true }
        }

        for tile in HomeTile.allCases {
            guard let button = homeTileButton(tile) else { continue }
            if button.accessibilityIdentifier == nil { button.accessibilityIdentifier = tile.buttonIdentifier }
            button.accessibilityLabel = tile.title
        }

        centreGridBetweenBars(grid)
    }

    /// viewDidLayoutSubviews: tiles no larger than four rows allow.
    func fitHomeGridToFourRows() {
        guard let guide = view.layoutGuides.first(where: { $0.identifier == "home.gridArea" }), guide.layoutFrame.height > 0 else { return }
        let rows = CGFloat(HomeTile.rows.count)
        let available = guide.layoutFrame.height - 2 * 12
        let fitting = floor((available - (rows - 1) * Self.tileSpacing) / rows)
        let size = min(manageWidth(size: 150), fitting)
        if abs(con_viewSize.constant - size) > 0.5 { con_viewSize.constant = size }
    }

    private func centreGridBetweenBars(_ grid: UIStackView) {
        guard let navigationBar = con_NavigationBar.firstItem as? UIView else { return }
        let guide = UILayoutGuide()
        guide.identifier = "home.gridArea"
        view.addLayoutGuide(guide)
        let bottom: NSLayoutYAxisAnchor = (con_Upload.firstItem as? UIView)?.topAnchor ?? view.safeAreaLayoutGuide.bottomAnchor
        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            guide.bottomAnchor.constraint(equalTo: bottom),
        ])
        // Replace the storyboard's "centred on the whole screen".
        view.constraints
            .filter { ($0.firstItem === grid && $0.firstAttribute == .centerY) || ($0.secondItem === grid && $0.secondAttribute == .centerY) }
            .forEach { $0.isActive = false }
        grid.centerYAnchor.constraint(equalTo: guide.centerYAnchor).isActive = true
    }
}
