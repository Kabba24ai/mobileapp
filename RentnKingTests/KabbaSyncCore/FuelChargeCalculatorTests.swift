//
//  FuelChargeCalculatorTests.swift
//  KabbaSyncCoreTests
//
//  The phone's fuel pricing against the SHARED vectors (Fixtures/fuel_charge_vectors.json,
//  written by Laravel's tests/Fixtures/fuel-charge/generate_vectors.py — a third, independent
//  implementation). Laravel's FuelChargeCalculatorTest reads the same file, so the phone and
//  the server cannot drift apart without a failing test on both sides.
//

import XCTest
@testable import KabbaSyncCore

final class FuelChargeCalculatorTests: XCTestCase {

    private struct Vector: Decodable {
        let name: String
        let fluid: String
        let capacity: String
        let prices: [String: String]
        let delivered: String
        let returned: String
        let delivery_completed: Bool
        let prepaid_fuel: Bool
        let expected_eighths: Int
        let expected_amount: String
        let expected_outcome: String
    }

    private struct VectorFile: Decodable {
        let version: Int
        let vectors: [Vector]
    }

    private func vectors() throws -> [Vector] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fuel_charge_vectors.json")
        return try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: url)).vectors
    }

    private static let outcomeNames: [FuelChargeLine.Outcome: String] = [
        .charged: "charged", .noUsage: "no_usage", .notReturned: "not_returned", .prepaid: "prepaid",
        .deliveryNotRecorded: "delivery_not_recorded", .deliveryMissing: "delivery_missing",
        .priceMissing: "price_missing", .capacityMissing: "capacity_missing",
    ]

    func testEverySharedVector() throws {
        let all = try vectors()
        XCTAssertGreaterThan(all.count, 250, "every level pair for every fluid plus the rules")
        for v in all {
            guard let fluid = FuelFluid(rawValue: v.fluid) else { return XCTFail("unknown fluid in \(v.name)") }
            let profile = FuelTankProfile(powerSourceType: fluid == .def ? "diesel" : fluid.rawValue,
                                          hasDef: fluid == .def ? "Yes" : "No",
                                          dieselTankCapacity: fluid == .diesel ? v.capacity : "0",
                                          gasTankCapacity: fluid == .gas ? v.capacity : "0",
                                          defTankCapacity: fluid == .def ? v.capacity : "0")
            let line = FuelChargeCalculator.line(fluid: fluid, profile: profile, prices: FuelPrices(settings: v.prices.reduce(into: [:]) { $0["\($1.key)_price_per_gallon"] = $1.value }),
                                                 delivered: v.delivered, returned: v.returned,
                                                 deliveryCompleted: v.delivery_completed, prepaidFuel: v.prepaid_fuel)
            XCTAssertEqual(FuelChargeCalculator.amountString(line.amount), v.expected_amount, v.name)
            XCTAssertEqual(line.eighthsUsed, v.expected_eighths, v.name)
            XCTAssertEqual(Self.outcomeNames[line.outcome], v.expected_outcome, v.name)
        }
    }

    // MARK: - The defect this release fixes

    /// TAK-SS-18 on order #4597: a 32 gal diesel machine with a 5 gal DEF tank. Until 1.0.26
    /// its one fuel reading (Full → Empty) was priced as DEF: $19.90. Diesel is $208.00;
    /// DEF is read and charged on its own.
    func testADieselMachineWithADEFTankIsChargedForDieselAndDEFSeparately() {
        let profile = FuelTankProfile(powerSourceType: "diesel", hasDef: "Yes", dieselTankCapacity: "32.00", gasTankCapacity: "0", defTankCapacity: "5.00")
        let prices = FuelPrices(settings: ["diesel_price_per_gallon": "6.50", "gas_price_per_gallon": "4.25", "def_price_per_gallon": "3.98"])
        XCTAssertEqual(profile.fluids, [.diesel, .def])

        let lines = FuelChargeCalculator.lines(profile: profile, prices: prices,
                                               readings: [.diesel: ("9", "1"), .def: ("9", "5")],
                                               deliveryCompleted: true, prepaidFuel: false)
        XCTAssertEqual(lines.map(\.fluid), [.diesel, .def])
        XCTAssertEqual(FuelChargeCalculator.amountString(lines[0].amount), "208.00")
        XCTAssertEqual(FuelChargeCalculator.amountString(lines[1].amount), "9.95")
        XCTAssertEqual(FuelChargeCalculator.amountString(FuelChargeCalculator.total(lines)), "217.95")
    }

    func testDEFNeverOverridesTheDieselReadingOrPrice() {
        let profile = FuelTankProfile(powerSourceType: "diesel", hasDef: "Yes", dieselTankCapacity: "32", gasTankCapacity: nil, defTankCapacity: "5")
        let prices = FuelPrices(diesel: 6.5, gas: 4.25, def: 3.98)
        // DEF untouched (no DEF reading at all): the diesel reading is priced as diesel.
        let lines = FuelChargeCalculator.lines(profile: profile, prices: prices, readings: [.diesel: ("9", "1")],
                                               deliveryCompleted: true, prepaidFuel: false)
        XCTAssertEqual(lines[0].pricePerGallon, 6.5)
        XCTAssertEqual(lines[0].capacity, 32)
        XCTAssertEqual(lines[0].amount, 208)
        XCTAssertEqual(lines[1].outcome, .deliveryNotRecorded)
        XCTAssertEqual(lines[1].amount, 0)
    }

    func testIdenticalLevelsForEveryFluid() {
        XCTAssertEqual(FuelLevel.options.map(\.id), [9, 8, 7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(FuelLevel.options.map(\.name), ["Full", "7/8", "3/4", "5/8", "1/2", "3/8", "1/4", "1/8", "Empty"])
        XCTAssertEqual(FuelLevel.returnOptions.map(\.id), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(FuelLevel.name("10"), "Pre-Paid")
        XCTAssertNil(FuelLevel.name(""))
        XCTAssertNil(FuelLevel.value("0"))
        XCTAssertNil(FuelLevel.value("11"))
    }

    func testMachinesWithoutFuelHaveNoReading() {
        for source in ["electric", "batteries", "", nil] as [String?] {
            let profile = FuelTankProfile(powerSourceType: source, hasDef: "No", dieselTankCapacity: "0", gasTankCapacity: "0", defTankCapacity: "0")
            XCTAssertEqual(profile.fluids, [], "\(source ?? "nil")")
        }
        let gas = FuelTankProfile(powerSourceType: "Gas", hasDef: "no", dieselTankCapacity: nil, gasTankCapacity: "5.00", defTankCapacity: nil)
        XCTAssertEqual(gas.fluids, [.gas])
    }

    func testPricesComeFromSystemConfigurationOnly() {
        let prices = FuelPrices(settings: ["diesel_price_per_gallon": " 6.50 ", "gas_price_per_gallon": "", "def_price_per_gallon": "abc"])
        XCTAssertEqual(prices.diesel, Decimal(string: "6.50"))
        XCTAssertNil(prices.gas)
        XCTAssertNil(prices.def)
        XCTAssertNil(FuelPrices(settings: [:]).diesel)
    }

    func testAmountsUseTheCentAndTheDotWhateverTheDeviceLocale() {
        XCTAssertEqual(FuelChargeCalculator.amountString(Decimal(string: "11.375")!), "11.38")
        XCTAssertEqual(FuelChargeCalculator.amountString(Decimal(string: "47.53125")!), "47.53")
        XCTAssertEqual(FuelChargeCalculator.amountString(0), "0.00")
        XCTAssertEqual(FuelChargeCalculator.amountString(Decimal(string: "1234.5")!), "1234.50")
    }

    // MARK: - Contract: does this server store DEF readings?

    /// The 1.0.26 backend adds `def_initial_reading` / `def_final_reading` to the context's
    /// operational block (Laravel MobileContractFixturesTest pins the same file). A context
    /// from an older server has no such keys → no DEF row, no DEF reading sent.
    func testTheContextSaysWhetherLaravelStoresDEFReadings() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/return_checklist_context.json")
        let data = try Data(contentsOf: url)
        let current = try ChecklistContext.decode(envelopeData: data)
        XCTAssertTrue(current.operational.carriesDEFReadings)
        XCTAssertEqual(current.operational.defInitialReading, "")

        let older = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .filter { !$0.contains("\"def_initial_reading\"") && !$0.contains("\"def_final_reading\"") }
            .joined(separator: "\n")
        let legacy = try ChecklistContext.decode(envelopeData: Data(older.utf8))
        XCTAssertFalse(legacy.operational.carriesDEFReadings)
        XCTAssertNil(legacy.operational.defFinalReading)
    }
}
