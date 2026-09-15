//
//  AssemblyReview.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Queue Line Assembly Review (dependent-assembly model, 2026-09-14): the yard
//  technician sees every member of a Queue Line entity together — the base
//  product and the products that physically depend on it (a Rental Bundle
//  child, a related product), every Product Option frozen on each member —
//  and CONFIRMS each requirement Available before any checklist in that
//  assembly may begin.
//
//  Grouping is Laravel's, derived from PERSISTED dependency edges on the
//  order rows; the phone never regroups and offers no unbundle. ONE durable
//  operation backs the screen, through the ONE Sync Engine:
//
//      queue_line.availability   → POST queue-line/{order_product}/availability
//
//  It carries the member's order product as its business identity, so the
//  engine's per-orderingKey FIFO keeps it ordered with that line's own
//  checklist prepare / substitution operations. Laravel owns every rule (the
//  append-only ledger, the unstage on Not Available, the assembly
//  aggregation, the STOP/GO gate inside the staging Save); this layer records
//  confirmations durably, overlays them locally until acknowledged, and
//  mirrors the rules only for display and for refusing the obviously invalid
//  Save before it is enqueued.
//
//  Affirmative model: the technician confirms Available. Until then a
//  requirement is operationally not available (STOP). A reversal is the
//  canonical Not Available underneath — kept for the ledger and the
//  lifecycle rule, never a second control. Product Options are whatever the
//  order froze: the phone shows every entry by its stored label and
//  classifies nothing by name.
//

import Foundation

// MARK: - Vocabulary

enum AssemblyStage: String, Codable, Equatable, CaseIterable {
    case pending
    case staged
    case inTransit = "in_transit"
    case equipmentDelivered = "equipment_delivered"

    /// Board order, furthest milestone last (mirrors QueueLineLifecycle::STAGES).
    var rank: Int { AssemblyStage.allCases.firstIndex(of: self) ?? 0 }

    /// The mobile board keeps three lanes; In Transit stays a badge on Staged.
    var lane: String {
        switch self {
        case .pending: return "pending"
        case .staged, .inTransit: return "staged"
        case .equipmentDelivered: return "completed"
        }
    }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .staged: return "Staged"
        case .inTransit: return "In Transit"
        case .equipmentDelivered: return "Equipment Delivered"
        }
    }

    /// Physically settled: the equipment already left the yard, so it imposes
    /// nothing on the assembly gate and cannot be re-acknowledged.
    var hasLeftTheYard: Bool { self == .inTransit || self == .equipmentDelivered }
}

enum AvailabilityState: String, Codable, Equatable {
    case available
    case notAvailable = "not_available"

    var title: String { self == .available ? "Available" : "Not Available" }
}

/// single = a line on its own; dependent = joined to other lines by persisted
/// bundle / related-product edges (never by the order id alone).
enum AssemblyKind: String, Codable, Equatable {
    case single
    case dependent
}

enum AvailabilitySubject: String, Codable, Equatable {
    case unit
    case option
}

// MARK: - Wire contract (decodes GET queue-line/orders/{order}/assembly)

struct AssemblyAcknowledgement: Codable, Equatable {
    let state: AvailabilityState?
    let acknowledgedBy: String?
    let acknowledgedAt: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case state, acknowledgedBy = "acknowledged_by", acknowledgedAt = "acknowledged_at", note
    }

    init(state: AvailabilityState?, acknowledgedBy: String? = nil, acknowledgedAt: String? = nil, note: String? = nil) {
        self.state = state; self.acknowledgedBy = acknowledgedBy; self.acknowledgedAt = acknowledgedAt; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown state string never fails the decode — it reads as unconfirmed.
        state = AvailabilityState(rawValue: (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "" )
        acknowledgedBy = try c.decodeIfPresent(String.self, forKey: .acknowledgedBy)
        acknowledgedAt = try c.decodeIfPresent(String.self, forKey: .acknowledgedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct AssemblyProductOption: Codable, Equatable {
    let uniqueId: String
    let name: String
    let included: Bool
    let availability: AssemblyAcknowledgement

    enum CodingKeys: String, CodingKey { case uniqueId = "unique_id", name, included, availability }
}

struct AssemblyUnitAvailability: Codable, Equatable {
    let equipmentUniqueId: String?
    let state: AvailabilityState?
    let acknowledgedBy: String?
    let acknowledgedAt: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case equipmentUniqueId = "equipment_unique_id"
        case state, acknowledgedBy = "acknowledged_by", acknowledgedAt = "acknowledged_at", note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        equipmentUniqueId = try c.decodeIfPresent(String.self, forKey: .equipmentUniqueId)
        state = AvailabilityState(rawValue: (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "")
        acknowledgedBy = try c.decodeIfPresent(String.self, forKey: .acknowledgedBy)
        acknowledgedAt = try c.decodeIfPresent(String.self, forKey: .acknowledgedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct AssemblyAvailability: Codable, Equatable {
    let unit: AssemblyUnitAvailability
    let requiredCount: Int
    let acknowledgedCount: Int
    let effectiveState: AvailabilityState?

    enum CodingKeys: String, CodingKey {
        case unit, requiredCount = "required_count", acknowledgedCount = "acknowledged_count", effectiveState = "effective_state"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = try c.decode(AssemblyUnitAvailability.self, forKey: .unit)
        requiredCount = try c.decodeIfPresent(Int.self, forKey: .requiredCount) ?? 0
        acknowledgedCount = try c.decodeIfPresent(Int.self, forKey: .acknowledgedCount) ?? 0
        effectiveState = AvailabilityState(rawValue: (try? c.decodeIfPresent(String.self, forKey: .effectiveState)) ?? "")
    }
}

/// One thing that holds an assembly at STOP: a member's unit (unassigned,
/// unconfirmed or Not Available) or a frozen Product Option (unconfirmed or
/// Not Available). Labels are the server's, built from the unit's own name
/// and the stored option label — never a name list on the phone.
struct AssemblyStageBlocker: Codable, Equatable {
    let code: String
    let subjectType: String
    let subjectKey: String?
    let orderProductUniqueId: String?
    let productName: String?
    let label: String

    enum CodingKeys: String, CodingKey {
        case code, subjectType = "subject_type", subjectKey = "subject_key"
        case orderProductUniqueId = "order_product_unique_id", productName = "product_name", label
    }

    init(code: String, subjectType: String, subjectKey: String?, orderProductUniqueId: String?, productName: String?, label: String) {
        self.code = code; self.subjectType = subjectType; self.subjectKey = subjectKey
        self.orderProductUniqueId = orderProductUniqueId; self.productName = productName; self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        subjectType = try c.decodeIfPresent(String.self, forKey: .subjectType) ?? ""
        subjectKey = try c.decodeIfPresent(String.self, forKey: .subjectKey)
        orderProductUniqueId = try c.decodeIfPresent(String.self, forKey: .orderProductUniqueId)
        productName = try c.decodeIfPresent(String.self, forKey: .productName)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// The dependent assembly's derived STOP / GO (never stored).
struct AssemblyGate: Codable, Equatable {
    let ready: Bool
    let requiredCount: Int
    let confirmedCount: Int
    let blockers: [AssemblyStageBlocker]

    enum CodingKeys: String, CodingKey {
        case ready, requiredCount = "required_count", confirmedCount = "confirmed_count", blockers
    }

    static let unknown = AssemblyGate(ready: false, requiredCount: 0, confirmedCount: 0, blockers: [])

    init(ready: Bool, requiredCount: Int, confirmedCount: Int, blockers: [AssemblyStageBlocker]) {
        self.ready = ready; self.requiredCount = requiredCount; self.confirmedCount = confirmedCount; self.blockers = blockers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        requiredCount = try c.decodeIfPresent(Int.self, forKey: .requiredCount) ?? 0
        confirmedCount = try c.decodeIfPresent(Int.self, forKey: .confirmedCount) ?? 0
        blockers = try c.decodeIfPresent([AssemblyStageBlocker].self, forKey: .blockers) ?? []
    }
}

/// How one member hangs on its assembly: the base product, a bundle child of
/// a present master, or a related child of a present parent.
struct AssemblyDependency: Codable, Equatable {
    let role: String
    let dependsOn: String?
    let dependsOnName: String?

    enum CodingKeys: String, CodingKey { case role, dependsOn = "depends_on", dependsOnName = "depends_on_name" }

    static let base = AssemblyDependency(role: "base", dependsOn: nil, dependsOnName: nil)

    init(role: String, dependsOn: String?, dependsOnName: String?) {
        self.role = role; self.dependsOn = dependsOn; self.dependsOnName = dependsOnName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "base"
        dependsOn = try c.decodeIfPresent(String.self, forKey: .dependsOn)
        dependsOnName = try c.decodeIfPresent(String.self, forKey: .dependsOnName)
    }

    var isBase: Bool { role == "base" }
}

struct AssemblyWarning: Codable, Equatable {
    let code: String
    let label: String
}

struct AssemblyStageCounts: Codable, Equatable {
    let pending: Int
    let staged: Int
    let inTransit: Int
    let equipmentDelivered: Int

    enum CodingKeys: String, CodingKey {
        case pending, staged, inTransit = "in_transit", equipmentDelivered = "equipment_delivered"
    }

    static let zero = AssemblyStageCounts(pending: 0, staged: 0, inTransit: 0, equipmentDelivered: 0)

    init(pending: Int, staged: Int, inTransit: Int, equipmentDelivered: Int) {
        self.pending = pending; self.staged = staged; self.inTransit = inTransit; self.equipmentDelivered = equipmentDelivered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
        staged = try c.decodeIfPresent(Int.self, forKey: .staged) ?? 0
        inTransit = try c.decodeIfPresent(Int.self, forKey: .inTransit) ?? 0
        equipmentDelivered = try c.decodeIfPresent(Int.self, forKey: .equipmentDelivered) ?? 0
    }
}

/// The `assembly` block every board item and every review member carries.
struct AssemblyInfo: Codable, Equatable {
    let key: String
    let kind: AssemblyKind
    let stage: AssemblyStage
    let lane: String
    let memberCount: Int
    let stageCounts: AssemblyStageCounts
    let dependency: AssemblyDependency
    let gate: AssemblyGate

    enum CodingKeys: String, CodingKey {
        case key, kind, stage, lane, memberCount = "member_count", stageCounts = "stage_counts", dependency, gate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        kind = AssemblyKind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .single
        stage = AssemblyStage(rawValue: (try? c.decode(String.self, forKey: .stage)) ?? "") ?? .pending
        lane = try c.decodeIfPresent(String.self, forKey: .lane) ?? stage.lane
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        stageCounts = try c.decodeIfPresent(AssemblyStageCounts.self, forKey: .stageCounts) ?? .zero
        dependency = try c.decodeIfPresent(AssemblyDependency.self, forKey: .dependency) ?? .base
        gate = try c.decodeIfPresent(AssemblyGate.self, forKey: .gate) ?? .unknown
    }
}

/// One member of an assembly — the board item plus the Assembly Review blocks.
struct AssemblyMember: Codable, Equatable {
    struct Product: Codable, Equatable {
        let uniqueId: String?
        let name: String?
        let imageUrl: String?
        enum CodingKeys: String, CodingKey { case uniqueId = "unique_id", name, imageUrl = "image_url" }
    }

    struct Equipment: Codable, Equatable {
        let uniqueId: String?
        let displayId: String?
        let name: String?
        let status: String?
        let statusLabel: String?
        enum CodingKeys: String, CodingKey { case uniqueId = "unique_id", displayId = "display_id", name, status, statusLabel = "status_label" }
    }

    struct Delivery: Codable, Equatable {
        let typeLabel: String?
        let transportMode: String?
        let date: String?
        let time: String?
        enum CodingKeys: String, CodingKey { case typeLabel = "type_label", transportMode = "transport_mode", date, time }
    }

    struct Store: Codable, Equatable {
        let uniqueId: String?
        let name: String?
        enum CodingKeys: String, CodingKey { case uniqueId = "unique_id", name }
    }

    let orderProductUniqueId: String
    let orderUniqueId: String
    let orderNumber: String
    let customerName: String?
    let identity: QueueLineItemIdentity
    let checklist: QueueLineItemContract.Checklist
    let product: Product
    let equipment: Equipment?
    let delivery: Delivery?
    let store: Store?
    let assignmentState: String?
    let status: String
    let staged: Bool
    let inTransit: Bool
    let completed: Bool
    let lifecycleStage: AssemblyStage
    let assembly: AssemblyInfo
    let productOptions: [AssemblyProductOption]
    let availability: AssemblyAvailability
    let stageBlockers: [AssemblyStageBlocker]
    let warnings: [AssemblyWarning]

    enum CodingKeys: String, CodingKey {
        case orderProductUniqueId = "order_product_unique_id", orderUniqueId = "order_unique_id"
        case orderNumber = "order_number", customerName = "customer_name"
        case identity, checklist, product, equipment, delivery, store
        case assignmentState = "assignment_state", status, staged, inTransit = "in_transit", completed
        case lifecycleStage = "lifecycle_stage", assembly, productOptions = "product_options", availability
        case stageBlockers = "stage_blockers", warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderProductUniqueId = try c.decode(String.self, forKey: .orderProductUniqueId)
        orderUniqueId = try c.decode(String.self, forKey: .orderUniqueId)
        orderNumber = try c.decodeIfPresent(String.self, forKey: .orderNumber) ?? ""
        customerName = try c.decodeIfPresent(String.self, forKey: .customerName)
        identity = try c.decode(QueueLineItemIdentity.self, forKey: .identity)
        checklist = try c.decode(QueueLineItemContract.Checklist.self, forKey: .checklist)
        product = try c.decode(Product.self, forKey: .product)
        equipment = try c.decodeIfPresent(Equipment.self, forKey: .equipment)
        delivery = try c.decodeIfPresent(Delivery.self, forKey: .delivery)
        store = try c.decodeIfPresent(Store.self, forKey: .store)
        assignmentState = try c.decodeIfPresent(String.self, forKey: .assignmentState)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        staged = try c.decodeIfPresent(Bool.self, forKey: .staged) ?? false
        inTransit = try c.decodeIfPresent(Bool.self, forKey: .inTransit) ?? false
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        lifecycleStage = AssemblyStage(rawValue: (try? c.decodeIfPresent(String.self, forKey: .lifecycleStage)) ?? "") ?? .pending
        assembly = try c.decode(AssemblyInfo.self, forKey: .assembly)
        productOptions = try c.decodeIfPresent([AssemblyProductOption].self, forKey: .productOptions) ?? []
        availability = try c.decode(AssemblyAvailability.self, forKey: .availability)
        stageBlockers = try c.decodeIfPresent([AssemblyStageBlocker].self, forKey: .stageBlockers) ?? []
        warnings = try c.decodeIfPresent([AssemblyWarning].self, forKey: .warnings) ?? []
    }
}

struct AssemblyGroup: Codable, Equatable {
    let key: String
    let kind: AssemblyKind
    let stage: AssemblyStage
    let lane: String
    let memberCount: Int
    let stageCounts: AssemblyStageCounts
    let gate: AssemblyGate
    let members: [AssemblyMember]

    enum CodingKeys: String, CodingKey {
        case key, kind, stage, lane, memberCount = "member_count", stageCounts = "stage_counts", gate, members
    }

    init(key: String, kind: AssemblyKind, stage: AssemblyStage, memberCount: Int, stageCounts: AssemblyStageCounts, gate: AssemblyGate, members: [AssemblyMember]) {
        self.key = key; self.kind = kind; self.stage = stage; self.lane = stage.lane
        self.memberCount = memberCount; self.stageCounts = stageCounts; self.gate = gate; self.members = members
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        kind = AssemblyKind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .single
        stage = AssemblyStage(rawValue: (try? c.decode(String.self, forKey: .stage)) ?? "") ?? .pending
        lane = try c.decodeIfPresent(String.self, forKey: .lane) ?? stage.lane
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        stageCounts = try c.decodeIfPresent(AssemblyStageCounts.self, forKey: .stageCounts) ?? .zero
        members = try c.decodeIfPresent([AssemblyMember].self, forKey: .members) ?? []
        gate = try c.decodeIfPresent(AssemblyGate.self, forKey: .gate) ?? members.first?.assembly.gate ?? .unknown
    }

    /// The base product (the first member: the server leads with it).
    var base: AssemblyMember? { members.first }
}

struct AssemblyReview: Codable, Equatable {
    struct OrderHeader: Codable, Equatable {
        let uniqueId: String
        let orderNumber: String
        let customerName: String?
        let paymentLabel: String?
        let financiallyActive: Bool
        enum CodingKeys: String, CodingKey {
            case uniqueId = "unique_id", orderNumber = "order_number", customerName = "customer_name"
            case paymentLabel = "payment_label", financiallyActive = "financially_active"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            uniqueId = try c.decode(String.self, forKey: .uniqueId)
            orderNumber = try c.decodeIfPresent(String.self, forKey: .orderNumber) ?? ""
            customerName = try c.decodeIfPresent(String.self, forKey: .customerName)
            paymentLabel = try c.decodeIfPresent(String.self, forKey: .paymentLabel)
            financiallyActive = try c.decodeIfPresent(Bool.self, forKey: .financiallyActive) ?? true
        }
    }

    struct Excluded: Codable, Equatable {
        let orderProductUniqueId: String
        let productName: String?
        let reason: String?
        enum CodingKeys: String, CodingKey { case orderProductUniqueId = "order_product_unique_id", productName = "product_name", reason }
    }

    let order: OrderHeader
    let assemblies: [AssemblyGroup]
    let excluded: [Excluded]
    let memberCount: Int

    enum CodingKeys: String, CodingKey { case order, assemblies, excluded, memberCount = "member_count" }

    init(order: OrderHeader, assemblies: [AssemblyGroup], excluded: [Excluded], memberCount: Int) {
        self.order = order; self.assemblies = assemblies; self.excluded = excluded; self.memberCount = memberCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode(OrderHeader.self, forKey: .order)
        assemblies = try c.decodeIfPresent([AssemblyGroup].self, forKey: .assemblies) ?? []
        excluded = try c.decodeIfPresent([Excluded].self, forKey: .excluded) ?? []
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
    }

    var members: [AssemblyMember] { assemblies.flatMap(\.members) }

    /// The assembly a member belongs to (nil when it is not on the review).
    func group(containing orderProductUniqueId: String) -> AssemblyGroup? {
        assemblies.first { $0.members.contains { $0.orderProductUniqueId == orderProductUniqueId } }
    }
}

/// The full envelope: `data` + `meta.employee` (who is acting on this phone).
struct AssemblyReviewEnvelope: Codable, Equatable {
    struct Employee: Codable, Equatable {
        let uniqueId: String
        let fullName: String?
        enum CodingKeys: String, CodingKey { case uniqueId = "unique_id", fullName = "full_name" }
    }
    struct Meta: Codable, Equatable {
        let generatedAt: String?
        let employee: Employee?
        enum CodingKeys: String, CodingKey { case generatedAt = "generated_at", employee }
    }

    let success: Bool
    let data: AssemblyReview
    let meta: Meta?

    static func decode(_ data: Data) throws -> AssemblyReviewEnvelope {
        try KabbaISO8601.makeDecoder().decode(AssemblyReviewEnvelope.self, from: data)
    }
}

// MARK: - The durable operation

/// The technician's confirmation (Available) — or its reversal (Not
/// Available) — for the assigned unit or one ordered Product Option of one
/// order line.
struct AvailabilityCapture: Equatable {
    var orderUniqueId: String
    var orderProductUniqueId: String
    /// The unit the decision is about (unit subject) — travels as identity so a
    /// reassignment before sync is visible in diagnostics.
    var equipmentUniqueId: String?
    var subject: AvailabilitySubject
    /// Equipment unique id, or the frozen Product Option item unique id.
    var subjectKey: String
    var state: AvailabilityState
    var performedByUniqueId: String
    var note: String?
    var capturedAt: Date = Date()
}

enum AssemblyOperationBuilder {

    static let availabilityType = "queue_line.availability"

    // MARK: Payload (the exact request body)

    static func availabilityPayload(_ capture: AvailabilityCapture) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_product_unique_id": .string(capture.orderProductUniqueId),
            "subject_type": .string(capture.subject.rawValue),
            "subject_key": .string(capture.subjectKey),
            "state": .string(capture.state.rawValue),
            "performed_by": .string(capture.performedByUniqueId),
        ]
        if let note = capture.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            body["note"] = .string(note)
        }
        return .object(body)
    }

    // MARK: Identity

    static func identity(_ capture: AvailabilityCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId,
                             equipmentUniqueId: capture.subject == .unit ? capture.subjectKey : capture.equipmentUniqueId)
    }

    // MARK: Enqueue

    @discardableResult
    static func enqueueAvailability(_ capture: AvailabilityCapture,
                                    into engine: SyncEngine,
                                    operationId: String = UUID().uuidString) throws -> SyncOperation {
        try engine.enqueue(type: availabilityType,
                           payload: availabilityPayload(capture),
                           identity: identity(capture),
                           capturedAt: capture.capturedAt,
                           displayTitle: "\(capture.state.title) · \(capture.subject == .unit ? "unit" : "option") \(capture.subjectKey)",
                           operationId: operationId)
    }
}

/// Request shape (the app layer wires the session check).
enum AssemblyRequestFactory {

    static func availabilityRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let product = operation.payload["order_product_unique_id"]?.stringValue, !product.isEmpty else {
            throw SyncHandlerError.invalidPayload("Availability confirmation has no order product")
        }
        guard operation.payload["subject_key"]?.stringValue?.isEmpty == false,
              operation.payload["state"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Availability confirmation has no subject or state")
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        return SyncHTTPRequest(method: "POST",
                               path: "queue-line/\(product)/availability",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }
}

// MARK: - Local overlay (a pure function of the engine snapshot)

/// What this phone durably decided that Laravel may not have acknowledged
/// yet. Overlaid on the cached/server Assembly Review and board items so the
/// technician sees a confirmation the moment it is made, and a stale feed
/// replace can never hide it. Replay order = capture order, so a later
/// decision on the same subject wins locally exactly as it will on the server.
struct AssemblyLocalOverlay: Equatable {

    struct Decision: Equatable {
        let state: AvailabilityState
        let queuedAt: Date
        let syncState: SyncState
        let operationId: String
        let attentionReason: String?
        let performedBy: String?
        let note: String?

        var isPendingSync: Bool { syncState == .pending || syncState == .syncing }
        var needsAttention: Bool { syncState == .needsAttention }
    }

    /// product → subject key ("unit" | "option:<frozen option key>") → latest decision
    var availability: [String: [String: Decision]] = [:]
    /// Products whose latest durable decisions include a Not Available that no
    /// later staging Save has answered — the local mirror of the server rule
    /// "Staged + Not Available → Pending".
    var unstagedLocally: Set<String> = []

    /// A unit decision is about ONE unit: keyed by the equipment unique id it
    /// named, so a decision for unit A never reads as a decision about unit B
    /// after a reassignment (the same episode rule as the server ledger).
    static func unitKey(_ equipmentUniqueId: String) -> String { "unit:\(equipmentUniqueId)" }
    static func optionKey(_ frozenOptionKey: String) -> String { "option:\(frozenOptionKey)" }

    func decision(product: String, subjectKey: String) -> Decision? {
        availability[product]?[subjectKey]
    }

    func unitDecision(product: String, equipmentUniqueId: String?) -> Decision? {
        guard let unit = equipmentUniqueId, !unit.isEmpty else { return nil }
        return decision(product: product, subjectKey: Self.unitKey(unit))
    }

    func optionDecision(product: String, frozenOptionKey: String) -> Decision? {
        decision(product: product, subjectKey: Self.optionKey(frozenOptionKey))
    }

    func isUnstagedLocally(_ product: String) -> Bool { unstagedLocally.contains(product) }

    /// Anything for this product still on its way to Laravel?
    func isPendingSync(_ product: String) -> Bool {
        availability[product]?.values.contains { $0.isPendingSync } ?? false
    }

    /// The first employee-facing rejection for this product, if any.
    func attentionReason(_ product: String) -> String? {
        availability[product]?.values
            .filter { $0.needsAttention }
            .sorted { $0.queuedAt > $1.queuedAt }
            .first
            .map { $0.attentionReason ?? "The availability change was not accepted by Kabba." }
    }

    /// Pending DECISIONS (two operations on the same subject collapse into its latest state).
    var pendingCount: Int {
        availability.values.reduce(0) { $0 + $1.values.filter { $0.isPendingSync }.count }
    }

    static func from(_ operations: [SyncOperation]) -> AssemblyLocalOverlay {
        var overlay = AssemblyLocalOverlay()
        // product → the moment of its latest durable staging Save
        var lastStagingSave: [String: Date] = [:]
        // product → the moment of its latest durable Not Available
        var lastNotAvailable: [String: Date] = [:]

        for op in operations.sorted(by: { $0.queuedAt < $1.queuedAt }) {
            guard let product = op.identity.orderProductUniqueId,
                  EffectiveFieldState.countsAsDurableEvidence(op.state) else { continue }

            switch op.type {
            case AssemblyOperationBuilder.availabilityType:
                guard let subjectType = op.payload["subject_type"]?.stringValue,
                      let key = op.payload["subject_key"]?.stringValue,
                      let state = op.payload["state"]?.stringValue.flatMap(AvailabilityState.init(rawValue:)) else { continue }
                let subjectKey = subjectType == AvailabilitySubject.unit.rawValue ? unitKey(key) : optionKey(key)
                overlay.availability[product, default: [:]][subjectKey] = Decision(
                    state: state, queuedAt: op.queuedAt, syncState: op.state, operationId: op.id,
                    attentionReason: op.attentionReason,
                    performedBy: op.payload["performed_by"]?.stringValue,
                    note: op.payload["note"]?.stringValue)
                if state == .notAvailable { lastNotAvailable[product] = op.queuedAt }

            case EffectiveFieldState.deliveryPrepareType:
                if op.payload["mark_staged"]?.boolValue == true { lastStagingSave[product] = op.queuedAt }

            default:
                break
            }
        }

        for (product, notAvailableAt) in lastNotAvailable {
            if let saveAt = lastStagingSave[product], saveAt > notAvailableAt { continue }
            overlay.unstagedLocally.insert(product)
        }

        return overlay
    }
}

// MARK: - Policy (pure mirrors of the server rules, for display and pre-checks)

enum AssemblyPolicy {

    /// The review's heading for an order number, with exactly one hash whatever the stored
    /// value carries: production numbers are stored as "#4287", test and older rows as "4287".
    /// Presentation only — the stored number is never touched.
    static func orderHeading(_ orderNumber: String) -> String {
        var digits = Substring(orderNumber.trimmingCharacters(in: .whitespacesAndNewlines))
        while digits.first == "#" { digits = digits.dropFirst() }
        return "Order #\(digits.trimmingCharacters(in: .whitespaces))"
    }

    /// The assembly's stage is its least-advanced member (QueueLineAssembly::stageFor).
    static func stage(forMemberStages stages: [AssemblyStage]) -> AssemblyStage {
        stages.min(by: { $0.rank < $1.rank }) ?? .pending
    }

    static func stageCounts(_ stages: [AssemblyStage]) -> AssemblyStageCounts {
        AssemblyStageCounts(pending: stages.filter { $0 == .pending }.count,
                            staged: stages.filter { $0 == .staged }.count,
                            inTransit: stages.filter { $0 == .inTransit }.count,
                            equipmentDelivered: stages.filter { $0 == .equipmentDelivered }.count)
    }

    /// A member's effective stage after the local overlays: a durable staging
    /// Save promotes to Staged, a signed completion to Delivered, an On My Way
    /// to In Transit, and a Not Available with no later Save demotes a Staged
    /// member back to Pending (the server rule, mirrored). Delivered and In
    /// Transit are never demoted — the equipment already left.
    static func memberStage(serverStage: AssemblyStage,
                            product: String,
                            queue: QueueLineLocalOverlay,
                            assembly: AssemblyLocalOverlay) -> AssemblyStage {
        if serverStage == .equipmentDelivered || queue.isCompletedLocally(product) { return .equipmentDelivered }
        if serverStage == .inTransit || queue.isInTransitLocally(product) { return .inTransit }
        if assembly.isUnstagedLocally(product) { return .pending }
        if serverStage == .staged || queue.isStagedLocally(product) { return .staged }
        return .pending
    }

    /// The parent line's effective availability (QueueLineAvailabilityService::effective).
    static func effectiveState(unit: AvailabilityState?, options: [AvailabilityState?]) -> AvailabilityState? {
        let states = [unit] + options
        if states.contains(.notAvailable) { return .notAvailable }
        if states.allSatisfy({ $0 == .available }) { return .available }
        return nil
    }

    /// The unit a member is on RIGHT NOW as this phone knows it: a switch this
    /// phone recorded through the canonical reassignment (pending, syncing or
    /// synced — never a rejected one) wins over the cached feed's unit until the
    /// feed catches up; otherwise the server's assignment.
    struct EffectiveEquipment: Equatable {
        let uniqueId: String
        let name: String?
        let displayId: String?
        /// True while the switch that named this unit has not been acknowledged.
        let pendingSync: Bool
        /// True when the unit comes from this phone's switch, not the feed.
        let fromLocalSwitch: Bool

        /// "Name · #TAG" — the yard's way of naming a machine.
        var identityLine: String {
            let line = EquipmentIdentity.line(name: name, displayId: displayId)
            return line.isEmpty ? uniqueId : line
        }
    }

    static func effectiveEquipment(member: AssemblyMember, queue: QueueLineLocalOverlay) -> EffectiveEquipment? {
        let serverUnit = member.equipment?.uniqueId
        if let local = queue.pendingEquipment(for: member.orderProductUniqueId), local.uniqueId != serverUnit {
            return EffectiveEquipment(uniqueId: local.uniqueId, name: local.name, displayId: local.displayId,
                                      pendingSync: local.isPendingSync, fromLocalSwitch: true)
        }
        guard let unit = serverUnit, !unit.isEmpty else { return nil }
        return EffectiveEquipment(uniqueId: unit, name: member.equipment?.name, displayId: member.equipment?.displayId,
                                  pendingSync: false, fromLocalSwitch: false)
    }

    /// Effective unit / option states once this phone's durable decisions are layered on.
    /// The unit state is the EFFECTIVE unit's: the server's acknowledgement counts only
    /// while it names that same unit (its episode), and a local decision only when it
    /// was made about that unit — a replacement machine always starts unconfirmed.
    static func unitState(member: AssemblyMember, queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> AvailabilityState? {
        guard let unit = effectiveEquipment(member: member, queue: queue) else { return nil }
        if let local = overlay.unitDecision(product: member.orderProductUniqueId, equipmentUniqueId: unit.uniqueId) {
            return local.state
        }
        guard !unit.fromLocalSwitch,
              member.availability.unit.equipmentUniqueId == nil || member.availability.unit.equipmentUniqueId == unit.uniqueId else {
            return nil
        }
        return member.availability.unit.state
    }

    static func optionState(member: AssemblyMember, option: AssemblyProductOption, overlay: AssemblyLocalOverlay) -> AvailabilityState? {
        overlay.optionDecision(product: member.orderProductUniqueId, frozenOptionKey: option.uniqueId)?.state
            ?? option.availability.state
    }

    static func effectiveState(member: AssemblyMember, queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> AvailabilityState? {
        effectiveState(unit: unitState(member: member, queue: queue, overlay: overlay),
                       options: member.productOptions.map { optionState(member: member, option: $0, overlay: overlay) })
    }

    // MARK: STOP / GO

    /// The assembly gate as this phone sees it: the server's rule
    /// (QueueLineAvailabilityService::gateFor) recomputed over the members
    /// with this phone's durable confirmations layered on. Derived on every
    /// render, never stored.
    struct LocalGate: Equatable {
        let ready: Bool
        let requiredCount: Int
        let confirmedCount: Int
        /// Full sentences, the same wording the server uses.
        let blockers: [String]

        var title: String { ready ? "GO" : "STOP" }
        var detail: String {
            if ready {
                if requiredCount == 0 { return "Nothing left to confirm" }   // every member has left the yard
                return requiredCount == 1 ? "Confirmed" : "All \(requiredCount) confirmed"
            }
            return "\(confirmedCount) of \(requiredCount) confirmed"
        }
    }

    static func gate(for group: AssemblyGroup, queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> LocalGate {
        var blockers: [String] = []
        var required = 0
        var confirmed = 0

        for member in group.members {
            let stage = memberStage(serverStage: member.lifecycleStage, product: member.orderProductUniqueId, queue: queue, assembly: overlay)
            if stage.hasLeftTheYard { continue }
            let name = member.product.name ?? "This item"
            required += 1
            if let unit = effectiveEquipment(member: member, queue: queue) {
                let unitName = unit.name ?? "The assigned machine"
                switch unitState(member: member, queue: queue, overlay: overlay) {
                case .available: confirmed += 1
                case .notAvailable: blockers.append("\(unitName) is acknowledged Not Available.")
                case nil: blockers.append("\(unitName) has not been confirmed Available.")
                }
            } else {
                blockers.append("\(name) needs a machine assigned.")
            }
            for option in member.productOptions {
                required += 1
                switch optionState(member: member, option: option, overlay: overlay) {
                case .available: confirmed += 1
                case .notAvailable: blockers.append("\(option.name) is acknowledged Not Available.")
                case nil: blockers.append("\(option.name) has not been confirmed Available.")
                }
            }
        }

        return LocalGate(ready: blockers.isEmpty, requiredCount: required, confirmedCount: confirmed, blockers: blockers)
    }

    /// The gate of the assembly a member belongs to (nil when the review does not hold it).
    static func gate(forMember orderProductUniqueId: String, in review: AssemblyReview,
                     queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> LocalGate? {
        review.group(containing: orderProductUniqueId).map { gate(for: $0, queue: queue, overlay: overlay) }
    }

    /// The Save-time message, from the server's blocker labels
    /// (context.server_state.stage_blockers) merged with this phone's own
    /// derived gate. Every label is a sentence about ONE subject.
    static func stagingRefusalMessage(productName: String, blockerLabels: [String]) -> String? {
        guard !blockerLabels.isEmpty else { return nil }
        let reasons = blockerLabels.map { label -> String in
            var reason = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.hasSuffix(".") { reason.removeLast() }
            return reason
        }
        return "Cannot stage \(productName) because \(reasons.joined(separator: " and "))."
    }

    /// The review's groups with this phone's durable evidence layered on:
    /// each member's overlaid stage, the assembly's recomputed stage and
    /// counts. Membership is the server's — the phone never regroups.
    static func groups(_ review: AssemblyReview, queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> [AssemblyGroup] {
        review.assemblies.map { group in
            let stages = group.members.map {
                memberStage(serverStage: $0.lifecycleStage, product: $0.orderProductUniqueId, queue: queue, assembly: overlay)
            }
            return AssemblyGroup(key: group.key, kind: group.kind, stage: stage(forMemberStages: stages),
                                 memberCount: group.memberCount, stageCounts: stageCounts(stages),
                                 gate: group.gate, members: group.members)
        }
    }

    /// Wording for the assembly header line.
    static func progressLine(stageCounts: AssemblyStageCounts, memberCount: Int) -> String {
        let beyondPending = memberCount - stageCounts.pending
        if memberCount <= 1 { return "" }
        return "\(beyondPending) of \(memberCount) items staged"
    }
}
