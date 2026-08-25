//
//  KabbaDateFormats.swift
//  RentnKing — Sync Core (Foundation only)
//
//  ONE canonical wire format for the Sync Engine: ISO 8601 with a UTC offset
//  ("2026-08-25T14:14:03-05:00"). Laravel (Carbon) parses it unambiguously and
//  converts to the app timezone, so an offline capture keeps its real time no
//  matter when connectivity returns. Do not add another format here — the
//  audit counted sixteen in the app already.
//

import Foundation

enum KabbaISO8601 {

    private static let writer: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f
    }()

    private static let readerWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let readerPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// "2026-08-25T14:14:03-05:00" in the device's current zone.
    static func string(from date: Date) -> String {
        writer.string(from: date)
    }

    /// Accepts both fractional and whole-second ISO 8601 strings.
    static func date(from string: String) -> Date? {
        readerWithFraction.date(from: string) ?? readerPlain.date(from: string)
    }

    /// Encoder/decoder pair used for every persisted Sync Engine record.
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(KabbaISO8601.string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            guard let date = KabbaISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not an ISO 8601 date: \(raw)")
            }
            return date
        }
        return d
    }
}
