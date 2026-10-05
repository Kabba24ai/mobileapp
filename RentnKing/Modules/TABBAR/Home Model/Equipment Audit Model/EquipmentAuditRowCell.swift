//
//  EquipmentAuditRowCell.swift
//  RentnKing
//
//  One unit on the mobile Equipment Audit, in two compact lines:
//
//      ✅  Cab - Tak TL8 — TAK-SS-14
//          Verified · Bon Aqua · John · 9:42 AM
//
//  The state reads from across the yard without reading a word: a green
//  check (Verified), a red X (Needs Verification), an amber warning
//  (Unresolved). Rows never move within a section when their state changes.
//

import UIKit

final class EquipmentAuditRowCell: UITableViewCell {

    static let reuseId = "equipmentAuditRow"

    enum Palette {
        static let page = UIColor.background
        static let ink = UIColor.primary
        static let subtle = UIColor(red: 0x9A / 255.0, green: 0xA4 / 255.0, blue: 0xB2 / 255.0, alpha: 1)
        static let border = UIColor(red: 0x2A / 255.0, green: 0x35 / 255.0, blue: 0x42 / 255.0, alpha: 1)
        static let green = UIColor(red: 0x1F / 255.0, green: 0xA1 / 255.0, blue: 0x55 / 255.0, alpha: 1)
        static let greenText = UIColor(red: 0x59 / 255.0, green: 0xD0 / 255.0, blue: 0x8A / 255.0, alpha: 1)
        static let red = UIColor(red: 0xE5 / 255.0, green: 0x48 / 255.0, blue: 0x4D / 255.0, alpha: 1)
        static let amber = UIColor.secondaryText
        static let cyan = UIColor.secondary
    }

    var onVerify: (() -> Void)?
    var onMore: (() -> Void)?

    private let stateIcon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let verifyButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = Palette.page
        contentView.backgroundColor = Palette.page
        selectionStyle = .none

        stateIcon.contentMode = .scaleAspectFit
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        stateIcon.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.numberOfLines = 0
        // Two compact lines per unit: the second shrinks a little rather than wrap.
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.8
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 3

        verifyButton.setTitle("Verify", for: .normal)
        verifyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        verifyButton.setTitleColor(.white, for: .normal)
        verifyButton.backgroundColor = Palette.green
        verifyButton.layer.cornerRadius = 8
        verifyButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        verifyButton.setContentHuggingPriority(.required, for: .horizontal)
        verifyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        verifyButton.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)

        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        moreButton.tintColor = Palette.cyan
        moreButton.accessibilityLabel = "More actions"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        spinner.color = Palette.cyan
        spinner.hidesWhenStopped = true

        let row = UIStackView(arrangedSubviews: [stateIcon, text, spinner, verifyButton, moreButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        let divider = UIView()
        divider.backgroundColor = Palette.border
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            stateIcon.widthAnchor.constraint(equalToConstant: 28),
            stateIcon.heightAnchor.constraint(equalToConstant: 28),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 52),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// - Parameters:
    ///   - verifyTitle: nil hides the Verify button (nothing to verify, or no permission).
    ///   - hasMore: whether the "…" menu has anything to offer.
    ///   - busy: an action on this unit is in flight — no second tap.
    func configure(row: EquipmentAuditRow, verifyTitle: String?, hasMore: Bool, busy: Bool) {
        let id = row.equipment.equipmentId
        let (symbol, tint, stateText): (String, UIColor, String) = {
            switch row.state {
            case .verified: return ("checkmark.circle.fill", Palette.green, "Verified")
            case .unresolved: return ("exclamationmark.triangle.fill", Palette.amber, "Unresolved")
            case .needsVerification: return ("xmark.circle.fill", Palette.red, "Needs Verification")
            }
        }()
        stateIcon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
        stateIcon.tintColor = tint
        stateIcon.accessibilityLabel = stateText
        stateIcon.isAccessibilityElement = true
        stateIcon.accessibilityIdentifier = "equipmentAudit.state.\(id)"

        // "Cab - Tak TL8 — TAK-SS-14", the Equipment ID emphasized.
        let title = NSMutableAttributedString(string: "\(row.equipment.name) — ",
                                              attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: Palette.ink])
        title.append(NSAttributedString(string: id, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .heavy), .foregroundColor: Palette.ink]))
        titleLabel.attributedText = title

        detailLabel.text = EquipmentAuditPresentation.rowDetail(row)
        detailLabel.textColor = row.state == .verified ? Palette.greenText : (row.state == .unresolved ? Palette.amber : Palette.subtle)

        verifyButton.isHidden = verifyTitle == nil || busy
        verifyButton.setTitle(verifyTitle, for: .normal)
        verifyButton.accessibilityIdentifier = "equipmentAudit.verify.\(id)"
        moreButton.isHidden = !hasMore || busy
        moreButton.accessibilityIdentifier = "equipmentAudit.more.\(id)"
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }

        accessibilityIdentifier = "equipmentAudit.row.\(id)"
    }

    @objc private func verifyTapped() { onVerify?() }
    @objc private func moreTapped() { onMore?() }
}
