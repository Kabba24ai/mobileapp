import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Mobile issue #10 — the number the Call / Send Message sheet dials and texts. Kabba sends it
/// formatted for reading; the phone needs "+" and digits, with the country code the number
/// already has (only a bare ten-digit number is taken as +1) and nothing at all when there is
/// no number to dial.
final class CustomerPhoneNumberTests: XCTestCase {

    private func dial(_ raw: String?) -> String? { CustomerPhoneNumber(raw)?.dialable }

    func testKabbasFormattedUSNumberDialsWithPlusOne() {
        let number = CustomerPhoneNumber("(865) 555-0142")
        XCTAssertEqual(number?.dialable, "+18655550142")
        XCTAssertEqual(number?.text, "(865) 555-0142", "shown as Kabba sent it")
        XCTAssertEqual(number?.spoken, "(865) 555-0142")
        XCTAssertEqual(number?.callURL?.absoluteString, "tel:+18655550142")
    }

    func testOtherUSSpellingsDialTheSameNumber() {
        for raw in ["865-555-0142", "865.555.0142", "8655550142", "  (865)555-0142 ", "1 865 555 0142", "1-865-555-0142"] {
            XCTAssertEqual(dial(raw), "+18655550142", raw)
        }
    }

    func testAPlusOneNumberKeepsItsCodeOnceAndReadsWithoutIt() {
        let number = CustomerPhoneNumber("+1 (865) 555-0142")
        XCTAssertEqual(number?.dialable, "+18655550142", "never +1+1")
        XCTAssertEqual(number?.spoken, "(865) 555-0142", "the sheet reads it as the Driver Checklist always has")
        XCTAssertEqual(number?.text, "+1 (865) 555-0142")
        XCTAssertEqual(dial("+18655550142"), "+18655550142")
    }

    func testAnInternationalNumberKeepsItsOwnCountryCode() {
        XCTAssertEqual(dial("+44 20 7946 0958"), "+442079460958", "not +1+44…")
        XCTAssertEqual(CustomerPhoneNumber("+44 20 7946 0958")?.spoken, "+44 20 7946 0958")
        XCTAssertEqual(dial("+52 55 1234 5678"), "+525512345678")
        XCTAssertEqual(dial("+1-604-555-0100"), "+16045550100", "Canada is +1 too")
    }

    func testANumberWithoutACountryCodeThatIsNotTenDigitsGetsNoneInvented() {
        XCTAssertEqual(dial("555-0199"), "5550199", "a seven-digit local number is dialled as written")
        XCTAssertEqual(dial("020 7946 0958"), "02079460958")
    }

    func testAnExtensionIsReadButNotDialledIntoTheNumber() {
        let number = CustomerPhoneNumber("(865) 555-0142 ext 12")
        XCTAssertEqual(number?.dialable, "+18655550142")
        XCTAssertEqual(number?.text, "(865) 555-0142 ext 12", "the extension stays on screen for the driver")
        XCTAssertEqual(dial("865-555-0142 x12"), "+18655550142")
        XCTAssertEqual(dial("865-555-0142#12"), "+18655550142")
    }

    func testNoNumberMeansNothingToDial() {
        for raw in [nil, "", "   ", "N/A", "none", "-", "()", "12345", "555-01", "+1 865", "1234567890123456"] {
            XCTAssertNil(CustomerPhoneNumber(raw), String(describing: raw))
        }
    }
}
