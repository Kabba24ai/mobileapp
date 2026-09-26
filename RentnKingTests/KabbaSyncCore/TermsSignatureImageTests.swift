import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 5 hardening — the signature image contract on the phone (TermsSignatureImage),
/// pinned by the same vectors Laravel's SignatureImage reads (terms_signature_image.json):
/// the phone never records a signature the server would refuse.
final class TermsSignatureImageTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures

    private func contract() throws -> JSONValue {
        try XCTUnwrap(JSONValue.parse(F.data("terms_signature_image")))
    }

    func testTheLimitsAreTheSharedContract() throws {
        let limits = try XCTUnwrap(try contract()["contract"])
        XCTAssertEqual(limits["data_url_prefix"]?.stringValue, TermsSignatureImage.dataURLPrefix)
        XCTAssertEqual(limits["max_decoded_bytes"]?.intValue, TermsSignatureImage.maxDecodedBytes)
        XCTAssertEqual(limits["max_encoded_length"]?.intValue, TermsSignatureImage.maxEncodedLength)
        XCTAssertEqual(limits["max_width"]?.intValue, TermsSignatureImage.maxWidth)
        XCTAssertEqual(limits["max_height"]?.intValue, TermsSignatureImage.maxHeight)
        XCTAssertEqual(limits["max_pixels"]?.intValue, TermsSignatureImage.maxPixels)
        XCTAssertEqual(limits["max_pad_ratio"]?.intValue, TermsSignatureImage.maxPadRatio)
    }

    func testEveryValidVectorIsAcceptedWithItsDimensions() throws {
        for vector in try XCTUnwrap(try contract()["valid"]?.arrayValue) {
            let name = vector["name"]?.stringValue ?? "?"
            switch TermsSignatureImage.validatedPNG(fromDataURL: vector["data_url"]?.stringValue ?? "") {
            case .success(let png):
                guard case .success(let size) = TermsSignatureImage.inspect(png) else { return XCTFail("\(name): inspect") }
                XCTAssertEqual(size.width, vector["width"]?.intValue, name)
                XCTAssertEqual(size.height, vector["height"]?.intValue, name)
            case .failure(let refusal):
                XCTFail("\(name) refused: \(refusal)")
            }
        }
    }

    func testEveryInvalidVectorIsRefusedForTheSameReasonAsTheServer() throws {
        for vector in try XCTUnwrap(try contract()["invalid"]?.arrayValue) {
            let name = vector["name"]?.stringValue ?? "?"
            let reason = vector["reason"]?.stringValue ?? ""
            let result = TermsSignatureImage.validatedPNG(fromDataURL: vector["value"]?.stringValue ?? "")
            if reason == "undecodable" {
                // Decided by decoding the image, not by structure: the app layer's UIImage check
                // (TermsAndConditionViewController.signaturePNG) refuses it, as GD does on the server.
                if case .failure(let refusal) = result { XCTFail("\(name): structurally valid, refused as \(refusal)") }
                continue
            }
            guard case .failure(let refusal) = result else { XCTFail("accepted: \(name)"); continue }
            XCTAssertEqual(refusal.rawValue, reason, name)
        }
    }

    func testOversizedInputIsRefusedBeforeAnythingIsDecoded() {
        let tooLong = TermsSignatureImage.dataURLPrefix + String(repeating: "A", count: TermsSignatureImage.maxEncodedLength)
        XCTAssertEqual(TermsSignatureImage.validatedPNG(fromDataURL: tooLong).refusal, .tooLarge)
        XCTAssertEqual(TermsSignatureImage.validatedPNG(fromDataURL: String(repeating: "<", count: TermsSignatureImage.maxEncodedLength + 1)).refusal, .tooLarge)
        XCTAssertEqual(TermsSignatureImage.inspect(Data(count: TermsSignatureImage.maxDecodedBytes + 1)).refusal, .tooLarge)
    }

    /// The size limit and the pads' ratio cap together: a noisy signature (canvas read-back noise
    /// does not compress, so its PNG is the raw size) on the largest canvas either page draws — its
    /// CSS size at maxPadRatio — is recorded; the same noise on an uncapped ratio-4 canvas is refused.
    func testANoisySignatureFitsEveryCappedPadAndIsRefusedUncapped() {
        let ratio = TermsSignatureImage.maxPadRatio
        for (page, width, height) in [("phone page", 448, 160), ("web page", 400, 128)] {
            let capped = Self.noisyPNG(width: width * ratio, height: height * ratio)
            XCTAssertGreaterThan(capped.count, width * ratio * height * ratio * 4, "\(page): incompressible")
            let url = TermsSignatureImage.dataURLPrefix + capped.base64EncodedString()
            XCTAssertEqual(try? TermsSignatureImage.validatedPNG(fromDataURL: url).get(), capped, page)

            let uncapped = Self.noisyPNG(width: width * 4, height: height * 4)
            XCTAssertEqual(TermsSignatureImage.inspect(uncapped).refusal, .tooLarge, page)
            XCTAssertEqual(TermsSignatureImage.validatedPNG(fromDataURL: TermsSignatureImage.dataURLPrefix + uncapped.base64EncodedString()).refusal, .tooLarge, page)
        }
    }

    /// A genuine RGBA PNG of deterministic noise: rows unfiltered, IDAT a stored (uncompressed) zlib
    /// stream — what an incompressible canvas encodes to.
    private static func noisyPNG(width: Int, height: Int) -> Data {
        var seed: UInt32 = 7
        var rows = [UInt8]()
        rows.reserveCapacity((width * 4 + 1) * height)
        for _ in 0..<height {
            rows.append(0)
            for _ in 0..<(width * 4) {
                seed = seed &* 1_103_515_245 &+ 12_345
                rows.append(UInt8(truncatingIfNeeded: seed >> 16))
            }
        }
        var zlib: [UInt8] = [0x78, 0x01]
        var start = 0
        repeat {
            let count = min(65_535, rows.count - start)
            let last = start + count == rows.count
            zlib += [last ? 1 : 0, UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)]
            zlib += rows[start..<(start + count)]
            start += count
        } while start < rows.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in rows { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        zlib += bigEndian((b << 16) | a)

        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let body = Array(type.utf8) + data
            return bigEndian(UInt32(data.count)) + body + bigEndian(crc32(body))
        }
        let ihdr = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 6, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", ihdr) + chunk("IDAT", zlib) + chunk("IEND", []))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Result {
    var refusal: Failure? { if case .failure(let error) = self { return error } else { return nil } }
}
