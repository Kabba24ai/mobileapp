import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class JSONValueTests: XCTestCase {

    func testRoundTripsFoundationObjectsAndDistinguishesBoolFromNumber() throws {
        let any: [String: Any] = ["s": "x", "n": 2, "d": 2.5, "b": true, "null": NSNull(), "a": [1, "two"], "o": ["k": false]]
        let value = try XCTUnwrap(JSONValue(any: any))

        XCTAssertEqual(value["s"], .string("x"))
        XCTAssertEqual(value["n"], .number(2))
        XCTAssertEqual(value["d"], .number(2.5))
        XCTAssertEqual(value["b"], .bool(true))
        XCTAssertEqual(value["null"], .null)
        XCTAssertEqual(value["a"]?.arrayValue?.count, 2)
        XCTAssertEqual(value["o"]?["k"], .bool(false))

        let back = value.anyValue as? [String: Any]
        XCTAssertEqual(back?["n"] as? Int, 2, "integral numbers go back on the wire as Int, not 2.0")
        XCTAssertEqual(back?["b"] as? Bool, true)
    }

    func testCodableRoundTrip() throws {
        let value: JSONValue = .object(["a": .array([.number(1), .string("x"), .null]), "b": .bool(true)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testRejectsNonJSONObjects() {
        XCTAssertNil(JSONValue(any: ["date": Date()]))
        XCTAssertNil(JSONValue(any: Data([1, 2, 3])))
    }

    func testLenientScalarAccessors() {
        XCTAssertEqual(JSONValue.string("1").boolValue, true)
        XCTAssertEqual(JSONValue.string("0").boolValue, false)
        XCTAssertEqual(JSONValue.number(1).boolValue, true)
        XCTAssertEqual(JSONValue.string("42").intValue, 42)
        XCTAssertEqual(JSONValue.number(7).stringValue, "7")
        XCTAssertNil(JSONValue.string("maybe").boolValue)
    }

    func testParseAndSerialize() throws {
        let data = Data(#"{"success":"1","data":{"x":1}}"#.utf8)
        let value = try XCTUnwrap(JSONValue.parse(data))
        XCTAssertEqual(value["success"]?.boolValue, true)
        let out = try value.serialized()
        XCTAssertEqual(JSONValue.parse(out), value)
        XCTAssertNil(JSONValue.parse(Data("not json".utf8)))
    }
}
