//
//  FuelChecklistRows.swift
//  RentnKing — Sync App layer
//
//  The checklist's fuel rows for one machine, built and priced in ONE place.
//
//  A machine gets one row per fluid it is read for (FuelTankProfile.fluids):
//    • its primary fuel — "Fuel (Diesel)" / "Fuel (Gas)" — as before;
//    • "DEF" — an independent row with the SAME eighth-tank levels, only when Equipment
//      Management says the machine has a DEF tank AND Laravel carries DEF readings for the
//      line (the 1.0.26 backend adds `def_initial_reading` / `def_final_reading`; a server
//      without them never gets a DEF reading it would silently drop).
//
//  Both rows are `type == "fuel"` so every existing rule for fuel rows (required, blank,
//  machine-row replacement, excluded from template answers) applies to DEF unchanged;
//  `fuelFluid == "def"` is the only difference. The readings themselves live in the row
//  AND in the product's NoteModel (selectFule* for the primary fuel, selectDef* for DEF);
//  the capture reads NoteModel, the price reads the row — this file keeps them together.
//
//  Pricing is FuelChargeCalculator (Sync/Core/FuelCharge.swift) — never re-derived here.
//

import Foundation
import ObjectMapper

enum FuelChecklistRows {

    // MARK: - Contract capability

    /// Laravel stores independent DEF readings for this line: the order feed or the
    /// checklist context carries the DEF keys (even empty).
    static func carriesDEFReadings(product: ProductModel, context: ChecklistContext?) -> Bool {
        product.def_initial_reading != nil || (context?.operational.carriesDEFReadings ?? false)
    }

    // MARK: - Building

    /// The machine's tank facts as the checklist rows carry them.
    struct TankFacts: Equatable {
        var powerSourceType: String
        var hasDef: String
        var dieselTankCapacity: String
        var gasTankCapacity: String
        var defTankCapacity: String

        init(powerSourceType: String, hasDef: String, dieselTankCapacity: String, gasTankCapacity: String, defTankCapacity: String) {
            self.powerSourceType = powerSourceType
            self.hasDef = hasDef
            self.dieselTankCapacity = dieselTankCapacity
            self.gasTankCapacity = gasTankCapacity
            self.defTankCapacity = defTankCapacity
        }

        init(machine: MachineModel) {
            self.init(powerSourceType: machine.powerSourceType, hasDef: machine.hasDEF,
                      dieselTankCapacity: machine.diesel_tank_capacity, gasTankCapacity: machine.gas_tank_capacity,
                      defTankCapacity: machine.def_tank_capacity)
        }

        init(equipment: ChecklistContext.Equipment) {
            self.init(powerSourceType: equipment.powerSourceType ?? "", hasDef: equipment.hasDef ?? "",
                      dieselTankCapacity: equipment.dieselTankCapacity ?? "", gasTankCapacity: equipment.gasTankCapacity ?? "",
                      defTankCapacity: equipment.defTankCapacity ?? "")
        }

        var profile: FuelTankProfile {
            FuelTankProfile(powerSourceType: powerSourceType, hasDef: hasDef, dieselTankCapacity: dieselTankCapacity,
                            gasTankCapacity: gasTankCapacity, defTankCapacity: defTankCapacity)
        }
    }

    /// The fuel rows for a machine, readings seeded from what the server recorded for the line.
    /// An electric / battery / unknown machine has no fuel row (unchanged rule: power source required).
    static func rows(facts: TankFacts, product: ProductModel, defSupported: Bool) -> [CustomerCheckListModel] {
        guard !facts.powerSourceType.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var result: [CustomerCheckListModel] = []
        if var primary = blankRow(facts: facts) {
            let title = "Fuel (\(facts.powerSourceType.capitalizingFirstLetter()))"
            primary.question_delivery_text = title
            primary.question_return_text = title
            primary.fuelFluid = nil
            primary.selectFuleDelivery = product.fuel_initial_reading
            primary.selectFuleReturn = product.fuel_final_reading
            result.append(primary)
        }
        if defSupported, facts.profile.hasDEF, var def = blankRow(facts: facts) {
            def.question_delivery_text = FuelFluid.def.rowTitle
            def.question_return_text = FuelFluid.def.rowTitle
            def.fuelFluid = FuelFluid.def.rawValue
            def.selectFuleDelivery = product.def_initial_reading ?? ""
            def.selectFuleReturn = product.def_final_reading ?? ""
            result.append(def)
        }
        return result
    }

    static func rows(machine: MachineModel?, product: ProductModel, defSupported: Bool) -> [CustomerCheckListModel] {
        guard let machine = machine else { return [] }
        return rows(facts: TankFacts(machine: machine), product: product, defSupported: defSupported)
    }

    private static func blankRow(facts: TankFacts) -> CustomerCheckListModel? {
        guard var row = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:])) else { return nil }
        row.type = "fuel"
        stamp(&row, facts: facts)
        return row
    }

    private static func stamp(_ row: inout CustomerCheckListModel, facts: TankFacts) {
        row.fuleType = facts.powerSourceType
        row.isDEF = facts.hasDef
        row.diesel_tank_capacity = facts.dieselTankCapacity
        row.gas_tank_capacity = facts.gasTankCapacity
        row.def_tank_capacity = facts.defTankCapacity
    }

    // MARK: - Reconciling rows that already exist (draft restore, live equipment data)

    /// Brings existing fuel rows in line with the machine's tank facts WITHOUT touching any
    /// reading the employee entered: refreshes tank data (Equipment Management may have
    /// changed since the order line's snapshot), adds an owed DEF row right after the primary
    /// fuel row, removes a DEF row that is no longer owed (and its NoteModel readings).
    /// Returns true when anything changed.
    @discardableResult
    static func reconcile(_ questions: inout [CustomerCheckListModel], facts: TankFacts, product: ProductModel,
                          other: NoteModel?, defSupported: Bool) -> Bool {
        guard let primaryIndex = questions.firstIndex(where: { $0.type == "fuel" && !$0.isDEFRow }) else { return false }
        var changed = false
        for index in questions.indices where questions[index].type == "fuel" {
            let before = TankFacts(powerSourceType: questions[index].fuleType ?? "", hasDef: questions[index].isDEF ?? "",
                                   dieselTankCapacity: questions[index].diesel_tank_capacity ?? "",
                                   gasTankCapacity: questions[index].gas_tank_capacity ?? "",
                                   defTankCapacity: questions[index].def_tank_capacity ?? "")
            if before != facts {
                stamp(&questions[index], facts: facts)
                changed = true
            }
        }
        let owesDEF = defSupported && facts.profile.hasDEF
        let defIndex = questions.firstIndex(where: { $0.isDEFRow })
        if owesDEF, defIndex == nil, let def = rows(facts: facts, product: product, defSupported: true).first(where: { $0.isDEFRow }) {
            var row = def
            // A reading already on this phone (NoteModel) wins over the server's empty one.
            if let other = other {
                if !other.selectDefDelivery.isEmpty { row.selectFuleDelivery = other.selectDefDelivery }
                if !other.selectDefReturn.isEmpty { row.selectFuleReturn = other.selectDefReturn }
            }
            questions.insert(row, at: primaryIndex + 1)
            changed = true
        } else if !owesDEF, let index = defIndex {
            questions.remove(at: index)
            other?.selectDefDelivery = ""
            other?.selectDefReturn = ""
            changed = true
        }
        return changed
    }

    // MARK: - Readings

    /// The NoteModel side of a fuel row's reading (the capture reads NoteModel).
    static func setReading(_ value: String, isDelivery: Bool, row: CustomerCheckListModel, other: NoteModel) {
        switch (row.isDEFRow, isDelivery) {
        case (true, true): other.selectDefDelivery = value
        case (true, false): other.selectDefReturn = value
        case (false, true): other.selectFuleDelivery = value
        case (false, false): other.selectFuleReturn = value
        }
    }

    /// What the server recorded for this row's fluid (the "untouched default" for input detection).
    static func serverReading(row: CustomerCheckListModel, product: ProductModel, isDelivery: Bool) -> String {
        if row.isDEFRow { return (isDelivery ? product.def_initial_reading : product.def_final_reading) ?? "" }
        return isDelivery ? product.fuel_initial_reading : product.fuel_final_reading
    }

    // MARK: - Pricing

    /// The fluid a fuel row reads: DEF for the DEF row, otherwise the machine's primary fuel.
    /// Rows saved before 1.0.26 (no `fuelFluid`) are the primary fuel row — that is what the
    /// employee read there ("Fuel (Diesel)"), whatever the old DEF flag said.
    static func fluid(of row: CustomerCheckListModel) -> FuelFluid? {
        guard row.type == "fuel" else { return nil }
        if row.isDEFRow { return .def }
        return profile(of: row).primaryFluid
    }

    static func profile(of row: CustomerCheckListModel) -> FuelTankProfile {
        FuelTankProfile(powerSourceType: row.fuleType, hasDef: row.isDEF, dieselTankCapacity: row.diesel_tank_capacity,
                        gasTankCapacity: row.gas_tank_capacity, defTankCapacity: row.def_tank_capacity)
    }

    /// System Configuration prices from the cached "Price Settings" list.
    static func prices(from list: [(name: String?, value: String?)]) -> FuelPrices {
        var settings: [String: String] = [:]
        for item in list {
            if let name = item.name, let value = item.value { settings[name] = value }
        }
        return FuelPrices(settings: settings)
    }

    /// The priced reading for ONE fuel row, or nil when the row reads no fuel.
    static func line(for row: CustomerCheckListModel, product: ProductModel, prices: FuelPrices) -> FuelChargeLine? {
        guard let fluid = fluid(of: row) else { return nil }
        let prepaid = (product.objProductData?.arrProductSelectdOptions ?? []).contains("rental_prepaid_fuel")
        return FuelChargeCalculator.line(fluid: fluid, profile: profile(of: row), prices: prices,
                                         delivered: row.selectFuleDelivery, returned: row.selectFuleReturn,
                                         deliveryCompleted: product.is_delivered == true, prepaidFuel: prepaid)
    }

    /// What the delivery column shows for a fuel row on screen.
    static func deliveredText(for row: CustomerCheckListModel, product: ProductModel) -> String {
        if let name = FuelLevel.name(row.selectFuleDelivery) { return name }
        guard product.is_delivered == true else { return "Select" }
        // A primary fuel reading missing on a delivered line counts as Full (Admin Override);
        // DEF is never assumed.
        return row.isDEFRow ? "Not Recorded" : "Admin Override"
    }

    static func returnedText(for row: CustomerCheckListModel) -> String {
        FuelLevel.name(row.selectFuleReturn) ?? "Select"
    }
}
