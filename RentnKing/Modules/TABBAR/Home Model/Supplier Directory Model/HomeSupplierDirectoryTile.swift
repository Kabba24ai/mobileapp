//
//  HomeSupplierDirectoryTile.swift
//  RentnKing
//
//  The Home entry for the Supplier Directory (2026-11-13). Home's fourth row
//  (Equipment Audit) had an empty slot beside it; Suppliers takes it, built in
//  code to match the storyboard tiles (icon over label, cyan border, rounded),
//  so every existing tile keeps its place.
//
//  Like Equipment Audit, the tile is shown to everyone signed in: the login
//  carries no permissions, so Kabba decides — an account outside the employee
//  policy is told so on the next screen.
//

import UIKit

extension HomeViewController {

    private static let supplierTileTag = 70_106

    /// viewDidLoad, after installEquipmentAuditTile(): the empty slot in the audit row becomes Suppliers.
    func installSupplierDirectoryTile() {
        guard let row = viewInventory.superview as? UIStackView,
              row.arrangedSubviews.count == 2,
              let spacer = row.arrangedSubviews.last,
              spacer !== viewInventory,
              row.viewWithTag(Self.supplierTileTag) == nil else { return }

        let tile = UIView()
        tile.tag = Self.supplierTileTag
        tile.backgroundColor = .clear
        tile.viewBorderCorneRadius(borderColour: .secondary)
        tile.viewCorneRadius(radius: 15, isRound: false)
        tile.accessibilityIdentifier = "home.suppliers.tile"

        let icon = UIImageView(image: UIImage(systemName: "shippingbox", withConfiguration: UIImage.SymbolConfiguration(weight: .regular)))
        icon.contentMode = .scaleAspectFit
        imgColor(imgColor: icon, colorHex: .secondary)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 50),
            icon.widthAnchor.constraint(equalTo: icon.heightAnchor, multiplier: 41.0 / 40.0),
        ])

        let label = UILabel()
        label.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "Suppliers")
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75

        let content = UIStackView(arrangedSubviews: [icon, label])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 8
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(content)

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "home.suppliers"
        button.accessibilityLabel = "Suppliers"
        button.addTarget(self, action: #selector(btnSuppliersClicked), for: .touchUpInside)
        tile.addSubview(button)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: tile.topAnchor),
            button.bottomAnchor.constraint(equalTo: tile.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
        ])

        row.removeArrangedSubview(spacer)
        spacer.removeFromSuperview()
        row.addArrangedSubview(tile)
    }

    @objc func btnSuppliersClicked() {
        navigationController?.pushViewController(SupplierListViewController(), animated: true)
    }
}
