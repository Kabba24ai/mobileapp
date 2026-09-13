//
//  QueueLinePresentation.swift
//  RentnKing
//
//  Queue Line board presentation rules that earn their own tests:
//    • Delivery / In-Store icon + label pairing — ONE predicate, so the icon
//      and the text can never disagree.
//    • The card's single Update button — solid at rest; the moment it is
//      tapped it turns hollow and disabled (before any navigation starts), so
//      a half-second push delay cannot be tapped twice.
//

import UIKit

/// Truck vs In-Store presentation for a Queue Line card — the convention the
/// Schedule, Dispatch, Driver Checklist and Order Details screens already use:
/// Truck → `icon_delivery_pending` (truck), Store → `icon_store` (storefront).
enum QueueLineTransportPresentation {

    static let truckIcon  = "icon_delivery_pending"
    static let storeIcon  = "icon_store"
    static let truckLabel = "Delivery : "
    static let storeLabel = "In Store : "

    /// The board's classification is unchanged: only a "Store" transport mode is
    /// In-Store; everything else (Truck, or a feed that omitted the mode) is a
    /// truck delivery — exactly what the label has always said.
    static func isInStore(_ transportMode: String?) -> Bool { transportMode == "Store" }

    static func icon(for transportMode: String?) -> String {
        isInStore(transportMode) ? storeIcon : truckIcon
    }

    static func label(for transportMode: String?) -> String {
        isInStore(transportMode) ? storeLabel : truckLabel
    }
}

/// The ONE action on a Pending / Staged card: Update → the main Delivery Checklist.
///
/// Solid (high-emphasis) by default. `beginLoading()` flips it to a hollow,
/// disabled outline synchronously — the caller does this on the tap, BEFORE
/// pushing — and `reset()` restores it when the board comes back.
final class QueueLineUpdateButton: UIButton {

    enum Look: Equatable { case solid, pressed, loading }

    static let accessibilityID = "queueLineUpdate"
    static let title = "Update"

    /// The card this button belongs to.
    var item: QueueLineModel?

    private(set) var look: Look = .solid

    private let fill: UIColor
    private let ink: UIColor

    init(fill: UIColor, ink: UIColor) {
        self.fill = fill
        self.ink = ink
        super.init(frame: .zero)

        setTitle(Self.title, for: .normal)
        setTitle(Self.title, for: .disabled)
        titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 14)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        layer.cornerRadius = 8
        layer.borderWidth = 1.5
        clipsToBounds = true
        accessibilityIdentifier = Self.accessibilityID
        accessibilityLabel = Self.title

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        // Never squeezed by a long customer name — the name truncates instead.
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        apply(.solid)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Finger-down / finger-up feedback. Never overrides the loading look.
    override var isHighlighted: Bool {
        didSet {
            guard look != .loading else { return }
            apply(isHighlighted ? .pressed : .solid)
        }
    }

    /// The tap registered: hollow + disabled, immediately.
    func beginLoading() {
        isEnabled = false
        apply(.loading)
    }

    /// Back to the solid, tappable default.
    func reset() {
        isEnabled = true
        apply(.solid)
    }

    private func apply(_ newLook: Look) {
        look = newLook
        switch newLook {
        case .solid:
            backgroundColor = fill
            layer.borderColor = fill.cgColor
            setTitleColor(ink, for: .normal)
        case .pressed:
            backgroundColor = fill.withAlphaComponent(0.7)
            layer.borderColor = fill.withAlphaComponent(0.7).cgColor
            setTitleColor(ink, for: .normal)
        case .loading:
            backgroundColor = .clear
            layer.borderColor = fill.cgColor
            setTitleColor(fill, for: .normal)
            setTitleColor(fill, for: .disabled)
        }
    }
}
