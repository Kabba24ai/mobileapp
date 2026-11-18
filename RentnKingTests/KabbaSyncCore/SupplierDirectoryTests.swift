import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Supplier Directory (2026-11-13). The fixtures are Laravel's own responses,
/// captured from the API's feature-test app (SupplierDirectoryMobileApiTest world),
/// so the phone is tested against the server's real shape.
final class SupplierDirectoryTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Fixture \(name).json missing") }
        return try Data(contentsOf: url)
    }

    // MARK: Contract

    func testTheDirectoryPageDecodes() throws {
        let page = try SupplierDirectoryDecoding.decode(SupplierPage.self, envelope: try fixture("supplier_directory_list"))
        XCTAssertEqual(page.suppliers.map(\.name), ["Midway Parts", "Smoky Mountain Hydraulics"], "alphabetical")
        let smoky = try XCTUnwrap(page.suppliers.last)
        XCTAssertTrue(smoky.isPreferred)
        XCTAssertEqual(smoky.primaryContactName, "Dana Brooks")
        XCTAssertEqual(smoky.state, "TN")
        XCTAssertEqual(smoky.category, "Hydraulics")
        XCTAssertEqual(smoky.tags, ["Same-day delivery"])
        XCTAssertFalse(page.suppliers.first!.isActive)
        XCTAssertEqual(page.pagination, SupplierPagination(currentPage: 1, lastPage: 1, perPage: 25, total: 2))
        XCTAssertFalse(page.pagination.hasMore)
        XCTAssertEqual(page.can, SupplierCapabilities(view: true, create: true, viewPaymentTerms: false))
    }

    func testTheDetailDecodesWithoutPaymentTermsForAnEmployee() throws {
        let envelope = try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_detail"))
        let s = envelope.supplier
        XCTAssertEqual(s.name, "Smoky Mountain Hydraulics")
        XCTAssertEqual(s.address.oneLine, "12 Main St, Knoxville, TN 37902")
        XCTAssertEqual(s.address.state?.abbreviation, "TN")
        XCTAssertEqual(s.contacts.map(\.role), ["primary_contact", "technical_support"], "only contacts on file")
        XCTAssertNil(s.contacts[1].name)
        XCTAssertEqual(s.parts.items.map(\.slot), ["primary", "alternate"])
        XCTAssertNil(s.paymentTerms)
        XCTAssertFalse(envelope.can.viewPaymentTerms)
        XCTAssertFalse(String(data: try fixture("supplier_directory_detail"), encoding: .utf8)!.contains("12-3456789"), "the tax id never reaches the phone")
        XCTAssertEqual(s.summary.primaryContactName, "Dana Brooks")
    }

    func testTheAccountsPayableDetailCarriesPaymentTerms() throws {
        let envelope = try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_detail_ap"))
        XCTAssertEqual(envelope.supplier.paymentTerms, "Net 30")
        XCTAssertTrue(envelope.can.viewPaymentTerms)
    }

    func testOptionsDuplicatesCreatedAndTheDuplicateRefusalDecode() throws {
        let options = try SupplierDirectoryDecoding.decode(SupplierOptions.self, envelope: try fixture("supplier_directory_options"))
        XCTAssertEqual(options.categories.map(\.name), ["Hydraulics"])
        XCTAssertEqual(options.tags.map(\.name), ["Same-day delivery"])
        XCTAssertEqual(options.states.first?.abbreviation, "TN")

        let duplicates = try SupplierDirectoryDecoding.decode(SupplierDuplicates.self, envelope: try fixture("supplier_directory_duplicates"))
        XCTAssertEqual(duplicates.duplicates.first?.reasons, ["name", "phone"])

        let refused = SupplierDirectoryDecoding.duplicates(fromErrorBody: try fixture("supplier_directory_duplicate_409"))
        XCTAssertEqual(refused.map(\.name), ["Smoky Mountain Hydraulics"])

        let created = try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_created"))
        XCTAssertEqual(created.supplier.status, "Active")
        XCTAssertEqual(created.supplier.contacts.first?.name, "Pat Quinn")
        XCTAssertTrue(SupplierDirectoryDecoding.duplicates(fromErrorBody: try fixture("supplier_directory_forbidden")).isEmpty)
    }

    // MARK: Requests

    func testPathsAreBoundedAndEncoded() {
        XCTAssertEqual(SupplierDirectoryPaths.list(search: "", scope: .supplier, status: .active, page: 1),
                       "suppliers?status=active&page=1&per_page=25")
        XCTAssertEqual(SupplierDirectoryPaths.list(search: " A&B Supply + Co ", scope: .supplier, status: .all, page: 3),
                       "suppliers?search=A%26B%20Supply%20%2B%20Co&status=all&page=3&per_page=25")
        XCTAssertEqual(SupplierDirectoryPaths.list(search: "HF-2201", scope: .part, status: .inactive, page: 0),
                       "suppliers?part=HF-2201&status=inactive&page=1&per_page=25")
        XCTAssertEqual(SupplierDirectoryPaths.detail("SUP-AB12-CD34"), "suppliers/SUP-AB12-CD34")
    }

    // MARK: Add Supplier form

    func testOnlyTheCompanyNameIsRequiredAndEmailsAreChecked() {
        var draft = SupplierDraft()
        XCTAssertEqual(draft.validationErrors()["name"], "Enter the supplier company name.")
        draft.name = "  Cumberland Tool  "
        XCTAssertTrue(draft.validationErrors().isEmpty)
        draft.email = "orders@"
        draft.contacts["billing_contact"] = SupplierContactDraft(email: "ap at cumberland")
        draft.zipCode = "12345678901"
        XCTAssertEqual(Set(draft.validationErrors().keys), ["email", "billing_contact_email", "zip_code"])
    }

    func testTheBodyCarriesOnlyWhatWasEnteredAndNeverAFinancialField() throws {
        var draft = SupplierDraft()
        draft.name = "  Cumberland   Tool Rental "
        draft.phone = "615-555-0123"
        draft.stateId = 4
        draft.categoryId = 2
        draft.tagIds = [7, 9]
        draft.contacts["inside_sales"] = SupplierContactDraft(name: "Pat Quinn", phone: "", email: "pat@cumberland.example")
        draft.contacts["billing_contact"] = SupplierContactDraft()

        guard case .object(let body) = draft.body(acknowledgeDuplicates: false) else { return XCTFail() }
        XCTAssertEqual(body["name"], .string("Cumberland Tool Rental"))
        XCTAssertEqual(body["state_id"], .number(4))
        XCTAssertEqual(body["tags"], .array([.number(7), .number(9)]))
        XCTAssertEqual(body["inside_sales_name"], .string("Pat Quinn"))
        XCTAssertEqual(body["inside_sales_email"], .string("pat@cumberland.example"))
        XCTAssertNil(body["inside_sales_phone"], "blank fields are not sent")
        XCTAssertNil(body["billing_contact_name"])
        XCTAssertNil(body["acknowledge_duplicates"])
        for officeOnly in ["payment_terms", "tax_id", "status", "is_preferred_supplier"] { XCTAssertNil(body[officeOnly]) }

        guard case .object(let confirmed) = draft.body(acknowledgeDuplicates: true) else { return XCTFail() }
        XCTAssertEqual(confirmed["acknowledge_duplicates"], .bool(true))

        guard case .object(let check) = draft.duplicateCheckBody else { return XCTFail() }
        XCTAssertEqual(Set(check.keys), ["name", "phone", "inside_sales_email"], "the identifying fields only")
        XCTAssertFalse(SupplierDraft().hasIdentifyingInformation)
    }

    // MARK: Contact links

    func testLinksAreBuiltOnlyFromRealValues() {
        XCTAssertEqual(SupplierContactLinks.phoneURL("(865) 555-0142")?.absoluteString, "tel:8655550142")
        XCTAssertEqual(SupplierContactLinks.phoneURL("+1 865.555.0142")?.absoluteString, "tel:+18655550142")
        XCTAssertEqual(SupplierContactLinks.phoneURL("865-555-0199 x12")?.absoluteString, "tel:8655550199", "the extension is not dialled")
        XCTAssertNil(SupplierContactLinks.phoneURL("555"))
        XCTAssertNil(SupplierContactLinks.phoneURL(nil))
        XCTAssertNil(SupplierContactLinks.phoneURL("  "))

        XCTAssertEqual(SupplierContactLinks.emailURL(" sales@smh.example ")?.absoluteString, "mailto:sales@smh.example")
        XCTAssertNil(SupplierContactLinks.emailURL("not an email"))

        XCTAssertEqual(SupplierContactLinks.websiteURL("smh.example")?.absoluteString, "https://smh.example")
        XCTAssertEqual(SupplierContactLinks.websiteURL("http://smh.example/parts")?.absoluteString, "http://smh.example/parts")
        XCTAssertNil(SupplierContactLinks.websiteURL("javascript:alert(1)"))
        XCTAssertNil(SupplierContactLinks.websiteURL("localhost"))

        let address = SupplierAddress(street: "12 Main St", city: "Knoxville", state: SupplierStateOption(id: 1, name: "Tennessee", abbreviation: "TN"),
                                      zipCode: "37902", country: nil, oneLine: "12 Main St, Knoxville, TN 37902")
        XCTAssertEqual(SupplierContactLinks.directionsURL(address: address)?.absoluteString,
                       "https://maps.apple.com/?daddr=12%20Main%20St,%20Knoxville,%20TN%2037902")
        XCTAssertNil(SupplierContactLinks.directionsURL(address: SupplierAddress(street: nil, city: nil, state: nil, zipCode: "37902", country: nil, oneLine: nil)))
    }

    // MARK: Wording and offline

    func testWording() throws {
        let page = try SupplierDirectoryDecoding.decode(SupplierPage.self, envelope: try fixture("supplier_directory_list"))
        XCTAssertEqual(SupplierDirectoryPresentation.subtitle(page.suppliers[1]), "Dana Brooks · Knoxville, TN · (865) 555-0100")
        XCTAssertEqual(SupplierDirectoryPresentation.statusLine(status: "Active", isPreferred: true), "Active · Preferred supplier")
        XCTAssertEqual(SupplierDirectoryPresentation.reasonText(["name", "phone"]), "Same name · Same phone number")
        XCTAssertEqual(SupplierDirectoryPresentation.emptyMessage(search: "hose", scope: .part, status: .active),
                       "No supplier is on file for a part matching “hose”.")
        XCTAssertEqual(SupplierDirectoryPresentation.partLine(SupplierPartItem(uniqueId: nil, name: "Seal Set", partNumber: "SS-9", slot: "alternate")),
                       "#SS-9 · Alternate source")
    }

    func testOfflineFilteringSearchesTheSameFields() throws {
        let page = try SupplierDirectoryDecoding.decode(SupplierPage.self, envelope: try fixture("supplier_directory_list"))
        let all = page.suppliers
        XCTAssertEqual(SupplierDirectoryPresentation.filter(all, search: "", status: .active).map(\.name), ["Smoky Mountain Hydraulics"])
        XCTAssertEqual(SupplierDirectoryPresentation.filter(all, search: "", status: .inactive).map(\.name), ["Midway Parts"])
        for term in ["dana", "8655550100", "same-day", "hydraulics", "KNOXVILLE"] {
            XCTAssertEqual(SupplierDirectoryPresentation.filter(all, search: term, status: .all).map(\.name), ["Smoky Mountain Hydraulics"], term)
        }
        XCTAssertTrue(SupplierDirectoryPresentation.filter(all, search: "zzz", status: .all).isEmpty)
    }

    func testTheReadOnlyCopyKeepsWhatKabbaReturnedAndIsBounded() throws {
        var storage: [String: Data] = [:]
        let copy = SupplierDirectoryOfflineCopy(read: { storage[$0] }, write: { key, data in storage[key] = data })
        let envelope = try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_detail"))
        let page = try SupplierDirectoryDecoding.decode(SupplierPage.self, envelope: try fixture("supplier_directory_list"))

        XCTAssertTrue(copy.allSummaries().isEmpty)
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        copy.saveDetail(envelope, at: savedAt)
        copy.saveList(page.suppliers)
        XCTAssertEqual(copy.detail(envelope.supplier.uniqueId), SupplierCachedDetail(envelope: envelope, savedAt: savedAt))
        XCTAssertEqual(Set(copy.allSummaries().map(\.name)), ["Midway Parts", "Smoky Mountain Hydraulics"])

        // Bounded: the oldest opened supplier drops off.
        for i in 0..<SupplierDirectoryOfflineCopy.maxDetails {
            let other = SupplierDetailEnvelope(supplier: SupplierDetail(uniqueId: "SUP-\(i)", name: "S\(i)", status: "Active", isActive: true, isPreferred: false,
                                                                        phone: nil, email: nil, website: nil,
                                                                        address: SupplierAddress(street: nil, city: nil, state: nil, zipCode: nil, country: nil, oneLine: nil),
                                                                        category: nil, tags: [], contacts: [], parts: SupplierParts(count: 0, items: []),
                                                                        paymentTerms: nil, updatedAt: nil), can: envelope.can)
            copy.saveDetail(other)
        }
        XCTAssertNil(copy.detail(envelope.supplier.uniqueId))
        XCTAssertNil(storage[SupplierDirectoryOfflineCopy.detailPrefix + envelope.supplier.uniqueId], "evicted, not just forgotten")
    }

    func testTheCopyIsCompanyScoped() {
        XCTAssertTrue(DispatchOfflineTenantStorage.isTenantScoped(SupplierDirectoryOfflineCopy.indexKey))
        XCTAssertTrue(DispatchOfflineTenantStorage.isTenantScoped(SupplierDirectoryOfflineCopy.listKey))
        XCTAssertTrue(DispatchOfflineTenantStorage.isTenantScoped(SupplierDirectoryOfflineCopy.detailPrefix + "SUP-1"))
        XCTAssertNil(DispatchOfflineTenantStorage.storageKey(SupplierDirectoryOfflineCopy.listKey, tenantKey: nil), "signed out: nothing is read or written")
        XCTAssertNotEqual(DispatchOfflineTenantStorage.storageKey(SupplierDirectoryOfflineCopy.listKey, tenantKey: "a"),
                          DispatchOfflineTenantStorage.storageKey(SupplierDirectoryOfflineCopy.listKey, tenantKey: "b"))
    }
}
