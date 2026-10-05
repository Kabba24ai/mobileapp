//
//  HomeEquipmentAuditTile.swift
//  RentnKing
//
//  The Home entry for the mobile Equipment Audit (2026-10-05). Home's grid is
//  a storyboard of square tiles; its Inventory tile was laid out but never
//  wired. It becomes "Equipment Audit" (the web module lives under Inventory)
//  in a row of its own, so the existing rows keep their tiles and their
//  order.
//
//  A fourth row has to fit between the navigation bar and the tab bar on
//  every phone, so the grid is centred in that area (not the whole screen)
//  and the tile size is the smaller of the usual size and what four rows
//  allow — unchanged in practice on larger phones, a little smaller on an SE.
//
//  The tile is shown to everyone signed in: the login response carries no
//  permissions, so Laravel decides — an account without View Equipment
//  Audits gets a plain explanation on the next screen.
//

import UIKit

extension HomeViewController {

    private static let tileSpacing: CGFloat = 16
    private static let rows: CGFloat = 4
    private static let auditTileTag = 70_105

    /// viewDidLoad: move the Inventory tile into its own row and make it tappable.
    func installEquipmentAuditTile() {
        guard let row = viewInventory.superview as? UIStackView,
              let column = row.superview as? UIStackView,
              let rowIndex = column.arrangedSubviews.firstIndex(of: row),
              viewInventory.viewWithTag(Self.auditTileTag) == nil else { return }

        row.removeArrangedSubview(viewInventory)
        viewInventory.removeFromSuperview()
        let auditRow = UIStackView(arrangedSubviews: [viewInventory, UIView()])
        auditRow.axis = .horizontal
        auditRow.distribution = .fillEqually
        auditRow.spacing = row.spacing
        column.insertArrangedSubview(auditRow, at: rowIndex + 1)
        viewInventory.isHidden = false

        let button = UIButton(type: .custom)
        button.tag = Self.auditTileTag
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "home.equipmentAudit"
        button.accessibilityLabel = "Equipment Audit"
        button.addTarget(self, action: #selector(btnEquipmentAuditClicked), for: .touchUpInside)
        viewInventory.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: viewInventory.topAnchor),
            button.bottomAnchor.constraint(equalTo: viewInventory.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: viewInventory.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: viewInventory.trailingAnchor),
        ])

        lblInventory.numberOfLines = 2
        lblInventory.textAlignment = .center
        lblInventory.widthAnchor.constraint(lessThanOrEqualTo: viewInventory.widthAnchor, constant: -16).isActive = true

        centreGridBetweenBars(column)
    }

    /// setTheView: the tile's own label and icon (setTheView restyles every tile on each appear).
    func styleEquipmentAuditTile() {
        imgInventory.image = UIImage(systemName: "checklist", withConfiguration: UIImage.SymbolConfiguration(weight: .regular))
        imgColor(imgColor: imgInventory, colorHex: .secondary)
        lblInventory.text = "Equipment Audit"
        lblInventory.adjustsFontSizeToFitWidth = true
        lblInventory.minimumScaleFactor = 0.75
    }

    /// viewDidLayoutSubviews: tiles no larger than four rows allow.
    func fitHomeGridToFourRows() {
        guard let guide = view.layoutGuides.first(where: { $0.identifier == "home.gridArea" }), guide.layoutFrame.height > 0 else { return }
        let available = guide.layoutFrame.height - 2 * 12
        let fitting = floor((available - (Self.rows - 1) * Self.tileSpacing) / Self.rows)
        let size = min(manageWidth(size: 150), fitting)
        if abs(con_viewSize.constant - size) > 0.5 { con_viewSize.constant = size }
    }

    private func centreGridBetweenBars(_ column: UIStackView) {
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
            .filter { ($0.firstItem === column && $0.firstAttribute == .centerY) || ($0.secondItem === column && $0.secondAttribute == .centerY) }
            .forEach { $0.isActive = false }
        column.centerYAnchor.constraint(equalTo: guide.centerYAnchor).isActive = true
    }

    @objc func btnEquipmentAuditClicked() {
        navigationController?.pushViewController(EquipmentAuditListViewController(), animated: true)
    }
}
