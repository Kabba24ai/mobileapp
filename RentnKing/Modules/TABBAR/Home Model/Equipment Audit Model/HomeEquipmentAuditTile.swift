//
//  HomeEquipmentAuditTile.swift
//  RentnKing
//
//  The Home entry for the mobile Equipment Audit (2026-10-05). Home's grid is
//  a storyboard of square tiles; its Inventory tile was laid out but never
//  wired. It becomes "Equipment Audit" (the web module lives under Inventory).
//  Where it sits is HomeTileGrid's table (mobile issue #10): row 3, beside
//  Equipment.
//
//  The tile is shown to everyone signed in: the login response carries no
//  permissions, so Laravel decides — an account without View Equipment
//  Audits gets a plain explanation on the next screen.
//

import UIKit

extension HomeViewController {

    private static let auditTileTag = 70_105

    /// installHomeTiles(): the storyboard's hidden Inventory tile becomes a tappable Equipment Audit tile.
    func prepareEquipmentAuditTile() {
        guard viewInventory.viewWithTag(Self.auditTileTag) == nil else { return }
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
    }

    /// setTheView: the tile's own label and icon (setTheView restyles every tile on each appear).
    func styleEquipmentAuditTile() {
        imgInventory.image = UIImage(systemName: "checklist", withConfiguration: UIImage.SymbolConfiguration(weight: .regular))
        imgColor(imgColor: imgInventory, colorHex: .secondary)
        lblInventory.text = "Equipment Audit"
        lblInventory.adjustsFontSizeToFitWidth = true
        lblInventory.minimumScaleFactor = 0.75
    }

    @objc func btnEquipmentAuditClicked() {
        navigationController?.pushViewController(EquipmentAuditListViewController(), animated: true)
    }
}
