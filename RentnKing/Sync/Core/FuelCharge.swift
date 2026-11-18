//
//  FuelCharge.swift
//  KabbaSyncCore
//
//  The ONE place the phone prices a returned machine's fuel.
//
//  A machine has at most two fluids the customer can use up:
//    • its primary fuel — diesel or gas, from Equipment Management's power source;
//    • DEF (diesel exhaust fluid) — only when Equipment Management says the machine has
//      a DEF tank.
//  Each fluid is read independently, in eighths of a tank, with the SAME levels
//  (`FuelLevel.options`). Each fluid is priced on its own: the System Configuration price
//  per gallon × that fluid's tank capacity × eighths used ÷ 8, rounded to the cent.
//  The fuel charge for the machine is the sum of its fluids.
//
//  Until 1.0.26 a DEF tank REPLACED the diesel price and capacity for the machine's only
//  fuel reading (a diesel machine with a 5-gallon DEF tank was charged as if its diesel
//  were DEF). Nothing here ever lets one fluid's price, capacity or reading stand in for
//  another's.
//
//  Rules kept from the existing checklist (unchanged behaviour):
//    • used = delivered − returned eighths; nothing is charged when the machine came back
//      at the same level or fuller;
//    • a delivered level of 10 (legacy "Prepaid") charges nothing;
//    • the product option "rental_prepaid_fuel" charges nothing;
//    • the PRIMARY fuel's delivery reading, when missing on a delivered line (an admin
//      completed the delivery), counts as Full — the "Admin Override" shown on screen.
//  New rule: a DEF delivery reading is never assumed. Without a recorded DEF delivery level
//  there is no DEF charge — a customer is never billed for DEF on a guess.
//

import Foundation

enum FuelFluid: String, Codable, CaseIterable, Equatable {
    case diesel
    case gas
    case def

    /// The System Configuration setting that holds this fluid's price per gallon.
    var priceSettingName: String {
        switch self {
        case .diesel: return "diesel_price_per_gallon"
        case .gas: return "gas_price_per_gallon"
        case .def: return "def_price_per_gallon"
        }
    }

    /// How the checklist names the reading.
    var rowTitle: String {
        switch self {
        case .diesel: return "Fuel (Diesel)"
        case .gas: return "Fuel (Gas)"
        case .def: return "DEF"
        }
    }
}

/// Eighth-tank levels, identical for every fluid. Ids are what Laravel stores.
enum FuelLevel {
    static let full = 9
    static let empty = 1
    /// Legacy "Prepaid" delivery level (no longer offered; still honoured when stored).
    static let prepaid = 10

    struct Option: Equatable {
        let id: Int
        let name: String
    }

    /// Delivery order (Full first). The return picker lists the same options reversed.
    static let options: [Option] = [
        Option(id: 9, name: "Full"),
        Option(id: 8, name: "7/8"),
        Option(id: 7, name: "3/4"),
        Option(id: 6, name: "5/8"),
        Option(id: 5, name: "1/2"),
        Option(id: 4, name: "3/8"),
        Option(id: 3, name: "1/4"),
        Option(id: 2, name: "1/8"),
        Option(id: 1, name: "Empty"),
    ]

    static var returnOptions: [Option] { options.reversed() }

    /// A stored reading as a level 1...10, or nil when it is blank, zero or not a level.
    static func value(_ raw: String?) -> Int? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), let number = Int(text) else { return nil }
        return (1...prepaid).contains(number) ? number : nil
    }

    static func name(_ raw: String?) -> String? {
        guard let level = value(raw) else { return nil }
        if level == prepaid { return "Pre-Paid" }
        return options.first(where: { $0.id == level })?.name
    }
}

/// What Equipment Management says about a machine's tanks.
struct FuelTankProfile: Equatable {
    /// diesel or gas; nil for electric / batteries / unknown (no fuel reading at all).
    let primaryFluid: FuelFluid?
    let hasDEF: Bool
    let dieselCapacity: Decimal
    let gasCapacity: Decimal
    let defCapacity: Decimal

    init(powerSourceType: String?, hasDef: String?, dieselTankCapacity: String?, gasTankCapacity: String?, defTankCapacity: String?) {
        switch (powerSourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "diesel": primaryFluid = .diesel
        case "gas": primaryFluid = .gas
        default: primaryFluid = nil
        }
        hasDEF = (hasDef ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yes"
        dieselCapacity = FuelTankProfile.gallons(dieselTankCapacity)
        gasCapacity = FuelTankProfile.gallons(gasTankCapacity)
        defCapacity = FuelTankProfile.gallons(defTankCapacity)
    }

    /// The fluids this machine is read for, in checklist order: primary fuel, then DEF.
    var fluids: [FuelFluid] {
        var result: [FuelFluid] = []
        if let primary = primaryFluid { result.append(primary) }
        if hasDEF { result.append(.def) }
        return result
    }

    func capacity(for fluid: FuelFluid) -> Decimal {
        switch fluid {
        case .diesel: return dieselCapacity
        case .gas: return gasCapacity
        case .def: return defCapacity
        }
    }

    static func gallons(_ raw: String?) -> Decimal {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return 0 }
        return value
    }
}

/// System Configuration fuel prices (Price Settings), per gallon.
struct FuelPrices: Equatable {
    var diesel: Decimal?
    var gas: Decimal?
    var def: Decimal?

    init(diesel: Decimal? = nil, gas: Decimal? = nil, def: Decimal? = nil) {
        self.diesel = diesel
        self.gas = gas
        self.def = def
    }

    /// From the `configurations` "Price Settings" list: setting_name → setting_value.
    init(settings: [String: String]) {
        func price(_ fluid: FuelFluid) -> Decimal? {
            guard let text = settings[fluid.priceSettingName]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
            return value
        }
        self.init(diesel: price(.diesel), gas: price(.gas), def: price(.def))
    }

    func perGallon(_ fluid: FuelFluid) -> Decimal? {
        switch fluid {
        case .diesel: return diesel
        case .gas: return gas
        case .def: return def
        }
    }
}

/// One fluid's priced reading.
struct FuelChargeLine: Equatable {
    enum Outcome: String, Equatable {
        /// Fuel was used and is charged.
        case charged
        /// Came back at the delivered level or fuller.
        case noUsage
        /// No return level yet.
        case notReturned
        /// Prepaid fuel (product option or legacy Prepaid delivery level).
        case prepaid
        /// DEF delivery level not recorded — never assumed.
        case deliveryNotRecorded
        /// No delivery level and the delivery is not complete (nothing to compare against).
        case deliveryMissing
        /// System Configuration has no price for this fluid.
        case priceMissing
        /// Equipment Management has no tank capacity for this fluid.
        case capacityMissing
    }

    let fluid: FuelFluid
    /// The delivery level actually used (9 when the Admin Override applied).
    let deliveredLevel: Int?
    let returnedLevel: Int?
    let eighthsUsed: Int
    let capacity: Decimal
    let pricePerGallon: Decimal?
    let amount: Decimal
    let outcome: Outcome
    /// True when a missing primary delivery reading was counted as Full.
    let assumedFullAtDelivery: Bool
}

enum FuelChargeCalculator {

    /// Prices ONE fluid's reading for one machine.
    /// - Parameters:
    ///   - deliveryCompleted: the line's delivery is complete on the server (`is_delivered`).
    ///     Only then may a missing PRIMARY delivery level count as Full.
    ///   - prepaidFuel: the order line carries the "rental_prepaid_fuel" option.
    static func line(fluid: FuelFluid,
                     profile: FuelTankProfile,
                     prices: FuelPrices,
                     delivered: String?,
                     returned: String?,
                     deliveryCompleted: Bool,
                     prepaidFuel: Bool) -> FuelChargeLine {
        let capacity = profile.capacity(for: fluid)
        let price = prices.perGallon(fluid)
        var deliveredLevel = FuelLevel.value(delivered)
        let returnedLevel = FuelLevel.value(returned)
        var assumedFull = false

        func result(_ outcome: FuelChargeLine.Outcome, eighths: Int = 0, amount: Decimal = 0) -> FuelChargeLine {
            FuelChargeLine(fluid: fluid, deliveredLevel: deliveredLevel, returnedLevel: returnedLevel, eighthsUsed: eighths,
                           capacity: capacity, pricePerGallon: price, amount: amount, outcome: outcome,
                           assumedFullAtDelivery: assumedFull)
        }

        if deliveredLevel == nil {
            if fluid == .def { return result(.deliveryNotRecorded) }
            guard deliveryCompleted else { return result(.deliveryMissing) }
            deliveredLevel = FuelLevel.full
            assumedFull = true
        }
        if prepaidFuel || deliveredLevel == FuelLevel.prepaid { return result(.prepaid) }
        guard let returnedValue = returnedLevel, returnedValue != FuelLevel.prepaid else { return result(.notReturned) }
        let eighths = max(0, (deliveredLevel ?? 0) - returnedValue)
        guard eighths > 0 else { return result(.noUsage) }
        guard capacity > 0 else { return result(.capacityMissing, eighths: eighths) }
        guard let perGallon = price else { return result(.priceMissing, eighths: eighths) }
        let raw = perGallon * capacity * Decimal(eighths) / 8
        return result(.charged, eighths: eighths, amount: cents(raw))
    }

    /// Every fluid the machine is read for. `readings` maps a fluid to its (delivered, returned)
    /// levels; the primary fuel's readings are filed under the machine's primary fluid.
    static func lines(profile: FuelTankProfile,
                      prices: FuelPrices,
                      readings: [FuelFluid: (delivered: String?, returned: String?)],
                      deliveryCompleted: Bool,
                      prepaidFuel: Bool) -> [FuelChargeLine] {
        profile.fluids.map { fluid in
            let reading = readings[fluid]
            return line(fluid: fluid, profile: profile, prices: prices, delivered: reading?.delivered ?? nil,
                        returned: reading?.returned ?? nil, deliveryCompleted: deliveryCompleted, prepaidFuel: prepaidFuel)
        }
    }

    static func total(_ lines: [FuelChargeLine]) -> Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Rounded to the cent, halves away from zero (the same rounding Laravel's round() applies).
    static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    /// The wire form of an amount: always two decimals, "." separator ("208.00").
    static func amountString(_ value: Decimal) -> String {
        let rounded = cents(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: rounded as NSDecimalNumber) ?? "0.00"
    }

    static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }
}
