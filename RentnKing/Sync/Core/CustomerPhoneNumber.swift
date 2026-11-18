//
//  CustomerPhoneNumber.swift
//  RentnKing — Sync Engine core (mobile issue #10, 2026-11-15)
//
//  A customer's telephone number as the phone dials and texts it. Kabba sends
//  the number for reading, not dialling: a ten-digit US number formatted
//  "(865) 555-0142" (CustomHelper::formatPhone), anything else exactly as it
//  was typed ("+44 20 7946 0958", "865.555.0142 ext 12", "555-0199").
//
//  The Call / Send Message sheet used to strip every "+1" and put "+1" back in
//  front of whatever was left, so an international number became "+1+44 …"
//  and a formatted one went into the tel: link with its spaces and brackets.
//  This keeps the country code the number already has, assumes +1 only for a
//  ten-digit number with none (what the app has always assumed), and gives up
//  — nil — when there is no number to dial, so the screen can say so.
//

import Foundation

struct CustomerPhoneNumber: Equatable {

    /// The number as Kabba sent it, trimmed: what a screen shows beside the phone icon.
    let text: String
    /// The sheet's "Call …" wording: the same, without a leading +1 (as the Driver Checklist always showed it).
    let spoken: String
    /// What is dialled and texted: an optional "+" and digits only, e.g. "+18655550142".
    let dialable: String

    /// Fewer digits than a local number (or more than E.164 allows) is not a number to dial.
    static let digitRange = 7...15

    init?(_ raw: String?) {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // An extension ("ext 12", "x12", "#12") is read out, never dialled into the main number;
        // a value that starts with a letter ("N/A", "none") has no number at all.
        let number = String(text.prefix { !$0.isLetter && $0 != "#" && $0 != ";" && $0 != "," })
            .trimmingCharacters(in: .whitespaces)
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard Self.digitRange.contains(digits.count) else { return nil }

        let dialable: String
        if number.hasPrefix("+") {
            dialable = "+" + digits                           // its own country code, untouched
        } else if digits.count == 10 {
            dialable = "+1" + digits                          // a US / Canada number written without one
        } else if digits.count == 11, digits.hasPrefix("1") {
            dialable = "+" + digits
        } else {
            dialable = digits                                 // a local or unrecognised number: no country code invented
        }

        self.text = text
        self.dialable = dialable
        self.spoken = dialable.hasPrefix("+1") && text.hasPrefix("+1")
            ? String(text.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: " -.").union(.whitespaces))
            : text
    }

    /// The Phone app's link (iOS asks before it dials).
    var callURL: URL? { URL(string: "tel:" + dialable) }
}
