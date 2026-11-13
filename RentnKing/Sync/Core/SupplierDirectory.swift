//
//  SupplierDirectory.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Supplier Directory (2026-11-13): find a supplier, a contact or a phone number
//  from the phone, and add a new supplier — all against Kabba's own supplier
//  table through api/admin/v1/suppliers. There is no second supplier database on
//  the phone: what is kept here is a READ-ONLY copy of what this phone already
//  opened, so a supplier looked up before stays readable without a connection.
//  Adding a supplier always needs Kabba; nothing is queued offline.
//
//  This file holds the contract (Codable, the server's own shape), the request
//  paths, the Add Supplier form's rules, the contact links (call / email / web /
//  directions), the wording and the offline filtering — everything testable
//  without UIKit. The screens live in Modules/…/Supplier Directory Model.
//

import Foundation

// MARK: - Contract

struct SupplierCapabilities: Codable, Equatable {
    let view: Bool
    let create: Bool
    let viewPaymentTerms: Bool

    static let none = SupplierCapabilities(view: false, create: false, viewPaymentTerms: false)
}

struct SupplierSummary: Codable, Equatable {
    let uniqueId: String
    let name: String
    let status: String
    let isActive: Bool
    let isPreferred: Bool
    let phone: String?
    let email: String?
    let city: String?
    let state: String?
    let primaryContactName: String?
    let category: String?
    let tags: [String]
}

struct SupplierPagination: Codable, Equatable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int

    var hasMore: Bool { currentPage < lastPage }
}

struct SupplierPage: Codable, Equatable {
    let suppliers: [SupplierSummary]
    let pagination: SupplierPagination
    let can: SupplierCapabilities
}

struct SupplierOption: Codable, Equatable {
    let id: Int
    let name: String
}

struct SupplierStateOption: Codable, Equatable {
    let id: Int
    let name: String
    let abbreviation: String?
}

struct SupplierOptions: Codable, Equatable {
    let categories: [SupplierOption]
    let tags: [SupplierOption]
    let states: [SupplierStateOption]
    let can: SupplierCapabilities
}

struct SupplierContact: Codable, Equatable {
    let role: String
    let label: String
    let name: String?
    let phone: String?
    let email: String?
}

struct SupplierAddress: Codable, Equatable {
    let street: String?
    let city: String?
    let state: SupplierStateOption?
    let zipCode: String?
    let country: String?
    let oneLine: String?
}

struct SupplierPartItem: Codable, Equatable {
    let uniqueId: String?
    let name: String
    let partNumber: String?
    /// primary | alternate — this supplier's slot on the part.
    let slot: String
}

struct SupplierParts: Codable, Equatable {
    let count: Int
    let items: [SupplierPartItem]
}

struct SupplierDetail: Codable, Equatable {
    let uniqueId: String
    let name: String
    let status: String
    let isActive: Bool
    let isPreferred: Bool
    let phone: String?
    let email: String?
    let website: String?
    let address: SupplierAddress
    let category: SupplierOption?
    let tags: [SupplierOption]
    let contacts: [SupplierContact]
    let parts: SupplierParts
    /// Present only for an account that may see payment terms (and then nil = none on file).
    let paymentTerms: String?
    let updatedAt: String?

    /// The list row this detail implies (offline lists are built from opened suppliers).
    var summary: SupplierSummary {
        SupplierSummary(uniqueId: uniqueId, name: name, status: status, isActive: isActive, isPreferred: isPreferred,
                        phone: phone, email: email, city: address.city, state: address.state?.abbreviation,
                        primaryContactName: contacts.first { $0.role == "primary_contact" }?.name,
                        category: category?.name, tags: tags.map(\.name))
    }
}

struct SupplierDetailEnvelope: Codable, Equatable {
    let supplier: SupplierDetail
    let can: SupplierCapabilities
}

struct SupplierDuplicate: Codable, Equatable {
    let uniqueId: String
    let name: String
    let city: String?
    let state: String?
    let phone: String?
    let status: String
    let reasons: [String]
}

struct SupplierDuplicates: Codable, Equatable {
    let duplicates: [SupplierDuplicate]
}

enum SupplierDirectoryDecoding {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    /// Decodes the canonical envelope's `data` object.
    static func decode<T: Decodable>(_ type: T.Type, envelope data: Data) throws -> T {
        guard let root = JSONValue.parse(data), let payload = root["data"], case .object = payload else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No data object in the response"))
        }
        return try decoder().decode(type, from: payload.serialized())
    }

    /// The likely duplicates a 409 SUPPLIER_POSSIBLE_DUPLICATE carries in `data.duplicates`.
    static func duplicates(fromErrorBody data: Data?) -> [SupplierDuplicate] {
        guard let data, let root = JSONValue.parse(data), let payload = root["data"],
              let decoded = try? decoder().decode(SupplierDuplicates.self, from: payload.serialized()) else { return [] }
        return decoded.duplicates
    }
}

// MARK: - Requests

enum SupplierStatusFilter: String, CaseIterable, Equatable {
    case active, inactive, all

    var title: String {
        switch self {
        case .active: return "Active suppliers"
        case .inactive: return "Inactive suppliers"
        case .all: return "All suppliers"
        }
    }
}

/// What the search box looks in: the supplier record (company, contacts, phones,
/// emails, category, tags) or the parts suppliers are on file for.
enum SupplierSearchScope: Int, Equatable {
    case supplier = 0
    case part = 1
}

enum SupplierDirectoryPaths {
    static let perPage = 25
    static let options = "suppliers/options"
    static let duplicateCheck = "suppliers/duplicate-check"
    static let create = "suppliers"

    static func list(search: String, scope: SupplierSearchScope, status: SupplierStatusFilter, page: Int, perPage: Int = perPage) -> String {
        var items = [URLQueryItem(name: "status", value: status.rawValue),
                     URLQueryItem(name: "page", value: String(max(1, page))),
                     URLQueryItem(name: "per_page", value: String(perPage))]
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            items.insert(URLQueryItem(name: scope == .part ? "part" : "search", value: String(term.prefix(100))), at: 0)
        }
        var components = URLComponents()
        components.path = "suppliers"
        components.queryItems = items
        // URLComponents leaves "+" alone, which a PHP server reads as a space.
        return (components.string ?? "suppliers").replacingOccurrences(of: "+", with: "%2B")
    }

    static func detail(_ uniqueId: String) -> String {
        "suppliers/" + (uniqueId.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? uniqueId)
    }
}

// MARK: - Add Supplier form

struct SupplierContactDraft: Equatable {
    var name = ""
    var phone = ""
    var email = ""

    var isEmpty: Bool { [name, phone, email].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

struct SupplierDraft: Equatable {
    /// The four contact roles, in the order the form and the detail show them.
    static let contactRoles: [(key: String, title: String)] = [
        ("primary_contact", "Primary Contact"),
        ("inside_sales", "Inside Sales"),
        ("technical_support", "Technical Support"),
        ("billing_contact", "Billing Contact"),
    ]

    var name = ""
    var phone = ""
    var email = ""
    var website = ""
    var address = ""
    var city = ""
    var stateId: Int?
    var zipCode = ""
    var categoryId: Int?
    var tagIds: [Int] = []
    var contacts: [String: SupplierContactDraft] = [:]

    /// Field key (Laravel's) → the problem, checked before anything is sent.
    func validationErrors() -> [String: String] {
        var errors: [String: String] = [:]
        if Self.clean(name).isEmpty { errors["name"] = "Enter the supplier company name." }
        if Self.clean(name).count > 255 { errors["name"] = "The company name is too long." }
        if !Self.clean(email).isEmpty, !Self.looksLikeEmail(email) { errors["email"] = "Enter a valid email address." }
        if Self.clean(zipCode).count > 10 { errors["zip_code"] = "The ZIP code is too long." }
        for (key, _) in Self.contactRoles {
            let email = contacts[key]?.email ?? ""
            if !Self.clean(email).isEmpty, !Self.looksLikeEmail(email) { errors[key + "_email"] = "Enter a valid email address." }
        }
        return errors
    }

    /// The create request: only what was entered, trimmed.
    func body(acknowledgeDuplicates: Bool) -> JSONValue {
        var body = identityFields()
        put(&body, "address", address)
        put(&body, "city", city)
        put(&body, "zip_code", zipCode)
        if let stateId { body["state_id"] = .number(Double(stateId)) }
        if let categoryId { body["supplier_category_id"] = .number(Double(categoryId)) }
        if !tagIds.isEmpty { body["tags"] = .array(tagIds.map { .number(Double($0)) }) }
        for (key, _) in Self.contactRoles {
            put(&body, key + "_name", contacts[key]?.name ?? "")
        }
        if acknowledgeDuplicates { body["acknowledge_duplicates"] = .bool(true) }
        return .object(body)
    }

    /// What the duplicate check needs: the company's name, phones, emails and website.
    var duplicateCheckBody: JSONValue { .object(identityFields()) }

    /// Worth asking about duplicates yet (a name, or a phone / email / website)?
    var hasIdentifyingInformation: Bool {
        guard case .object(let fields) = duplicateCheckBody else { return false }
        return !fields.isEmpty
    }

    private func identityFields() -> [String: JSONValue] {
        var body: [String: JSONValue] = [:]
        put(&body, "name", name)
        put(&body, "phone", phone)
        put(&body, "email", email)
        put(&body, "website", website)
        for (key, _) in Self.contactRoles {
            put(&body, key + "_phone", contacts[key]?.phone ?? "")
            put(&body, key + "_email", contacts[key]?.email ?? "")
        }
        return body
    }

    private func put(_ body: inout [String: JSONValue], _ key: String, _ value: String) {
        let cleaned = Self.clean(value)
        if !cleaned.isEmpty { body[key] = .string(cleaned) }
    }

    static func clean(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        let v = clean(value)
        guard !v.contains(" "), let at = v.firstIndex(of: "@"), at != v.startIndex else { return false }
        let domain = v[v.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains("@")
    }
}

// MARK: - Contact links (never invent a value: no input, no link)

enum SupplierContactLinks {

    /// tel: for a number with at least 7 digits; an extension ("x 12", "ext. 12") is dropped
    /// for dialling; a leading + is kept.
    static func phoneURL(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let range = text.range(of: #"(?i)\s*(ext\.?|x|#)\s*\d+\s*$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let digits = text.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return URL(string: "tel:" + (text.hasPrefix("+") ? "+" : "") + digits)
    }

    static func emailURL(_ raw: String?) -> URL? {
        guard let email = raw?.trimmingCharacters(in: .whitespacesAndNewlines), SupplierDraft.looksLikeEmail(email),
              let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed.union(CharacterSet(charactersIn: "@"))) else { return nil }
        return URL(string: "mailto:" + encoded)
    }

    /// http(s) only; "acme.com" opens as https://acme.com.
    static func websiteURL(_ raw: String?) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !text.contains(" ") else { return nil }
        let candidate = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") ? text : "https://" + text
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Apple Maps directions to the supplier's address (nil without a street or a city).
    static func directionsURL(address: SupplierAddress) -> URL? {
        guard address.street != nil || address.city != nil else { return nil }
        let destination = [address.street, address.city, [address.state?.abbreviation, address.zipCode].compactMap { $0 }.joined(separator: " "), address.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        return components?.url
    }
}

// MARK: - Wording and offline filtering

enum SupplierDirectoryPresentation {

    static let offlineList = "No connection — showing suppliers saved on this phone. Pull to refresh when you're back online."
    static let offlineAdd = "Adding a supplier needs a connection to Kabba. Nothing was saved — try again when you're back online."
    static let forbidden = "Your account does not have access to the Supplier Directory. Ask the office if you need it."

    /// "Dana Brooks · Knoxville, TN · (865) 555-0142"
    static func subtitle(_ s: SupplierSummary) -> String {
        let place = [s.city, s.state].compactMap { $0 }.joined(separator: ", ")
        return [s.primaryContactName, place.isEmpty ? nil : place, s.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Active · Preferred supplier" / "Inactive"
    static func statusLine(status: String, isPreferred: Bool) -> String {
        isPreferred ? "\(status) · Preferred supplier" : status
    }

    static func emptyMessage(search: String, scope: SupplierSearchScope, status: SupplierStatusFilter) -> String {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            return scope == .part ? "No supplier is on file for a part matching “\(term)”." : "No supplier matches “\(term)”."
        }
        switch status {
        case .active: return "No active suppliers yet.\nTap Add Supplier to add one."
        case .inactive: return "No inactive suppliers."
        case .all: return "No suppliers yet.\nTap Add Supplier to add one."
        }
    }

    static func reasonText(_ reasons: [String]) -> String {
        let words: [String: String] = ["name": "Same name", "similar_name": "Similar name", "phone": "Same phone number",
                                       "email": "Same email", "website": "Same website"]
        return reasons.compactMap { words[$0] }.joined(separator: " · ")
    }

    static func duplicateLine(_ d: SupplierDuplicate) -> String {
        let place = [d.city, d.state].compactMap { $0 }.joined(separator: ", ")
        return [place.isEmpty ? nil : place, d.phone, d.status == "Active" ? nil : d.status, reasonText(d.reasons)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Saved on this phone 9:42 AM — may be out of date."
    static func cachedNotice(savedAt: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = calendar.isDate(savedAt, inSameDayAs: now) ? "h:mm a" : "MMM d, h:mm a"
        return "No connection — showing the copy saved on this phone \(f.string(from: savedAt)). It may be out of date."
    }

    static func partLine(_ p: SupplierPartItem) -> String {
        [p.partNumber.map { "#\($0)" }, p.slot == "alternate" ? "Alternate source" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// Offline search over suppliers saved on this phone — the same fields the server searches.
    static func filter(_ suppliers: [SupplierSummary], search: String, status: SupplierStatusFilter) -> [SupplierSummary] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = term.filter(\.isNumber)
        return suppliers.filter { s in
            switch status {
            case .active: guard s.isActive else { return false }
            case .inactive: guard !s.isActive else { return false }
            case .all: break
            }
            guard !term.isEmpty else { return true }
            let text = ([s.name, s.primaryContactName, s.email, s.city, s.category, s.phone] + s.tags.map(Optional.some))
                .compactMap { $0?.lowercased() }
            if text.contains(where: { $0.contains(term) }) { return true }
            return digits.count >= 4 && (s.phone ?? "").filter(\.isNumber).contains(digits)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Read-only copy on this phone

/// One supplier as last read from Kabba, with when.
struct SupplierCachedDetail: Codable, Equatable {
    let envelope: SupplierDetailEnvelope
    let savedAt: Date
}

/// The phone's read-only copy: the suppliers it opened (newest first, bounded) and the last
/// directory page it listed. Stored through `read`/`write` (company-scoped by the app), so it
/// never mixes companies; never written from a form — only from Kabba's answers.
struct SupplierDirectoryOfflineCopy {
    static let detailPrefix = "kSupplierDirectoryDetail_"
    static let indexKey = "kSupplierDirectoryIndex"
    static let listKey = "kSupplierDirectoryList"
    static let maxDetails = 200

    let read: (String) -> Data?
    let write: (String, Data?) -> Void

    func saveDetail(_ envelope: SupplierDetailEnvelope, at date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(SupplierCachedDetail(envelope: envelope, savedAt: date)) else { return }
        let uid = envelope.supplier.uniqueId
        write(Self.detailPrefix + uid, data)
        var index = recentIds().filter { $0 != uid }
        index.insert(uid, at: 0)
        for evicted in index.dropFirst(Self.maxDetails) { write(Self.detailPrefix + evicted, nil) }
        write(Self.indexKey, try? JSONEncoder().encode(Array(index.prefix(Self.maxDetails))))
    }

    func detail(_ uniqueId: String) -> SupplierCachedDetail? {
        read(Self.detailPrefix + uniqueId).flatMap { try? JSONDecoder().decode(SupplierCachedDetail.self, from: $0) }
    }

    func saveList(_ suppliers: [SupplierSummary]) {
        write(Self.listKey, try? JSONEncoder().encode(Array(suppliers.prefix(Self.maxDetails))))
    }

    /// Every supplier this phone can show offline: opened ones (freshest copy) plus the last list.
    func allSummaries() -> [SupplierSummary] {
        var byId: [String: SupplierSummary] = [:]
        let listed = read(Self.listKey).flatMap { try? JSONDecoder().decode([SupplierSummary].self, from: $0) } ?? []
        for s in listed { byId[s.uniqueId] = s }
        for uid in recentIds() { if let d = detail(uid) { byId[uid] = d.envelope.supplier.summary } }
        return Array(byId.values)
    }

    private func recentIds() -> [String] {
        read(Self.indexKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }
}
