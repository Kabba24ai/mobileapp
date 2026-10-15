import XCTest
import ObjectMapper
@testable import RentnKing

/// Fuel and DEF on the checklist (1.0.26): independent rows, per-fluid pricing, and every
/// order product submitting ONLY its own charges.
final class FuelDEFChecklistHostedTests: XCTestCase {

    private let prices = FuelPrices(settings: ["diesel_price_per_gallon": "6.50",
                                               "gas_price_per_gallon": "4.25",
                                               "def_price_per_gallon": "3.98"])

    private func machine(_ uid: String = "EQ-1", power: String, hasDef: String = "No",
                         diesel: String = "", gas: String = "", def: String = "") -> MachineModel {
        MachineModel(map: Map(mappingType: .fromJSON, JSON: [
            "unique_id": uid, "power_source_type": power, "has_def": hasDef,
            "diesel_tank_capacity": diesel, "gas_tank_capacity": gas, "def_tank_capacity": def,
        ]))!
    }

    /// An order line; `carriesDEF` simulates a backend that sends the DEF keys.
    private func product(_ uid: String, machine: MachineModel?, delivered: Bool = true,
                         fuel: (String, String) = ("", ""), def: (String, String)? = nil) -> ProductModel {
        var product = ProductModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        product.unique_id = uid
        product.is_delivered = delivered
        product.objMachine = machine
        product.fuel_initial_reading = fuel.0
        product.fuel_final_reading = fuel.1
        if let def = def {
            product.def_initial_reading = def.0
            product.def_final_reading = def.1
        }
        product.arrQuestions = FuelChecklistRows.rows(machine: machine, product: product,
                                                      defSupported: FuelChecklistRows.carriesDEFReadings(product: product, context: nil))
        return product
    }

    private func amount(_ value: Decimal) -> String { FuelChargeCalculator.amountString(value) }

    // MARK: - Rows

    func testADieselMachineWithADEFTankGetsAnIndependentDEFRow() {
        let p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"),
                        fuel: ("9", ""), def: ("8", ""))
        XCTAssertEqual(p.arrQuestions.map { $0.question_delivery_text ?? "" }, ["Fuel (Diesel)", "DEF"])
        XCTAssertEqual(p.arrQuestions.map(\.isDEFRow), [false, true])
        XCTAssertEqual(p.arrQuestions.map { $0.type ?? "" }, ["fuel", "fuel"], "DEF keeps every fuel-row rule (required, blank, machine row)")
        XCTAssertEqual(p.arrQuestions[0].selectFuleDelivery, "9", "the diesel reading")
        XCTAssertEqual(p.arrQuestions[1].selectFuleDelivery, "8", "the DEF reading, independent")
    }

    func testNoDEFRowUntilLaravelCarriesDEFReadings() {
        let defMachine = machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00")
        XCTAssertEqual(product("P0", machine: defMachine).arrQuestions.count, 1, "a server without DEF readings would drop them")
        XCTAssertEqual(product("P0", machine: machine(power: "diesel", diesel: "28.00"), def: ("", "")).arrQuestions.count, 1,
                       "no DEF tank, no DEF row")
    }

    func testPowerSourceRules() {
        XCTAssertTrue(product("P0", machine: machine(power: "")).arrQuestions.isEmpty, "no power source, no fuel row")
        let electric = product("P0", machine: machine(power: "electric"), fuel: ("9", "1"))
        XCTAssertEqual(electric.arrQuestions.count, 1, "unchanged: electric units keep their row")
        XCTAssertNil(FuelChecklistRows.line(for: electric.arrQuestions[0], product: electric, prices: prices), "and are never priced")
    }

    // MARK: - Pricing

    /// #4597 (TAK-SS-18): the row a 1.0.25 draft saved says isDEF = "Yes" and holds the DIESEL
    /// level the employee read under "Fuel (Diesel)". It is priced as diesel now: $208.00, not $19.90.
    func testARowSavedBeforeThisReleaseIsPricedAsTheMachinesFuel() {
        var p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"), fuel: ("9", "1"))
        var legacy = p.arrQuestions[0]
        legacy.fuelFluid = nil
        legacy.isDEF = "Yes"
        p.arrQuestions = [legacy]
        let line = FuelChecklistRows.line(for: legacy, product: p, prices: prices)
        XCTAssertEqual(line?.fluid, .diesel)
        XCTAssertEqual(amount(line?.amount ?? -1), "208.00")
    }

    func testDieselAndDEFAreSummedOnTheMachinesLine() {
        let p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"),
                        fuel: ("9", "1"), def: ("8", "4"))
        let priced = ChecklistLineCharges.compute(products: [p], completedReport: false, fuelPrices: prices, cleaningPrice: { _ in 0 })
        XCTAssertEqual(amount(priced.charges["P0"]!.fuel), "217.95", "$208.00 diesel + $9.95 DEF")
        XCTAssertEqual(priced.charges["P0"]!.fuelString, "217.95")
    }

    func testADEFDeliveryLevelIsNeverAssumed() {
        let p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"),
                        fuel: ("", "5"), def: ("", "3"))
        XCTAssertEqual(FuelChecklistRows.deliveredText(for: p.arrQuestions[0], product: p), "Admin Override", "primary: counted Full")
        XCTAssertEqual(FuelChecklistRows.deliveredText(for: p.arrQuestions[1], product: p), "Not Recorded", "DEF: never assumed")
        let priced = ChecklistLineCharges.compute(products: [p], completedReport: false, fuelPrices: prices, cleaningPrice: { _ in 0 })
        XCTAssertEqual(amount(priced.charges["P0"]!.fuel), "104.00", "diesel Full→1/2 only; no DEF charge")
    }

    // MARK: - One line, one charge (the duplicate-billing defect)

    /// Order #4947 shape: a TL8 (28 gal) returned with a tilt trailer. Until 1.0.26 both lines
    /// were sent the TL8's $91.00 and Laravel billed it twice.
    func testEachLineSubmitsOnlyItsOwnFuel() throws {
        let tl8 = product("P0", machine: machine("EQ-TL8", power: "diesel", diesel: "28.00"), fuel: ("9", "5"))
        let trailer = product("P1", machine: nil)
        let saw = product("P2", machine: machine("EQ-SAW", power: "gas", gas: "1.00"), fuel: ("9", "9"))
        let mower = product("P3", machine: machine("EQ-ZT", power: "gas", gas: "5.00"), fuel: ("9", "1"))
        let priced = ChecklistLineCharges.compute(products: [tl8, trailer, saw, mower], completedReport: false,
                                                  fuelPrices: prices, cleaningPrice: { _ in 0 })
        XCTAssertEqual(priced.charges.mapValues { $0.fuelString }, ["P0": "91.00", "P1": "0.00", "P2": "0.00", "P3": "21.25"])
        XCTAssertEqual(priced.charges["P1"]!.totalString, "0.00", "the trailer owes nothing")

        // What each line's submission carries (legacy shape needs no context).
        for (index, item) in [tl8, trailer, saw, mower].enumerated() {
            let fields = ChecklistCaptureFactory.legacyItem(product: item, other: NoteModel(), isDelivery: false,
                                                            orderUniqueId: "ORD", charges: priced.charges[item.unique_id!]!)
            XCTAssertEqual(fields["fuel_total_charge"] as? String, ["91.00", "0.00", "0.00", "21.25"][index], item.unique_id!)
        }
    }

    func testTheCanonicalCaptureCarriesItsLinesChargesAndDEFReadings() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../KabbaSyncCore/Fixtures/return_checklist_context.json").standardizedFileURL
        let context = try ChecklistContext.decode(envelopeData: Data(contentsOf: url))

        let p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"),
                        fuel: ("9", "1"), def: ("8", "4"))
        let note = NoteModel()
        note.selectFuleReturn = "1"
        note.selectDefReturn = "4"
        let charges = ChecklistLineCharge(total: 217.95, fuel: Decimal(string: "217.95")!, cleaning: 0)
        let capture = ChecklistCaptureFactory.make(context: context, product: p, other: note, isDelivery: false, charges: charges)
        guard case .object(let body) = ChecklistOperationBuilder.completionPayload(capture, signatureClientMediaId: nil) else {
            return XCTFail("payload is an object")
        }
        XCTAssertEqual(body["fuel_total_charge"]?.stringValue, "217.95")
        XCTAssertEqual(body["total_charge"]?.stringValue, "217.95")
        XCTAssertEqual(body["fuel_final_reading"]?.stringValue, "1")
        XCTAssertEqual(body["def_final_reading"]?.stringValue, "4")

        // A line without a DEF row never sends a DEF reading, whatever the NoteModel holds.
        let plain = product("P1", machine: machine(power: "diesel", diesel: "28.00"), fuel: ("9", "5"))
        let stray = NoteModel()
        stray.selectDefReturn = "4"
        let plainCapture = ChecklistCaptureFactory.make(context: context, product: plain, other: stray, isDelivery: false,
                                                        charges: ChecklistLineCharge())
        guard case .object(let plainBody) = ChecklistOperationBuilder.completionPayload(plainCapture, signatureClientMediaId: nil) else {
            return XCTFail("payload is an object")
        }
        XCTAssertNil(plainBody["def_final_reading"])
        XCTAssertEqual(plainBody["fuel_total_charge"]?.stringValue, "0.00")
    }

    func testACompletedReportShowsEachLinesOwnServerTotal() {
        var a = product("P0", machine: nil)
        a.total_charge = 91
        var b = product("P1", machine: nil)
        b.total_charge = 0
        let priced = ChecklistLineCharges.compute(products: [a, b], completedReport: true, fuelPrices: prices, cleaningPrice: { _ in 0 })
        XCTAssertEqual(priced.charges["P0"]!.total, 91)
        XCTAssertEqual(priced.charges["P1"]!.total, 0)
    }

    func testHoursOverageStaysOnItsLine() {
        var p = product("P0", machine: nil)
        p.allocated_hours = 8
        var hours = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        hours.type = "text"; hours.startHours = 100; hours.endHours = 110.2; hours.hour_rate = 25
        p.arrQuestions = [hours]
        let other = product("P1", machine: nil)
        let priced = ChecklistLineCharges.compute(products: [p, other], completedReport: false, fuelPrices: prices, cleaningPrice: { _ in 0 })
        XCTAssertEqual(priced.charges["P0"]!.total, 75, "11 h rounded up − 8 allocated = 3 h × $25")
        XCTAssertEqual(priced.products[0].arrQuestions[0].additinal, 3)
        XCTAssertEqual(priced.charges["P1"]!.total, 0)
    }

    // MARK: - Drafts and Equipment Management changes

    func testADraftFromAnOlderBuildGainsTheDEFRowAndKeepsItsReadings() {
        let defMachine = machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00")
        var p = product("P0", machine: defMachine, fuel: ("9", ""))
        var legacy = p.arrQuestions[0]
        legacy.selectFuleReturn = "3"   // entered on 1.0.25
        legacy.fuelFluid = nil
        p.arrQuestions = [legacy]
        p.def_initial_reading = "7"     // the backend now carries DEF
        p.def_final_reading = ""
        let note = NoteModel()
        note.selectFuleReturn = "3"

        var questions = p.arrQuestions
        XCTAssertTrue(FuelChecklistRows.reconcile(&questions, facts: .init(machine: defMachine), product: p, other: note, defSupported: true))
        XCTAssertEqual(questions.map(\.isDEFRow), [false, true])
        XCTAssertEqual(questions[0].selectFuleReturn, "3", "the entered diesel reading is untouched")
        XCTAssertEqual(questions[1].selectFuleDelivery, "7", "DEF delivery level from the server")
        XCTAssertFalse(FuelChecklistRows.reconcile(&questions, facts: .init(machine: defMachine), product: p, other: note, defSupported: true),
                       "idempotent")
    }

    func testEquipmentManagementTankChangesReachExistingRowsAndARemovedDEFTankDropsItsRow() {
        let before = machine(power: "gas", gas: "5.00")
        var p = product("P0", machine: before, fuel: ("9", "1"))
        var questions = p.arrQuestions
        let after = FuelChecklistRows.TankFacts(powerSourceType: "gas", hasDef: "No", dieselTankCapacity: "", gasTankCapacity: "6.00", defTankCapacity: "")
        XCTAssertTrue(FuelChecklistRows.reconcile(&questions, facts: after, product: p, other: nil, defSupported: true))
        p.arrQuestions = questions
        XCTAssertEqual(amount(FuelChecklistRows.line(for: questions[0], product: p, prices: prices)!.amount), "25.50", "6 gal now, not the snapshot's 5")

        let defMachine = machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00")
        let q = product("P1", machine: defMachine, def: ("9", "2"))
        var rows = q.arrQuestions
        let note = NoteModel()
        note.selectDefReturn = "2"
        let noDef = FuelChecklistRows.TankFacts(powerSourceType: "diesel", hasDef: "No", dieselTankCapacity: "32.00", gasTankCapacity: "", defTankCapacity: "")
        XCTAssertTrue(FuelChecklistRows.reconcile(&rows, facts: noDef, product: q, other: note, defSupported: true))
        XCTAssertEqual(rows.map(\.isDEFRow), [false])
        XCTAssertEqual(note.selectDefReturn, "", "a DEF reading is never sent for a machine without a DEF tank")
    }

    func testNoteModelKeepsDEFReadingsAcrossTheDraft() {
        let note = NoteModel()
        note.selectFuleDelivery = "9"
        note.selectDefDelivery = "6"
        note.selectDefReturn = "2"
        let restored = NoteModel.fromDict(note.toDict())
        XCTAssertEqual(restored.selectFuleDelivery, "9")
        XCTAssertEqual(restored.selectDefDelivery, "6")
        XCTAssertEqual(restored.selectDefReturn, "2")
        var older = note.toDict()
        older.removeValue(forKey: "selectDefDelivery")
        older.removeValue(forKey: "selectDefReturn")
        XCTAssertEqual(NoteModel.fromDict(older).selectDefDelivery, "", "a 1.0.25 draft has no DEF reading")
    }

    func testPickingALevelWritesOnlyThatFluidsReading() {
        let p = product("P0", machine: machine(power: "diesel", hasDef: "Yes", diesel: "32.00", def: "5.00"), def: ("", ""))
        let note = NoteModel()
        FuelChecklistRows.setReading("6", isDelivery: true, row: p.arrQuestions[1], other: note)
        FuelChecklistRows.setReading("9", isDelivery: true, row: p.arrQuestions[0], other: note)
        FuelChecklistRows.setReading("2", isDelivery: false, row: p.arrQuestions[1], other: note)
        XCTAssertEqual([note.selectFuleDelivery, note.selectDefDelivery, note.selectFuleReturn, note.selectDefReturn], ["9", "6", "", "2"])
    }
}
