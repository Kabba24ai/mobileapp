//
//  CustomerCallVerification.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Checklist → Call Customer (2026-09-29): the successful customer call
//  on a DELIVERY is three verified steps the app walks the driver through —
//  the delivery address, the equipment order (product + Product Options) and
//  one unloading situation — instead of four boxes the driver ticked from
//  memory. "Confirmed" is DERIVED from the three steps (never tapped);
//  "No Answer" stays the explicit, recorded escape.
//
//  The steps belong to the customer interaction, not to a machine: they live
//  in the driver mini-checklist record beside Fuel / Keys but are never bound
//  to `equipment_unique_id`, so an equipment switch leaves them alone
//  (locked rule: Call Customer stays; Fuel / Keys follow the effective unit).
//
//  The wire names (`address_verified`, `equipment_verified`,
//  `unloading_situation`, `unloading_note`) are the server's — identical in
//  the request, the stored leg block and the feed's `delivery_checklist`.
//

import Foundation

/// The one unloading situation the driver records with the customer.
public enum UnloadingSituation: Equatable {
    case easyAccess
    case unloadOnStreet
    case alternateLocation
    case addressInaccurate
    /// Free text — required non-blank (the step never completes on an empty note).
    case other(note: String)

    public static let otherCode = "other"
    /// The server's cap on the Other note (`DriverCallVerification::NOTE_MAX_LENGTH`): a
    /// longer note would be refused (422, non-retryable) and park the call and the departure.
    /// Counted in Unicode scalars — what Laravel's `max:` (`mb_strlen`) counts — never in
    /// grapheme clusters (an emoji with a skin tone is one cluster but two scalars).
    public static let noteMaxLength = 500

    /// The server's measure of a note's length.
    public static func length(of note: String) -> Int { note.unicodeScalars.count }

    /// The approved choices in display order, with the short titles the phone shows.
    public static let choices: [(code: String, title: String)] = [
        ("easy_access", "Easy access, room to turn around"),
        ("unload_on_street", "Unload on the street"),
        ("alternate_location", "Alternate unloading location"),
        ("address_inaccurate", "Address inaccurate — alternate location"),
        (otherCode, "Other"),
    ]

    public static var codes: [String] { choices.map(\.code) }

    /// nil for a code the server does not know (never a silent default).
    public init?(code: String, note: String? = nil) {
        switch code {
        case "easy_access": self = .easyAccess
        case "unload_on_street": self = .unloadOnStreet
        case "alternate_location": self = .alternateLocation
        case "address_inaccurate": self = .addressInaccurate
        case Self.otherCode: self = .other(note: Self.trimmed(note))
        default: return nil
        }
    }

    public var code: String {
        switch self {
        case .easyAccess: return "easy_access"
        case .unloadOnStreet: return "unload_on_street"
        case .alternateLocation: return "alternate_location"
        case .addressInaccurate: return "address_inaccurate"
        case .other: return Self.otherCode
        }
    }

    /// The note, Other only ("" when none).
    public var note: String {
        if case .other(let note) = self { return note }
        return ""
    }

    public var title: String {
        Self.choices.first { $0.code == code }?.title ?? code
    }

    /// Other needs a non-blank note within the server's cap; every listed choice is valid on its own.
    public var isValid: Bool {
        if case .other(let note) = self { return !note.isEmpty && Self.length(of: note) <= Self.noteMaxLength }
        return true
    }

    static func trimmed(_ note: String?) -> String {
        (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The three steps of the successful call and what they derive.
public struct CustomerCallVerification: Equatable {

    public enum Step: Int, CaseIterable, Equatable {
        case address = 0
        case equipment = 1
        case unloading = 2

        /// The control's title on the Driver Checklist and the wizard page heading.
        public var title: String {
            switch self {
            case .address: return "Delivery Address"
            case .equipment: return "Equipment Order"
            case .unloading: return "Unloading Situation"
            }
        }
    }

    public var addressVerified: Bool
    public var equipmentVerified: Bool
    /// nil = not chosen yet. An invalid choice (Other without a note) is kept as
    /// recorded so the note can be finished, but it never completes the step.
    public var unloading: UnloadingSituation?

    public init(addressVerified: Bool = false, equipmentVerified: Bool = false, unloading: UnloadingSituation? = nil) {
        self.addressVerified = addressVerified
        self.equipmentVerified = equipmentVerified
        self.unloading = unloading
    }

    /// From the stored / wire strings: an unknown code reads as not chosen.
    public init(addressVerified: Bool, equipmentVerified: Bool, unloadingCode: String, unloadingNote: String) {
        self.init(addressVerified: addressVerified, equipmentVerified: equipmentVerified,
                  unloading: unloadingCode.isEmpty ? nil : UnloadingSituation(code: unloadingCode, note: unloadingNote))
    }

    public static let notStarted = CustomerCallVerification()

    public var unloadingCode: String { unloading?.code ?? "" }
    public var unloadingNote: String { unloading?.note ?? "" }

    public func isComplete(_ step: Step) -> Bool {
        switch step {
        case .address: return addressVerified
        case .equipment: return equipmentVerified
        case .unloading: return unloading?.isValid == true
        }
    }

    /// Every step verified — the ONLY way a delivery call reads "Confirmed".
    public var isComplete: Bool { Step.allCases.allSatisfy(isComplete) }

    public var completedSteps: Int { Step.allCases.filter(isComplete).count }

    /// Anything recorded at all (a chosen-but-invalid Other included).
    public var hasProgress: Bool { addressVerified || equipmentVerified || unloading != nil }

    /// The first step still to do, in wizard order; nil once complete.
    public var nextStep: Step? { Step.allCases.first { !isComplete($0) } }
}
