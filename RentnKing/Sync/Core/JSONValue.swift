//
//  JSONValue.swift
//  RentnKing — Sync Core (Foundation only)
//
//  A Codable, Equatable JSON tree. Operation payloads are stored as JSONValue
//  so an operation can be persisted, replayed and inspected without knowing
//  its concrete type, and so a payload never depends on NSDictionary/ObjectMapper.
//

import Foundation

indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b):   try container.encode(b)
        case .null:          try container.encodeNil()
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    // MARK: Bridging to/from Foundation (JSONSerialization) values

    /// Builds a JSONValue from a JSONSerialization-compatible object. Returns nil for
    /// anything that is not representable (e.g. UIImage, Data, Date).
    init?(any: Any) {
        switch any {
        case is NSNull:
            self = .null
        case let v as JSONValue:
            self = v
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // NSNumber bridges Bool as well; distinguish via objCType.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let b as Bool:
            self = .bool(b)
        case let i as Int:
            self = .number(Double(i))
        case let d as Double:
            self = .number(d)
        case let a as [Any]:
            var out: [JSONValue] = []
            out.reserveCapacity(a.count)
            for element in a {
                guard let v = JSONValue(any: element) else { return nil }
                out.append(v)
            }
            self = .array(out)
        case let o as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, element) in o {
                guard let v = JSONValue(any: element) else { return nil }
                out[k] = v
            }
            self = .object(out)
        default:
            return nil
        }
    }

    /// Back to Foundation types (NSNull for null) — suitable for JSONSerialization.
    var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n):
            // Emit integral numbers as Int so "attempts": 2 does not become 2.0 on the wire.
            if n.isFinite, n == n.rounded(), abs(n) < 9_007_199_254_740_992 { return Int(n) }
            return n
        case .bool(let b):   return b
        case .null:          return NSNull()
        case .array(let a):  return a.map { $0.anyValue }
        case .object(let o): return o.mapValues { $0.anyValue }
        }
    }

    // MARK: Convenience accessors

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "true" : "false"
        default:             return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b):   return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased() {
            case "1", "true", "yes":  return true
            case "0", "false", "no", "": return false
            default: return nil
            }
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        case .bool(let b):   return b ? 1 : 0
        default:             return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Serialized JSON bytes (compact). Objects/arrays only — scalars are wrapped by the caller.
    func serialized() throws -> Data {
        let any = anyValue
        guard JSONSerialization.isValidJSONObject(any) else {
            throw NSError(domain: "KabbaSync.JSONValue", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Top-level JSON must be an object or array"])
        }
        return try JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])
    }

    /// Parses JSON bytes into a tree; nil when the bytes are not JSON.
    static func parse(_ data: Data?) -> JSONValue? {
        guard let data = data, !data.isEmpty else { return nil }
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return JSONValue(any: any)
    }
}
