//
//  SyncMultipartBuilder.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Builds a multipart/form-data body into a FILE (so URLSession can stream it —
//  required for background sessions and for the large media of Phase 4) from a
//  JSON object of fields plus SyncAsset file parts.
//
//  Nested fields use Laravel bracket notation — `answers[0][question_id]` —
//  never a JSON string inside a form field (the legacy `checklist[]` hack the
//  server had three repair branches for).
//

import Foundation

enum SyncMultipartError: Error, Equatable {
    case assetMissing(String)
    case cannotCreateBodyFile
}

struct SyncMultipartBody {
    let fileURL: URL
    let boundary: String
    let contentType: String
    let byteCount: Int64
}

enum SyncMultipartBuilder {

    /// Flattens a JSON object into ordered (name, value) form fields.
    ///   {"a": {"b": 1}, "list": [{"x": "y"}], "s": "v"}  →  a[b]=1, list[0][x]=y, s=v
    /// Booleans become "1"/"0" (what Laravel's boolean rule accepts); null is omitted.
    static func formFields(from json: JSONValue) -> [(name: String, value: String)] {
        var out: [(String, String)] = []
        guard case .object(let root) = json else { return out }
        for key in root.keys.sorted() {
            flatten(root[key]!, name: key, into: &out)
        }
        return out.map { (name: $0.0, value: $0.1) }
    }

    private static func flatten(_ value: JSONValue, name: String, into out: inout [(String, String)]) {
        switch value {
        case .null:
            return
        case .string(let s):
            out.append((name, s))
        case .number(let n):
            out.append((name, n == n.rounded() && abs(n) < 9_007_199_254_740_992 ? String(Int(n)) : String(n)))
        case .bool(let b):
            out.append((name, b ? "1" : "0"))
        case .array(let items):
            for (index, item) in items.enumerated() {
                flatten(item, name: "\(name)[\(index)]", into: &out)
            }
        case .object(let dict):
            for key in dict.keys.sorted() {
                flatten(dict[key]!, name: "\(name)[\(key)]", into: &out)
            }
        }
    }

    /// Writes the multipart body to `directory` (temp file). Caller deletes it after the upload completes.
    static func build(fields: JSONValue?,
                      assets: [SyncAsset],
                      assetsDirectory: URL,
                      directory: URL = FileManager.default.temporaryDirectory,
                      fileManager: FileManager = .default) throws -> SyncMultipartBody {
        let boundary = "KabbaSync-" + UUID().uuidString
        let bodyURL = directory.appendingPathComponent("kabba-multipart-\(UUID().uuidString).tmp")

        guard fileManager.createFile(atPath: bodyURL.path, contents: nil, attributes: nil) else {
            throw SyncMultipartError.cannotCreateBodyFile
        }
        let handle = try FileHandle(forWritingTo: bodyURL)
        defer { try? handle.close() }

        func write(_ string: String) throws { try handle.write(contentsOf: Data(string.utf8)) }

        if let fields = fields {
            for field in formFields(from: fields) {
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
                try write(field.value)
                try write("\r\n")
            }
        }

        for asset in assets {
            let source = assetsDirectory.appendingPathComponent(asset.relativePath)
            guard fileManager.fileExists(atPath: source.path) else {
                throw SyncMultipartError.assetMissing(asset.relativePath)
            }
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(asset.fieldName)\"; filename=\"\(source.lastPathComponent)\"\r\n")
            try write("Content-Type: \(asset.mimeType)\r\n\r\n")

            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            while true {
                let chunk = try input.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                try handle.write(contentsOf: chunk)
            }
            try write("\r\n")
        }

        try write("--\(boundary)--\r\n")

        let size = (try? fileManager.attributesOfItem(atPath: bodyURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return SyncMultipartBody(fileURL: bodyURL, boundary: boundary,
                                 contentType: "multipart/form-data; boundary=\(boundary)", byteCount: size)
    }
}
