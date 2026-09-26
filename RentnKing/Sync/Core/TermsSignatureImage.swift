//
//  TermsSignatureImage.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline Phase 5 hardening. The ONE signature image form Laravel
//  accepts (App\Services\Terms\SignatureImage), checked on the phone before a
//  signature is recorded, so the phone never keeps a signature the server
//  would refuse:
//
//    data:image/png;base64,<strict, canonical base64 of a well-formed PNG>
//
//  In order, cheap and bounded before anything is decoded: text length, the
//  exact prefix, strict canonical base64, decoded size, PNG structure (the
//  signature, IHDR first with valid fields, every chunk's length and CRC, an
//  IDAT, IEND last with nothing after it), then the dimensions from IHDR.
//  Whether the image data itself decodes is the app layer's check (UIImage) —
//  the server decodes it too (GD) and stores its own re-encoding.
//
//  Limits (measured signature_pad output; shared with Laravel through
//  terms_signature_image.json): 1 MiB decoded, 1,398,126 characters, 4096 ×
//  2048 px, 4 MP.
//

import Foundation

enum TermsSignatureImage {

    enum Refusal: String, Error, Equatable {
        case notPngDataUrl = "not_png_data_url"
        case malformedBase64 = "malformed_base64"
        case tooLarge = "too_large"
        case notPng = "not_png"
        case dimensionsExceeded = "dimensions_exceeded"
    }

    static let dataURLPrefix = "data:image/png;base64,"
    static let maxDecodedBytes = 1_048_576
    /// The prefix (22) plus the base64 length of maxDecodedBytes.
    static let maxEncodedLength = 1_398_126
    static let maxWidth = 4096
    static let maxHeight = 2048
    static let maxPixels = 4_194_304

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let bitDepths: [UInt8: Set<UInt8>] = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]

    /// The signing page's data URL → the PNG bytes to record, or why it can't be recorded.
    static func validatedPNG(fromDataURL dataURL: String) -> Result<Data, Refusal> {
        guard dataURL.utf8.count <= maxEncodedLength else { return .failure(.tooLarge) }
        guard dataURL.hasPrefix(dataURLPrefix) else { return .failure(.notPngDataUrl) }
        let payload = String(dataURL.dropFirst(dataURLPrefix.count))
        guard isStrictBase64(payload), let data = Data(base64Encoded: payload), data.base64EncodedString() == payload else {
            return .failure(.malformedBase64)
        }
        return inspect(data).map { _ in data }
    }

    /// The PNG's structure and dimensions, without decoding any image data.
    static func inspect(_ png: Data) -> Result<(width: Int, height: Int), Refusal> {
        guard png.count <= maxDecodedBytes else { return .failure(.tooLarge) }
        let bytes = [UInt8](png)
        guard bytes.count >= 8, Array(bytes[0..<8]) == pngSignature else { return .failure(.notPng) }

        var offset = 8
        var index = 0
        var size: (width: Int, height: Int)?
        var sawData = false
        while true {
            guard offset + 12 <= bytes.count else { return .failure(.notPng) } // truncated, or no IEND
            let length = Int(uint32(bytes, offset))
            let type = Array(bytes[(offset + 4)..<(offset + 8)])
            guard length <= 0x7FFF_FFFF, offset + 12 + length <= bytes.count,
                  type.allSatisfy({ (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }) else { return .failure(.notPng) }
            let body = Array(bytes[(offset + 4)..<(offset + 8 + length)])
            guard crc32(body) == uint32(bytes, offset + 8 + length) else { return .failure(.notPng) }
            let name = String(decoding: type, as: UTF8.self)

            if index == 0 {
                guard name == "IHDR", length == 13 else { return .failure(.notPng) }
                let width = Int(uint32(bytes, offset + 8)), height = Int(uint32(bytes, offset + 12))
                let depth = bytes[offset + 16], color = bytes[offset + 17]
                guard width >= 1, height >= 1, width <= 0x7FFF_FFFF, height <= 0x7FFF_FFFF,
                      bitDepths[color]?.contains(depth) == true,
                      bytes[offset + 18] == 0, bytes[offset + 19] == 0, bytes[offset + 20] <= 1 else { return .failure(.notPng) }
                size = (width, height)
            } else if name == "IHDR" {
                return .failure(.notPng)
            } else if name == "IDAT" {
                sawData = true
            } else if name == "IEND" {
                guard length == 0, sawData, offset + 12 == bytes.count, let size = size else { return .failure(.notPng) }
                guard size.width <= maxWidth, size.height <= maxHeight, size.width * size.height <= maxPixels else {
                    return .failure(.dimensionsExceeded)
                }
                return .success(size)
            }
            offset += 12 + length
            index += 1
        }
    }

    // MARK: - Helpers

    /// The standard alphabet, a length that is a multiple of 4, padding only at the end.
    private static func isStrictBase64(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty, scalars.count % 4 == 0 else { return false }
        let padding = scalars.reversed().prefix { $0 == "=" }.count
        guard padding <= 2 else { return false }
        return scalars.dropLast(padding).allSatisfy { ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "+" || $0 == "/" }
    }

    private static func uint32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
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
