//
//  ManualDispatchListCell.swift
//  RentnKing
//
//  The Manual Dispatch card inside the mixed Dispatch workday (Phase 6A).
//  Fully programmatic (registered in code — no storyboard prototype), indigo
//  accent matching the web Dispatch board's manual card: MANUAL chip +
//  type label, status pill, description, location, date/time. Tapping the row
//  opens ManualDispatchDetailViewController (status progression lives there).
//
//  Deliberately NOT the order-shaped DispatchListCell: a manual task has no
//  order number, customer, product or checklist, and must never render as a
//  broken "#0" order card.
//

import UIKit

final class ManualDispatchListCell: UITableViewCell {

    static let reuseId = "ManualDispatchListCell"

    private enum Palette {
        static let card   = UIColor(hex: 0x141C26)
        static let border = UIColor(hex: 0x2A3542)
        static let ink    = UIColor.primary
        static let subtle = UIColor(hex: 0x9AA4B2)
        static let indigo = UIColor(hex: 0x6366F1)
        static let blue   = UIColor(hex: 0x1B6EC2)
        static let green  = UIColor(hex: 0x1FA155)
        static let amber  = UIColor(hex: 0xD97706)
        static let red    = UIColor(hex: 0xDC2626)
    }

    private let card = UIView()
    private let accent = UIView()
    private let chipManual = PaddingLabelManual()
    private let chipTransfer = PaddingLabelManual()
    private let pillStatus = PaddingLabelManual()
    private let lblType = UILabel()
    private let lblDescription = UILabel()
    private let lblLocation = UILabel()
    private let lblDateTime = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        selectionStyle = .none
        build()
    }

    private func build() {
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.border.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        accent.backgroundColor = Palette.indigo
        accent.layer.cornerRadius = 2
        accent.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(accent)

        chipManual.text = "MANUAL"
        chipManual.font = .systemFont(ofSize: 10, weight: .bold)
        chipManual.textColor = Palette.indigo
        chipManual.backgroundColor = Palette.indigo.withAlphaComponent(0.18)
        chipManual.layer.cornerRadius = 5
        chipManual.layer.masksToBounds = true

        chipTransfer.text = "INVENTORY TRANSFER"
        chipTransfer.font = .systemFont(ofSize: 10, weight: .bold)
        chipTransfer.textColor = Palette.amber
        chipTransfer.backgroundColor = Palette.amber.withAlphaComponent(0.18)
        chipTransfer.layer.cornerRadius = 5
        chipTransfer.layer.masksToBounds = true
        chipTransfer.isHidden = true

        pillStatus.font = .systemFont(ofSize: 10, weight: .bold)
        pillStatus.layer.cornerRadius = 5
        pillStatus.layer.masksToBounds = true

        lblType.font = .systemFont(ofSize: 16, weight: .bold)
        lblType.textColor = Palette.ink
        lblType.numberOfLines = 1

        lblDescription.font = .systemFont(ofSize: 14)
        lblDescription.textColor = Palette.ink
        lblDescription.numberOfLines = 2

        lblLocation.font = .systemFont(ofSize: 13)
        lblLocation.textColor = Palette.subtle
        lblLocation.numberOfLines = 1

        lblDateTime.font = .systemFont(ofSize: 13, weight: .semibold)
        lblDateTime.textColor = Palette.indigo
        lblDateTime.numberOfLines = 1

        let chipRow = UIStackView(arrangedSubviews: [chipManual, chipTransfer, UIView(), pillStatus])
        chipRow.axis = .horizontal
        chipRow.spacing = 6
        chipRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [chipRow, lblType, lblDescription, lblLocation, lblDateTime])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            accent.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            accent.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            accent.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            accent.widthAnchor.constraint(equalToConstant: 4),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    func configure(with job: DispatchManualJob) {
        let isTransfer = job.dispatch_subtype == "inventory_transfer"
        chipTransfer.isHidden = !isTransfer

        if isTransfer {
            let movement = [job.origin_store?.name, job.destination_store?.name]
                .compactMap { ($0?.isEmpty == false) ? $0 : nil }
                .joined(separator: " → ")
            lblType.text = movement.isEmpty ? (job.type ?? "Manual Task") : movement
        } else {
            lblType.text = (job.type ?? "Manual Task").uppercased()
        }

        pillStatus.text = job.status ?? ""
        let statusColor: UIColor
        switch job.status {
        case DispatchManualStatus.completed: statusColor = Palette.green
        case DispatchManualStatus.cancelled: statusColor = Palette.red
        case DispatchManualStatus.onMyWay, DispatchManualStatus.arrived: statusColor = Palette.blue
        default: statusColor = Palette.subtle
        }
        pillStatus.textColor = statusColor
        pillStatus.backgroundColor = statusColor.withAlphaComponent(0.18)

        let description = job.description ?? ""
        lblDescription.text = description
        lblDescription.isHidden = description.isEmpty

        let location = (job.location_name?.isEmpty == false ? job.location_name : job.address) ?? "—"
        lblLocation.text = location

        let dateTime = [job.date, job.time]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " · ")
        lblDateTime.text = dateTime
        lblDateTime.isHidden = dateTime.isEmpty
    }
}

// Local hex initializer — same file-private convention as the other
// Manual Dispatch / Queue Line files.
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}
