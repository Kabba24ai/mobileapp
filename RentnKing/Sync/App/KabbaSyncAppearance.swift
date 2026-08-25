//
//  KabbaSyncAppearance.swift
//  RentnKing — Sync App layer (app-specific glue)
//
//  Maps the app's design language (Colour.xcassets + Roboto) onto the
//  self-contained sync UI, and offers the one-line toast helper call sites use.
//

import UIKit

extension SyncStatusTheme {
    /// Kabba's dark palette: cyan accent, gray secondary text, Roboto.
    static var kabba: SyncStatusTheme {
        SyncStatusTheme(
            background: UIColor.background ?? .black,
            card: (UIColor.backgroundDark ?? UIColor.background ?? .black),
            accent: UIColor.secondary ?? .systemTeal,
            text: .white,
            secondaryText: UIColor.gray.withAlphaComponent(0.9),
            success: .systemGreen,
            warning: .systemOrange,
            bold: { SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: Double($0)) },
            regular: { SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: Double($0)) }
        )
    }
}

extension KabbaSync {
    /// Shows the "Saved · Pending Sync → Synced / Needs Attention" toast for an operation
    /// that was just enqueued. No-op when the engine is unavailable or the id is nil.
    static func showStatusToast(for operationId: String?) {
        guard let operationId = operationId else { return }
        DispatchQueue.main.async {
            SyncStatusToast.show(operationId: operationId,
                                 in: GlobalMainConstants.appDelegate?.window,
                                 theme: .kabba)
        }
    }
}
