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
}

private extension Result {
    var refusal: Failure? { if case .failure(let error) = self { return error } else { return nil } }
}
