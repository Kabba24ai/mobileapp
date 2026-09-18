//
//  AssemblyReviewViewController.swift
//  RentnKing
//
//  Entry point → Assembly Review → the existing Delivery Checklist (2026-09-14).
//
//  EVERY road into the outbound equipment checklist passes here first — the
//  Queue Line card, the Orders list, Order Details and everything that reaches
//  it (ChecklistEntry is the one helper that opens this screen and builds the
//  focused checklist it continues to). A single-line order with no options
//  takes the same road: one predictable workflow.
//
//  ONE Queue Line entity on one screen — the base product and the products
//  that physically depend on it (a Rental Bundle child, a related product),
//  every Product Option frozen on each member (shown by its stored label,
//  never renamed, never filtered by name) — and, per requirement, the
//  technician's affirmative confirmation: a red X and a hollow Available until
//  confirmed, a green check and a filled Available after. The assembly's
//  derived STOP / GO decides whether any member's checklist may open: the
//  Continue button stays hollow and inactive at STOP and fills at GO.
//
//  Nothing here stages, nothing here regroups: the ONLY road to Staged stays
//  the checklist's explicit Save, and grouping is the server's, from persisted
//  dependency edges. Local-first like the board: the cached review + this
//  phone's durable confirmations render immediately; the server read replaces
//  the cache; the engine's queue events re-render. A confirmation (or its
//  reversal) is a durable Sync Engine operation (AssemblySyncHandlers) — never
//  a second offline queue.
//

import UIKit

final class AssemblyReviewViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - Inputs
    var orderUniqueId = ""
    var orderNumber = ""
    /// The member the technician tapped Update on — scrolled into view.
    var focusOrderProductUniqueId: String?
    /// The entity the tapped card represents; when set, only that assembly is
    /// shown (the order's other, independent lines have their own cards).
    var focusAssemblyKey: String?
    /// Where the technician came from (ChecklistEntry) — handed on to the
    /// checklist so its downstream behaviour matches that entry point; Back
    /// from this screen always returns there.
    var origin: ChecklistEntry.Origin = .queueLine

    // MARK: - Palette (app dark theme, same values as the board)
    private enum Palette {
        static let page   = UIColor.background
        static let card   = UIColor(hex: 0x141C26)
        static let border = UIColor(hex: 0x2A3542)
        static let ink    = UIColor.primary
        static let subtle = UIColor(hex: 0x9AA4B2)
        static let cyan   = UIColor.secondary
        static let amber  = UIColor.secondaryText
        static let green  = UIColor(hex: 0x1FA155)
        static let red    = UIColor.redText
        static let unconfirmed = UIColor(hex: 0x6B7A8C)
    }

    // MARK: - State
    private(set) var review: AssemblyReview?
    private(set) var employeeUniqueId: String?
    private var queueOverlay = QueueLineLocalOverlay()
    private var assemblyOverlay = AssemblyLocalOverlay()
    private var lastRefreshFailed = false
    private var isOpeningChecklist = false
    private var syncObserver: NSObjectProtocol?
    private var didScrollToFocus = false
    /// The same equipment picker / confirmation / reason flow the Delivery Checklist uses.
    private lazy var equipmentFlow = EquipmentAssignmentFlow(host: self)
    private var isChangingEquipment = false

    // MARK: - Views
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let freshnessLabel = UILabel()
    private let refreshControl = UIRefreshControl()
    private var memberCards: [String: UIView] = [:]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "assemblyReview"
        setupScaffold()

        syncObserver = NotificationCenter.default.addObserver(forName: .kabbaSyncQueueChanged, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }
    }

    deinit {
        if let observer = syncObserver { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isOpeningChecklist = false
        AppUtility.PortraitMode()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigationBarFor(controller: self, title: "Assembly Review", isTransperent: true,
                            hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: false,
                            leftActionHandler: { [weak self] in
                                self?.navigationController?.popViewController(animated: true)
                            })

        // Back from the checklist (or first arrival): cache + local decisions NOW …
        if let cached = KabbaAssemblySync.cached(orderUniqueId: orderUniqueId) {
            apply(cached)
        } else {
            render()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // … then the server's answer replaces the cache (checklist status,
        // lifecycle, availability, assignment, options, the gate).
        fetch()
    }

    // MARK: - Data

    /// Applies a decoded envelope (cache or server) and re-renders.
    func apply(_ envelope: AssemblyReviewEnvelope) {
        review = envelope.data
        if let employee = envelope.meta?.employee?.uniqueId, !employee.isEmpty {
            employeeUniqueId = employee
        }
        render()
    }

    private func fetch() {
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "queueLineAssembly"
        webHelper.methodType = "get"
        webHelper.strURL = Url.queueLineAssembly(orderUniqueId).absoluteString ?? ""
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = false
        webHelper.indicatorShowOrHide = false

        webHelper.callAPIwithCompletation { [weak self] data, _, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshControl.endRefreshing()
                guard error == nil, let data = data, data.getStringForID(key: "success") == "1",
                      let raw = try? JSONSerialization.data(withJSONObject: data, options: []),
                      let envelope = try? AssemblyReviewEnvelope.decode(raw) else {
                    self.lastRefreshFailed = true
                    self.render()
                    return
                }
                self.lastRefreshFailed = false
                KabbaAssemblySync.cache(raw, orderUniqueId: self.orderUniqueId)
                self.apply(envelope)
            }
        }
    }

    @objc private func pullToRefresh() { fetch() }

    // MARK: - Render

    /// The groups this screen shows: the focused entity when the card named
    /// one (and the review still holds it), otherwise every entity of the order.
    func visibleGroups() -> [AssemblyGroup] {
        guard let review = review else { return [] }
        let groups = AssemblyPolicy.groups(review, queue: queueOverlay, overlay: assemblyOverlay)
        if let focus = focusAssemblyKey, let match = groups.first(where: { $0.key == focus }) { return [match] }
        if let focus = focusOrderProductUniqueId, let match = groups.first(where: { $0.members.contains { $0.orderProductUniqueId == focus } }) { return [match] }
        return groups
    }

    private func render() {
        queueOverlay = KabbaQueueLineSync.overlay()
        assemblyOverlay = KabbaAssemblySync.overlay()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        memberCards.removeAll()
        renderHeader()

        guard let review = review else {
            contentStack.addArrangedSubview(makeNote(lastRefreshFailed
                ? "Offline · no saved Assembly Review for this order yet. Reconnect and pull to refresh."
                : "Loading the assembly…", color: lastRefreshFailed ? Palette.amber : Palette.subtle))
            return
        }

        let groups = visibleGroups()
        if groups.isEmpty {
            contentStack.addArrangedSubview(makeNote(review.order.financiallyActive
                ? "No Queue Line items on this order."
                : "This order is no longer active on the Queue Line.", color: Palette.subtle))
        }
        for group in groups {
            let gate = AssemblyPolicy.gate(for: group, queue: queueOverlay, overlay: assemblyOverlay)
            contentStack.addArrangedSubview(makeGroupHeader(group, gate: gate))
            for member in group.members {
                let card = makeMemberCard(member, in: group, gate: gate)
                memberCards[member.orderProductUniqueId] = card
                contentStack.addArrangedSubview(card)
            }
        }
        for excluded in review.excluded where groups.count != 1 || groups[0].kind == .dependent {
            let reason = excluded.reason == "removed_forever" ? "removed from the Queue Line" : "removed for today"
            contentStack.addArrangedSubview(makeNote("\(excluded.productName ?? "An item") — \(reason); not part of this assembly.", color: Palette.subtle))
        }

        updateFreshnessLine()
        scrollToFocusOnce()
    }

    /// The header is the order identity only — instructions the technician
    /// would learn to ignore are not repeated on every open.
    private func renderHeader() {
        headerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let number = UILabel()
        number.attributedText = attr(AssemblyPolicy.orderHeading(review?.order.orderNumber ?? orderNumber), Palette.cyan, rFont(GlobalMainConstants.APP_FONT_Roboto_Bold, 18))
        number.accessibilityIdentifier = "assemblyReview.order"
        headerStack.addArrangedSubview(number)
        headerStack.addArrangedSubview(freshnessLabel)
    }

    /// Exceptional conditions only: offline, or confirmations still on their way.
    private func updateFreshnessLine() {
        let pending = assemblyOverlay.pendingCount
        var parts: [String] = []
        if lastRefreshFailed { parts.append("Offline · showing the saved assembly") }
        if pending > 0 { parts.append("\(pending) change\(pending == 1 ? "" : "s") pending sync") }
        freshnessLabel.text = parts.joined(separator: " · ")
        freshnessLabel.textColor = lastRefreshFailed ? Palette.amber : Palette.subtle
        freshnessLabel.accessibilityIdentifier = "assemblyReview.freshness"
        freshnessLabel.isHidden = parts.isEmpty
    }

    private func scrollToFocusOnce() {
        guard !didScrollToFocus, let focus = focusOrderProductUniqueId, let card = memberCards[focus] else { return }
        didScrollToFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.view.layoutIfNeeded()
            let target = card.convert(card.bounds, to: self.scrollView)
            self.scrollView.scrollRectToVisible(target.insetBy(dx: 0, dy: -12), animated: false)
        }
    }

    // MARK: - Group header (identity + derived STOP / GO)

    private func makeGroupHeader(_ group: AssemblyGroup, gate: AssemblyPolicy.LocalGate) -> UIView {
        let bold = GlobalMainConstants.APP_FONT_Roboto_Bold
        let title = UILabel()
        title.attributedText = attr(group.kind == .dependent ? "Assembly · \(group.memberCount) items" : "Item", Palette.ink, rFont(bold, 15))
        title.accessibilityIdentifier = "assemblyReview.group.\(group.key)"

        let chip = stageChip(group.stage)
        chip.accessibilityIdentifier = "assemblyReview.group.\(group.key).stage"

        let progress = UILabel()
        progress.attributedText = attr(AssemblyPolicy.progressLine(stageCounts: group.stageCounts, memberCount: group.memberCount), Palette.subtle, rFont(GlobalMainConstants.APP_FONT_Roboto_Medium, 12))
        progress.accessibilityIdentifier = "assemblyReview.group.\(group.key).progress"

        let top = UIStackView(arrangedSubviews: [title, UIView(), progress, chip])
        top.axis = .horizontal; top.spacing = 10; top.alignment = .center

        // The one derived readiness signal: icon + word + count, never colour alone.
        let readiness = makeGateBadge(gate)
        readiness.accessibilityIdentifier = "assemblyReview.group.\(group.key).gate"
        readiness.accessibilityLabel = "\(gate.title) · \(gate.detail)"
        let bottom = UIStackView(arrangedSubviews: [readiness, UIView()])
        bottom.axis = .horizontal; bottom.alignment = .center

        let column = UIStackView(arrangedSubviews: [top, bottom])
        column.axis = .vertical; column.spacing = 8
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 4, left: 2, bottom: 0, right: 2)
        return column
    }

    private func makeGateBadge(_ gate: AssemblyPolicy.LocalGate) -> UIView {
        let tone = gate.ready ? Palette.green : Palette.red
        let icon = UIImageView(image: UIImage(systemName: gate.ready ? "checkmark.circle.fill" : "hand.raised.fill"))
        icon.tintColor = tone
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let word = UILabel()
        word.attributedText = attr(gate.title, tone, .systemFont(ofSize: 14, weight: .heavy))
        let detail = UILabel()
        detail.attributedText = attr(gate.detail, Palette.subtle, .systemFont(ofSize: 12, weight: .medium))

        let row = UIStackView(arrangedSubviews: [icon, word, detail])
        row.axis = .horizontal; row.spacing = 6; row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 12)
        row.layer.cornerRadius = 8
        row.layer.borderWidth = 1
        row.layer.borderColor = tone.withAlphaComponent(0.7).cgColor
        row.backgroundColor = tone.withAlphaComponent(0.12)
        row.isAccessibilityElement = true
        return row
    }

    // MARK: - Member card

    private func makeMemberCard(_ member: AssemblyMember, in group: AssemblyGroup, gate: AssemblyPolicy.LocalGate) -> UIView {
        let bold = GlobalMainConstants.APP_FONT_Roboto_Bold
        let medium = GlobalMainConstants.APP_FONT_Roboto_Medium
        let regular = GlobalMainConstants.APP_FONT_Roboto_Regular
        let product = member.orderProductUniqueId
        let stage = AssemblyPolicy.memberStage(serverStage: member.lifecycleStage, product: product, queue: queueOverlay, assembly: assemblyOverlay)
        let left = stage.hasLeftTheYard

        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = (product == focusOrderProductUniqueId ? Palette.cyan.withAlphaComponent(0.7) : Palette.border).cgColor
        card.accessibilityIdentifier = "assembly.\(product)"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        // 1) Product + lifecycle
        let name = UILabel()
        name.numberOfLines = 0
        name.attributedText = attr(member.product.name ?? "", Palette.ink, rFont(bold, 18))
        name.accessibilityIdentifier = "assembly.\(product).product"
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var titleViews: [UIView] = [name, UIView()]
        if assemblyOverlay.isPendingSync(product) {
            titleViews.append(makeBadge("Pending Sync", bg: .clear, text: Palette.amber, bordered: true))
        } else if assemblyOverlay.attentionReason(product) != nil {
            titleViews.append(makeBadge("Sync Issue", bg: .clear, text: Palette.red, bordered: true))
        }
        let stageBadge = stageChip(stage)
        stageBadge.accessibilityIdentifier = "assembly.\(product).stage"
        titleViews.append(stageBadge)
        let title = UIStackView(arrangedSubviews: titleViews)
        title.axis = .horizontal; title.spacing = 8; title.alignment = .center
        stack.addArrangedSubview(title)

        // Dependent member: which base product it goes with (identity, not instruction).
        if !member.assembly.dependency.isBase, let base = member.assembly.dependency.dependsOnName, !base.isEmpty {
            let with = UILabel()
            with.numberOfLines = 0
            with.attributedText = attr("Goes with \(base)", Palette.subtle, rFont(medium, 12))
            with.accessibilityIdentifier = "assembly.\(product).dependency"
            stack.addArrangedSubview(with)
        }

        // 2) Exceptional warnings only (the unit itself is the first availability row)
        let chips: [UIView] = member.warnings.filter { $0.code != "needs_equipment" }
            .map { makeBadge($0.label, bg: .clear, text: Palette.red, bordered: true) }
        if !chips.isEmpty { stack.addArrangedSubview(wrapChips(chips)) }

        if let reason = assemblyOverlay.attentionReason(product) ?? queueOverlay.attentionReason(product) {
            stack.addArrangedSubview(makeNote(reason, color: Palette.red))
        }

        // 3) Availability — the machine as the yard names it ("Name · #TAG", tappable to
        //    change the assignment; "Assign" when there is none), then EVERY frozen option
        stack.addArrangedSubview(makeDivider())
        let sectionTitle = UILabel()
        sectionTitle.attributedText = attr("AVAILABILITY", Palette.subtle, rFont(medium, 11))
        stack.addArrangedSubview(sectionTitle)

        let unit = AssemblyPolicy.effectiveEquipment(member: member, queue: queueOverlay)
        let unitState = AssemblyPolicy.unitState(member: member, queue: queueOverlay, overlay: assemblyOverlay)
        if let unit = unit {
            stack.addArrangedSubview(makeAvailabilityRow(
                title: unit.identityLine,
                subtitle: confirmedText(unit: member, effective: unit, overlay: assemblyOverlay),
                state: unitState,
                enabled: !left,
                idPrefix: "assembly.\(product).unit",
                identityAction: left ? nil : { [weak self] in self?.changeEquipment(for: member) },
                onToggle: { [weak self] in self?.toggleUnit(member, unit: unit, current: unitState) }))
        } else {
            stack.addArrangedSubview(makeAssignRow(idPrefix: "assembly.\(product).unit", enabled: !left,
                                                   onAssign: { [weak self] in self?.changeEquipment(for: member) }))
        }

        let optionsTitle = UILabel()
        optionsTitle.attributedText = attr("Product Options", Palette.ink, rFont(medium, 13))
        stack.addArrangedSubview(optionsTitle)
        if member.productOptions.isEmpty {
            let none = UILabel()
            none.attributedText = attr("No Product Options on this line", Palette.subtle, rFont(regular, 13))
            none.accessibilityIdentifier = "assembly.\(product).options.none"
            stack.addArrangedSubview(none)
        }
        for option in member.productOptions {
            let state = AssemblyPolicy.optionState(member: member, option: option, overlay: assemblyOverlay)
            stack.addArrangedSubview(makeAvailabilityRow(
                title: option.name,                       // the stored order label, verbatim
                subtitle: confirmedText(option: option, member: member, overlay: assemblyOverlay),
                state: state,
                enabled: !left,
                idPrefix: "assembly.\(product).option.\(option.uniqueId)",
                onToggle: { [weak self] in self?.toggleOption(member, option: option, current: state) }))
        }

        // 4) The checklist action — hollow and inactive at STOP, filled at GO.
        //    Still offered once the truck has left (In Transit): the driver
        //    completes this same Delivery Checklist at the customer — Order
        //    Details → here → checklist → signature. Only delivered equipment
        //    has nothing left to continue to.
        if stage != .equipmentDelivered {
            stack.addArrangedSubview(makeDivider())
            let cont = makeButton("Continue to Checklist", fill: gate.ready ? Palette.cyan : .clear,
                                  ink: gate.ready ? Palette.page : Palette.unconfirmed, bordered: !gate.ready)
            cont.accessibilityIdentifier = "assembly.\(product).continue"
            cont.accessibilityValue = gate.ready ? "enabled" : "blocked"
            cont.isEnabled = gate.ready
            cont.addAction(UIAction { [weak self] _ in self?.continueToChecklist(member) }, for: .touchUpInside)
            stack.addArrangedSubview(cont)
        }

        return card
    }

    // MARK: - Availability row (X + hollow Available → check + filled Available)

    /// One requirement: title, a state line, and the ONE affirmative control.
    /// Unconfirmed = red X + hollow "Available"; confirmed = green check +
    /// filled "Available"; a Not Available reversal keeps the X. Tapping a
    /// confirmed row asks before reversing it.
    private func makeAvailabilityRow(title: String, subtitle: String?, state: AvailabilityState?, enabled: Bool,
                                     idPrefix: String, identityAction: (() -> Void)? = nil, onToggle: @escaping () -> Void) -> UIView {
        let medium = GlobalMainConstants.APP_FONT_Roboto_Medium
        let regular = GlobalMainConstants.APP_FONT_Roboto_Regular

        let name = UILabel()
        name.numberOfLines = 0
        name.attributedText = attr(title, identityAction == nil ? Palette.ink : Palette.cyan, rFont(medium, 14))
        name.accessibilityIdentifier = "\(idPrefix).title"

        let stateLine = UILabel()
        stateLine.numberOfLines = 0
        stateLine.attributedText = attr(subtitle ?? "", Palette.subtle, rFont(regular, 12))
        stateLine.accessibilityIdentifier = "\(idPrefix).state"

        var titleViews: [UIView] = [name]
        if identityAction != nil {
            // Tappable identity: the yard changes the assignment right here (the same
            // canonical flow as the checklist) — a chevron says so without a second button.
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = Palette.cyan
            chevron.contentMode = .scaleAspectFit
            chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
            chevron.heightAnchor.constraint(equalToConstant: 14).isActive = true
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            titleViews.append(chevron)
            titleViews.append(UIView())
        }
        let titleRow = UIStackView(arrangedSubviews: titleViews)
        titleRow.axis = .horizontal; titleRow.spacing = 4; titleRow.alignment = .center

        let text = UIStackView(arrangedSubviews: [titleRow, stateLine])
        text.axis = .vertical; text.spacing = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let action = identityAction {
            let tap = UIButton(type: .custom)
            tap.translatesAutoresizingMaskIntoConstraints = false
            tap.accessibilityIdentifier = "\(idPrefix).reassign"
            tap.accessibilityLabel = "Change equipment"
            tap.accessibilityValue = title
            tap.addAction(UIAction { _ in action() }, for: .touchUpInside)
            text.addSubview(tap)
            NSLayoutConstraint.activate([
                tap.topAnchor.constraint(equalTo: text.topAnchor), tap.bottomAnchor.constraint(equalTo: text.bottomAnchor),
                tap.leadingAnchor.constraint(equalTo: text.leadingAnchor), tap.trailingAnchor.constraint(equalTo: text.trailingAnchor),
            ])
        }

        let confirmed = state == .available
        let icon = UIImageView(image: UIImage(systemName: confirmed ? "checkmark.circle.fill" : "xmark.circle.fill"))
        icon.tintColor = confirmed ? Palette.green : Palette.red
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        icon.isAccessibilityElement = true
        icon.accessibilityIdentifier = "\(idPrefix).icon"
        icon.accessibilityLabel = confirmed ? "Confirmed" : "Not confirmed"
        icon.alpha = enabled ? 1 : 0.45

        let button = confirmButton(confirmed: confirmed, enabled: enabled)
        button.accessibilityIdentifier = "\(idPrefix).available"
        button.addAction(UIAction { _ in onToggle() }, for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [icon, button])
        controls.axis = .horizontal; controls.spacing = 8; controls.alignment = .center
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [text, controls])
        row.axis = .horizontal; row.spacing = 10; row.alignment = .center
        row.accessibilityIdentifier = "\(idPrefix).row"
        return row
    }

    /// No machine yet: the requirement is unmet (red X) and the ONE action is to
    /// assign one — through the same canonical flow the checklist uses. No
    /// Available control exists for a machine that does not exist.
    private func makeAssignRow(idPrefix: String, enabled: Bool, onAssign: @escaping () -> Void) -> UIView {
        let medium = GlobalMainConstants.APP_FONT_Roboto_Medium
        let regular = GlobalMainConstants.APP_FONT_Roboto_Regular

        let name = UILabel()
        name.numberOfLines = 0
        name.attributedText = attr("No equipment selected", Palette.ink, rFont(medium, 14))
        name.accessibilityIdentifier = "\(idPrefix).title"
        let stateLine = UILabel()
        stateLine.numberOfLines = 0
        stateLine.attributedText = attr("Assign a machine first", Palette.subtle, rFont(regular, 12))
        stateLine.accessibilityIdentifier = "\(idPrefix).state"
        let text = UIStackView(arrangedSubviews: [name, stateLine])
        text.axis = .vertical; text.spacing = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let icon = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
        icon.tintColor = Palette.red
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        icon.isAccessibilityElement = true
        icon.accessibilityIdentifier = "\(idPrefix).icon"
        icon.accessibilityLabel = "Not confirmed"

        let assign = UIButton(type: .custom)
        assign.setTitle("Assign", for: .normal)
        assign.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        assign.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            assign.widthAnchor.constraint(equalToConstant: Self.confirmButtonSize.width),
            assign.heightAnchor.constraint(equalToConstant: Self.confirmButtonSize.height),
        ])
        assign.layer.cornerRadius = 8
        assign.backgroundColor = Palette.cyan
        assign.setTitleColor(Palette.page, for: .normal)
        assign.setTitleColor(Palette.page.withAlphaComponent(0.7), for: .highlighted)
        assign.isEnabled = enabled
        assign.alpha = enabled ? 1 : 0.45
        assign.accessibilityIdentifier = "\(idPrefix).assign"
        assign.addAction(UIAction { _ in onAssign() }, for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [icon, assign])
        controls.axis = .horizontal; controls.spacing = 8; controls.alignment = .center
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [text, controls])
        row.axis = .horizontal; row.spacing = 10; row.alignment = .center
        row.accessibilityIdentifier = "\(idPrefix).row"
        return row
    }

    /// Every Available control is exactly this size, whatever the row's text
    /// leaves beside it — the control never grows or shrinks between rows.
    static let confirmButtonSize = CGSize(width: 87, height: 29)

    /// A plain (non-system) button: the look is exactly the fill and border
    /// set here — no system selected/highlight tint on top of it. Fixed size.
    private func confirmButton(confirmed: Bool, enabled: Bool) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle("Available", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: Self.confirmButtonSize.width),
            b.heightAnchor.constraint(equalToConstant: Self.confirmButtonSize.height),
        ])
        b.layer.cornerRadius = 8
        b.layer.borderWidth = 1.5
        b.layer.borderColor = (confirmed ? Palette.green : Palette.unconfirmed).cgColor
        b.backgroundColor = confirmed ? Palette.green : .clear
        let ink: UIColor = confirmed ? .white : Palette.unconfirmed
        b.setTitleColor(ink, for: .normal)
        b.setTitleColor(ink, for: .selected)
        b.setTitleColor(ink.withAlphaComponent(0.7), for: .highlighted)
        b.setTitleColor(ink, for: .disabled)
        b.isEnabled = enabled
        b.alpha = enabled ? 1 : 0.45
        b.isSelected = confirmed
        b.accessibilityValue = confirmed ? "confirmed" : "not confirmed"
        return b
    }

    private func stageChip(_ stage: AssemblyStage) -> UIView {
        switch stage {
        case .pending: return makeBadge("Pending", bg: .clear, text: Palette.amber, bordered: true)
        case .staged: return makeBadge("Staged", bg: Palette.green, text: .white, bordered: false)
        case .inTransit: return makeBadge("In Transit", bg: Palette.cyan, text: .white, bordered: false)
        case .equipmentDelivered: return makeBadge("Equipment Delivered", bg: Palette.subtle, text: .white, bordered: false)
        }
    }

    /// The unit row's state line — always about the EFFECTIVE unit: a decision this
    /// phone made about it, else the server's acknowledgement for its episode, else
    /// "not yet confirmed" (a machine assigned on this phone starts unconfirmed).
    private func confirmedText(unit member: AssemblyMember, effective: AssemblyPolicy.EffectiveEquipment, overlay: AssemblyLocalOverlay) -> String {
        if let local = overlay.unitDecision(product: member.orderProductUniqueId, equipmentUniqueId: effective.uniqueId) {
            return local.isPendingSync ? "\(local.state.title) · pending sync" : "\(local.state.title) · confirmed on this phone"
        }
        if effective.fromLocalSwitch {
            return effective.pendingSync ? "Assigned on this phone · pending sync · not yet confirmed" : "Assigned on this phone · not yet confirmed"
        }
        guard member.availability.unit.equipmentUniqueId == nil || member.availability.unit.equipmentUniqueId == effective.uniqueId,
              let state = member.availability.unit.state else { return "Not yet confirmed" }
        let who = member.availability.unit.acknowledgedBy.map { " by \($0)" } ?? ""
        return state.title + who
    }

    private func confirmedText(option: AssemblyProductOption, member: AssemblyMember, overlay: AssemblyLocalOverlay) -> String {
        if let local = overlay.optionDecision(product: member.orderProductUniqueId, frozenOptionKey: option.uniqueId) {
            return local.isPendingSync ? "\(local.state.title) · pending sync" : "\(local.state.title) · confirmed on this phone"
        }
        guard let state = option.availability.state else {
            return option.included ? "Not yet confirmed · included with the order" : "Not yet confirmed"
        }
        let who = option.availability.acknowledgedBy.map { " by \($0)" } ?? ""
        let note = option.availability.note.map { " · \($0)" } ?? ""
        return state.title + who + note
    }

    // MARK: - Actions

    private func performedBy() -> String? {
        if let id = employeeUniqueId, !id.isEmpty { return id }
        showAlertMessage(strMessage: "Your employee record has not loaded yet — pull to refresh, then try again.")
        return nil
    }

    /// Unconfirmed / Not Available → confirm Available. Confirmed → ask, then
    /// reverse to Not Available (the canonical reversal underneath).
    private func toggleUnit(_ member: AssemblyMember, unit: AssemblyPolicy.EffectiveEquipment, current: AvailabilityState?) {
        let label = unit.name ?? "the assigned machine"
        toggle(current: current, label: label) { [weak self] state in
            guard let self = self, let performer = self.performedBy() else { return }
            self.recordAvailability(AvailabilityCapture(orderUniqueId: member.orderUniqueId, orderProductUniqueId: member.orderProductUniqueId,
                                                        equipmentUniqueId: unit.uniqueId, subject: .unit, subjectKey: unit.uniqueId, state: state,
                                                        performedByUniqueId: performer))
        }
    }

    // MARK: - Assign / change the machine (the checklist's own canonical flow)

    /// Assign (no unit) and change (tap on the identity) are ONE capability: the
    /// canonical candidates for this line, the shared picker, the shared confirmation
    /// and reason rules, and the canonical `queue_line.switch_equipment` operation —
    /// Laravel's EquipmentReassignmentService for a first assignment and a
    /// reassignment alike. Assignment is never availability: the new machine starts
    /// unconfirmed and the assembly stays STOP until it is confirmed here.
    private func changeEquipment(for member: AssemblyMember) {
        guard !isChangingEquipment else { return }
        let stage = AssemblyPolicy.memberStage(serverStage: member.lifecycleStage, product: member.orderProductUniqueId,
                                               queue: queueOverlay, assembly: assemblyOverlay)
        if stage.hasLeftTheYard {
            showAlertMessage(strMessage: (stage == .equipmentDelivered ? PreparationLifecycle.Block.delivered : PreparationLifecycle.Block.inTransit).message)
            return
        }
        isChangingEquipment = true
        indicatorShow()
        // The picker opens in the canonical Product Category of the current unit (else of the
        // ordered product): Laravel resolves it (`category=default`) and lists that category
        // whole, in operational order. The picker's Category pill and search ask the same
        // endpoint again — Laravel still decides what is eligible and how it is classified.
        loadCandidates(for: member, category: "default") { [weak self] page in
            guard let self = self else { return }
            indicatorHide()
            self.isChangingEquipment = false
            guard let page = page else {
                showAlertMessage(strMessage: "Could not load the equipment list. Check the connection and try again.")
                return
            }
            // Nothing in the whole fleet → nothing to open. An empty CATEGORY still opens the
            // picker: the employee changes the category or searches from there.
            guard !page.candidates.isEmpty || page.category != nil else {
                showAlertMessage(strMessage: "No equipment is available to assign right now.")
                return
            }
            let current = AssemblyPolicy.effectiveEquipment(member: member, queue: self.queueOverlay)
            self.equipmentFlow.onDismiss = nil
            let source = EquipmentAssignmentFlow.CandidateSource(
                fetch: { [weak self] category, term, deliver in
                    guard let self = self else { deliver(nil); return }
                    self.loadCandidates(for: member, search: term, category: category?.uniqueId ?? "all") { deliver($0?.candidates) }
                },
                categories: { [weak self] deliver in
                    guard let self = self else { deliver(nil); return }
                    self.loadCategories(deliver)
                })
            self.equipmentFlow.pick(from: page.candidates, preselectUniqueId: nil, category: page.category, source: source) { [weak self] candidate in
                self?.applyAssignment(member, replacement: candidate, current: current, stage: stage)
            }
        }
    }

    /// One answer of the candidates read: Laravel's list and the category it is scoped to (nil = the whole fleet).
    private struct CandidatePage {
        let candidates: [EquipmentCandidate]
        let category: EquipmentCategoryOption?
    }

    /// GET queue-line/{line}/equipment-candidates[?search=][&category=] — Laravel's list, Laravel's
    /// classification, Laravel's category resolution (`meta.category`).
    private func loadCandidates(for member: AssemblyMember, search: String? = nil, category: String? = nil,
                                completion: @escaping (CandidatePage?) -> Void) {
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "queueLineEquipmentCandidates"
        webHelper.methodType = "get"
        webHelper.strURL = Url.queueLineEquipmentCandidates(member.orderProductUniqueId, search: search, category: category).absoluteString ?? ""
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = false
        webHelper.indicatorShowOrHide = false
        webHelper.callAPIwithCompletation { data, _, _, error in
            DispatchQueue.main.async {
                guard error == nil, let data = data, data.getStringForID(key: "success") == "1",
                      let payload = data["data"] as? [String: Any],
                      let rows = payload["candidates"] as? [[String: Any]] else {
                    completion(nil)
                    return
                }
                let meta = data["meta"] as? [String: Any]
                completion(CandidatePage(candidates: rows.compactMap { EquipmentCandidate(candidateJSON: $0) },
                                         category: EquipmentCategoryOption(metaJSON: meta?["category"] as? [String: Any])))
            }
        }
    }

    /// The canonical Product Category list for the picker's Category pill — the same cached
    /// `product-categories` read the checklist's "Select Category ID" uses (CategoryListFile),
    /// delivered once; nil when neither the cache nor the network has it.
    private func loadCategories(_ deliver: @escaping ([EquipmentCategoryOption]?) -> Void) {
        let cachedFirst = !getCatData().isEmpty
        var calls = 0
        var delivered = false
        getCategoryList { list in
            calls += 1
            guard !delivered else { return }
            let options = list.compactMap { category -> EquipmentCategoryOption? in
                guard let uid = category.unique_id, !uid.isEmpty else { return nil }
                // The cached list prefixes child categories with "--" for the checklist's wheel.
                let title = (category.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "- ")).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : EquipmentCategoryOption(uniqueId: uid, title: title)
            }
            if !options.isEmpty {
                delivered = true
                DispatchQueue.main.async { deliver(options) }
            } else if !cachedFirst || calls >= 2 {
                delivered = true                      // the network read failed and there is no cache
                DispatchQueue.main.async { deliver(nil) }
            }
        }
    }

    private func applyAssignment(_ member: AssemblyMember, replacement: EquipmentCandidate,
                                 current: AssemblyPolicy.EffectiveEquipment?, stage: AssemblyStage) {
        guard let performer = performedBy() else { return }
        // A staged line, or one whose checklist is already prepared, loses that
        // preparation when its machine changes — say so first (the checklist's rule).
        let prepared = stage == .staged || member.checklist.delivery.preparedAt != nil
        let target = EquipmentAssignmentFlow.Target(
            orderUniqueId: member.orderUniqueId,
            orderProductUniqueId: member.orderProductUniqueId,
            supersededExecutionId: member.checklist.delivery.checklistExecutionId ?? member.identity.checklistExecutionId ?? "",
            currentEquipmentUniqueId: current?.uniqueId,
            currentEquipmentCode: current?.displayId,
            block: nil,
            confirmation: prepared ? .discardPrepared : .none,
            performedByUniqueId: performer)
        equipmentFlow.apply(target, replacement: replacement) { [weak self] _, _, operationId in
            guard let self = self else { return }
            // The operation is durable: the replacement shows NOW (overlay), unconfirmed,
            // and the gate recomputes — STOP until the yard confirms the new machine.
            self.render()
            KabbaSync.showStatusToast(for: operationId)
        }
    }

    private func toggleOption(_ member: AssemblyMember, option: AssemblyProductOption, current: AvailabilityState?) {
        toggle(current: current, label: option.name) { [weak self] state in
            guard let self = self, let performer = self.performedBy() else { return }
            self.recordAvailability(AvailabilityCapture(orderUniqueId: member.orderUniqueId, orderProductUniqueId: member.orderProductUniqueId,
                                                        equipmentUniqueId: member.equipment?.uniqueId, subject: .option, subjectKey: option.uniqueId,
                                                        state: state, performedByUniqueId: performer))
        }
    }

    private func toggle(current: AvailabilityState?, label: String, record: @escaping (AvailabilityState) -> Void) {
        guard current == .available else {
            record(.available)
            return
        }
        let alert = UIAlertController(title: "Mark \(label) Not Available?",
                                      message: "It stays part of the order. If this item is Staged it returns to Pending until everything is confirmed again.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Not Available", style: .destructive) { _ in record(.notAvailable) })
        present(alert, animated: true)
    }

    private func recordAvailability(_ capture: AvailabilityCapture) {
        guard let operationId = KabbaAssemblySync.acknowledge(capture) else {
            showAlertMessage(strMessage: "Could not save that on this phone. Please try again.")
            return
        }
        render()                                   // the confirmation shows NOW, from the durable record
        KabbaSync.showStatusToast(for: operationId) // Saved · Pending Sync → Synced / Needs Attention
    }

    /// The SAME Delivery Checklist every entry point opened before Assembly
    /// Review existed, with the same identity payload, entered for ONE member:
    /// only that member may receive staging intent from the Save. Built by the
    /// one canonical helper for every origin. One push at a time.
    private func continueToChecklist(_ member: AssemblyMember) {
        guard !isOpeningChecklist, let nav = navigationController else { return }
        isOpeningChecklist = true
        let unit = AssemblyPolicy.effectiveEquipment(member: member, queue: queueOverlay)?.uniqueId
        guard let vc = ChecklistEntry.makeChecklist(for: member, origin: origin, equipmentUniqueId: unit) else {
            isOpeningChecklist = false
            return
        }
        nav.pushViewController(vc, animated: true)
    }

    // MARK: - Scaffold + small builders

    private func setupScaffold() {
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let outer = UIStackView(arrangedSubviews: [headerStack, contentStack])
        outer.axis = .vertical
        outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.refreshControl = refreshControl
        refreshControl.tintColor = Palette.cyan
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        view.addSubview(scrollView)
        scrollView.addSubview(outer)

        freshnessLabel.font = .systemFont(ofSize: 12, weight: .medium)
        freshnessLabel.textColor = Palette.subtle
        freshnessLabel.numberOfLines = 1
        freshnessLabel.isHidden = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            outer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            outer.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -14),
            outer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    private func rFont(_ name: String, _ size: Double) -> UIFont { SetTheFont(fontName: name, size: size) }

    private func attr(_ text: String, _ color: UIColor, _ font: UIFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font])
    }

    private func labelValue(_ label: String, _ value: String) -> NSAttributedString {
        let f = rFont(GlobalMainConstants.APP_FONT_Roboto_Medium, 13)
        let s = NSMutableAttributedString(string: label, attributes: [.foregroundColor: Palette.cyan, .font: f])
        s.append(NSAttributedString(string: value, attributes: [.foregroundColor: Palette.ink, .font: f]))
        return s
    }

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = Palette.border
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func makeNote(_ text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attr(text, color, rFont(GlobalMainConstants.APP_FONT_Roboto_Medium, 13))
        return label
    }

    private func wrapChips(_ chips: [UIView]) -> UIView {
        let row = UIStackView(arrangedSubviews: chips + [UIView()])
        row.axis = .horizontal; row.spacing = 6; row.alignment = .center
        return row
    }

    private func makeBadge(_ text: String, bg: UIColor, text textColor: UIColor, bordered: Bool) -> UIView {
        let label = AssemblyPaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = textColor
        label.backgroundColor = bg
        label.insets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.numberOfLines = 1
        if bordered {
            label.layer.borderWidth = 1
            label.layer.borderColor = textColor.withAlphaComponent(0.6).cgColor
        }
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func makeButton(_ title: String, fill: UIColor, ink: UIColor, bordered: Bool) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        b.setTitleColor(ink, for: .normal)
        b.setTitleColor(ink, for: .disabled)
        b.setTitleColor(ink.withAlphaComponent(0.7), for: .highlighted)
        b.backgroundColor = fill
        b.layer.cornerRadius = 8
        b.layer.borderWidth = bordered ? 1.5 : 0
        b.layer.borderColor = ink.cgColor
        b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return b
    }
}

/// Label with configurable content insets (chips / badges).
final class AssemblyPaddedLabel: UILabel {
    var insets = UIEdgeInsets.zero
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1)
    }
}
