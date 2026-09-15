//
//  EquipmentAssignmentFlow.swift
//  RentnKing
//
//  The ONE equipment selector (2026-09-14): the picker the Delivery Checklist has
//  always used to assign / substitute a unit — status-grouped wheel, "Select
//  Equipment ID" header with Cancel / Select pills, the status triage on Select,
//  the "Change equipment and start over?" confirmation, Laravel's reason picklist
//  for a non-direct unit — lifted out of the checklist so Assembly Review invokes
//  exactly the same capability instead of a second one.
//
//  Nothing here is an assignment record. The only write is the canonical
//  `queue_line.switch_equipment` operation (PreparationOperationBuilder), the
//  same durable operation and endpoint the checklist and the web board use, which
//  Laravel resolves through EquipmentReassignmentService — for a first assignment
//  and for a reassignment alike. Every reader then sees the same assignment.
//

import UIKit

final class EquipmentAssignmentFlow: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {

    /// What the canonical change needs to know about the line being changed.
    struct Target {
        var orderUniqueId: String
        var orderProductUniqueId: String
        /// The live preparation cycle (superseded by the switch); "" when none is known.
        var supersededExecutionId: String
        var currentEquipmentUniqueId: String?
        var currentEquipmentCode: String?
        /// Physical refusal (In Transit / delivered) — nil when the unit may change.
        var block: PreparationLifecycle.Block?
        /// What a switch would discard for this line.
        var confirmation: PreparationLifecycle.Confirmation
        /// The employee physically staging (resolved by the host — the checklist's
        /// employee row before the login account); nil refuses the change.
        var performedByUniqueId: String?
    }

    private weak var host: UIViewController?
    private let hiddenField = UITextField(frame: .zero)
    private let picker = UIPickerView()
    private var rows: [String] = []
    private var candidates: [EquipmentCandidate] = []
    private var selectedIndex = 1
    private var onPicked: ((EquipmentCandidate) -> Void)?
    /// Called on every dismissal (Cancel, Select, refusal) — the host restores scroll state.
    var onDismiss: (() -> Void)?

    /// Server-backed candidate search (2026-09-15): `(term, deliver)` → the host asks
    /// Laravel for the matches across the WHOLE eligible fleet (`?search=`) and delivers
    /// them (nil = the request failed). Present only for hosts whose candidates come from
    /// the canonical candidates read; the checklist's category-scoped fleet list is already
    /// complete and passes none, so its picker is unchanged.
    typealias CandidateSearch = (String, @escaping ([EquipmentCandidate]?) -> Void) -> Void
    private var searchProvider: CandidateSearch?
    /// The prioritized first page (direct matches first) the picker opened with.
    private var baseCandidates: [EquipmentCandidate] = []
    private(set) var currentSearchTerm = ""
    private var titleButton: UIButton?
    /// The wheel's rows right now (section headers included) — for tests.
    var currentRows: [String] { rows }
    var searchIsOffered: Bool { searchProvider != nil }
    var searchPillTitle: String? { titleButton?.title(for: .normal) }
    var searchPillIsInteractive: Bool { titleButton?.isUserInteractionEnabled ?? false }

    static let title = "Select Equipment ID"
    static let searchTitle = "Search name or Equipment ID"
    private static let sectionPrefix = "Section: "

    init(host: UIViewController) {
        self.host = host
        super.init()
        picker.dataSource = self
        picker.delegate = self
        picker.backgroundColor = .white
    }

    // MARK: - Picker host (installed lazily into the host's view)

    private var installed = false

    private func installIfNeeded() {
        guard !installed, let view = host?.view else { return }
        installed = true
        hiddenField.translatesAutoresizingMaskIntoConstraints = false
        hiddenField.isHidden = true
        // This field only hosts the picker (inputView). It must NOT trigger
        // IQKeyboardManager's keyboard-avoidance, otherwise the view slides up.
        hiddenField.iq.enableMode = .disabled
        view.addSubview(hiddenField)

        let pickerHeight: CGFloat = 260
        let headerHeight: CGFloat = 56
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight + pickerHeight))
        hostView.backgroundColor = .black
        hostView.isOpaque = true

        let header = buildHeader(width: view.bounds.width)
        header.frame.origin = .zero
        picker.frame = CGRect(x: 0, y: headerHeight, width: hostView.bounds.width, height: pickerHeight)
        picker.autoresizingMask = [.flexibleWidth]
        picker.roundCornersView(onTopLeft: true, topRight: true, bottomLeft: false, bottomRight: false, radius: 15)
        hostView.addSubview(header)
        hostView.addSubview(picker)
        hiddenField.inputAccessoryView = nil
        hiddenField.inputView = hostView
    }

    private func buildHeader(width: CGFloat) -> UIView {
        let h: CGFloat = 56
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: h))
        header.backgroundColor = .clear
        header.autoresizingMask = [.flexibleWidth]
        let pillH: CGFloat = 38
        let y = (h - pillH) / 2

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancel.backgroundColor = UIColor(white: 0.16, alpha: 1.0)
        cancel.layer.cornerRadius = pillH / 2
        cancel.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        cancel.frame = CGRect(x: 14, y: y, width: 88, height: pillH)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let select = UIButton(type: .system)
        select.setTitle("Select", for: .normal)
        select.setTitleColor(.white, for: .normal)
        select.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        select.backgroundColor = UIColor.systemBlue
        select.layer.cornerRadius = pillH / 2
        select.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        select.frame = CGRect(x: header.bounds.width - 14 - 92, y: y, width: 92, height: pillH)
        select.autoresizingMask = [.flexibleLeftMargin]
        select.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let titleBtn = UIButton(type: .system)
        titleBtn.setTitle(Self.title, for: .normal)
        titleBtn.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
        titleBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleBtn.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        titleBtn.layer.cornerRadius = pillH / 2
        titleBtn.isUserInteractionEnabled = false            // becomes the Search pill only when a provider is supplied
        titleBtn.titleLabel?.adjustsFontSizeToFitWidth = true
        titleBtn.titleLabel?.minimumScaleFactor = 0.75
        titleBtn.accessibilityIdentifier = "equipmentPicker.search"
        titleBtn.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        titleButton = titleBtn
        let leftMaxX = cancel.frame.maxX + 12
        let rightMinX = select.frame.minX - 12
        titleBtn.frame = CGRect(x: leftMaxX, y: y, width: max(0, rightMinX - leftMaxX), height: pillH)
        titleBtn.autoresizingMask = [.flexibleWidth]

        header.addSubview(cancel)
        header.addSubview(titleBtn)
        header.addSubview(select)
        return header
    }

    // MARK: - Step 1 · pick a unit

    /// Shows the status-grouped wheel over `candidates`, preselecting `preselectUniqueId`
    /// when it is in the list. `onPicked` fires only for a unit that passed the status
    /// triage (Available; damaged / maintenance after the employee agreed).
    func pick(from candidates: [EquipmentCandidate], preselectUniqueId: String? = nil,
              search: CandidateSearch? = nil,
              onPicked: @escaping (EquipmentCandidate) -> Void) {
        guard let host = host else { return }
        installIfNeeded()
        self.candidates = candidates
        self.baseCandidates = candidates
        self.searchProvider = search
        self.currentSearchTerm = ""
        self.onPicked = onPicked
        updateSearchPill()
        rows = Self.rows(for: candidates)
        guard !rows.isEmpty else {
            showAlertMessage(strMessage: "No equipment found for the selected category.")
            return
        }
        picker.reloadAllComponents()
        let firstUnit = rows.firstIndex(where: { !$0.hasPrefix(Self.sectionPrefix) }) ?? 0
        if let pre = preselectUniqueId, let unit = candidates.first(where: { $0.uniqueId == pre }),
           let row = rows.firstIndex(of: unit.pickerRow) {
            selectedIndex = row
        } else {
            selectedIndex = firstUnit
        }
        selectedIndex = min(max(selectedIndex, 0), rows.count - 1)
        picker.selectRow(selectedIndex, inComponent: 0, animated: false)
        _ = host
        hiddenField.becomeFirstResponder()
    }

    /// Status sections (sorted), each followed by its units' rows — the checklist's layout.
    static func rows(for candidates: [EquipmentCandidate]) -> [String] {
        var rows: [String] = []
        let groups = Dictionary(grouping: candidates, by: { $0.statusLabel })
        for (section, items) in groups.sorted(by: { $0.key < $1.key }) {
            rows.append(sectionPrefix + section)
            rows.append(contentsOf: items.map { $0.pickerRow })
        }
        return rows
    }

    // MARK: - Step 1b · search the whole eligible fleet (candidate discovery, not assignment)

    /// The header pill: the plain title for a host without search; for a host with search,
    /// the Search affordance showing the active term.
    private func updateSearchPill() {
        guard let pill = titleButton else { return }
        guard searchProvider != nil else {
            pill.isUserInteractionEnabled = false
            pill.setTitle(Self.title, for: .normal)
            pill.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
            pill.accessibilityLabel = Self.title
            return
        }
        pill.isUserInteractionEnabled = true
        pill.setTitle(currentSearchTerm.isEmpty ? "🔍 \(Self.searchTitle)" : "🔍 “\(currentSearchTerm)” · Show all", for: .normal)
        pill.setTitleColor(.white, for: .normal)
        pill.accessibilityLabel = currentSearchTerm.isEmpty ? Self.searchTitle : "Search: \(currentSearchTerm)"
        pill.accessibilityValue = currentSearchTerm
    }

    /// Search pill → the term alert. The wheel steps aside while the alert's field has the
    /// keyboard and comes back with the server's matches (or the first page again).
    @objc private func searchTapped() {
        guard searchProvider != nil, let host = host else { return }
        hiddenField.resignFirstResponder()   // not a cancel: onDismiss is not called
        let alert = UIAlertController(title: Self.searchTitle,
                                      message: "Any eligible machine in the fleet can be found by its name or Equipment ID.",
                                      preferredStyle: .alert)
        alert.addTextField { [term = currentSearchTerm] field in
            field.placeholder = "Name or Equipment ID"
            field.text = term
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .search
            field.accessibilityIdentifier = "equipmentPicker.searchField"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.reopenWheel()
        })
        if !currentSearchTerm.isEmpty {
            alert.addAction(UIAlertAction(title: "Show all", style: .default) { [weak self] _ in
                self?.clearSearch()
            })
        }
        alert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self, weak alert] _ in
            let term = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let self = self else { return }
            if term.isEmpty { self.clearSearch() } else { self.performSearch(term) }
        })
        host.present(alert, animated: true)
    }

    /// Asks the provider for `term` across the whole eligible fleet and reloads the wheel
    /// with Laravel's matches, in Laravel's order (exact ID, direct matches, then name).
    /// Nothing about eligibility is decided here. Callable directly (tests, return key).
    func performSearch(_ term: String, completion: (() -> Void)? = nil) {
        guard let provider = searchProvider else { completion?(); return }
        indicatorShow()
        provider(term) { [weak self] results in
            DispatchQueue.main.async {
                indicatorHide()
                guard let self = self else { return }
                guard let results = results else {
                    showAlertMessage(strMessage: "Could not search the equipment list. Check the connection and try again.")
                    self.reopenWheel(); completion?(); return
                }
                guard !results.isEmpty else {
                    let alert = UIAlertController(title: Application.appName,
                                                  message: "No eligible equipment matches “\(term)”. Try part of the name or the Equipment ID.",
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: str.ok, style: .default) { [weak self] _ in self?.reopenWheel() })
                    self.host?.present(alert, animated: true)
                    completion?(); return
                }
                self.currentSearchTerm = term
                self.reload(with: results)
                completion?()
            }
        }
    }

    /// Back to the prioritized first page the picker opened with.
    func clearSearch() {
        currentSearchTerm = ""
        reload(with: baseCandidates)
    }

    private func reload(with list: [EquipmentCandidate]) {
        candidates = list
        rows = Self.rows(for: list)
        updateSearchPill()
        picker.reloadAllComponents()
        selectedIndex = rows.firstIndex(where: { !$0.hasPrefix(Self.sectionPrefix) }) ?? 0
        if !rows.isEmpty { picker.selectRow(selectedIndex, inComponent: 0, animated: false) }
        reopenWheel()
    }

    private func reopenWheel() {
        guard host?.view.window != nil else { return }
        hiddenField.becomeFirstResponder()
    }

    @objc private func cancelTapped() {
        hiddenField.resignFirstResponder()
        onDismiss?()
    }

    @objc private func doneTapped() {
        selectedIndex = picker.selectedRow(inComponent: 0)
        hiddenField.resignFirstResponder()
        onDismiss?()
        guard rows.indices.contains(selectedIndex) else { return }
        let input = rows[selectedIndex]
        if input.hasPrefix(Self.sectionPrefix) { return }
        guard let code = EquipmentIdentity.displayId(fromPickerRow: input),
              let candidate = candidates.first(where: { $0.displayId == code }) else { return }

        switch EquipmentPickTriage.forStatus(candidate.statusLabel) {
        case .proceed:
            onPicked?(candidate)
        case .askAboutStatus(let label):
            let alert = UIAlertController(title: Application.appName, message: EquipmentPickTriage.statusQuestion(label), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: str.yes, style: .default) { [weak self] _ in self?.onPicked?(candidate) })
            alert.addAction(UIAlertAction(title: str.no, style: .default))
            host?.present(alert, animated: true)
        case .refuseRented:
            let alert = UIAlertController(title: Application.appName, message: EquipmentPickTriage.rentedRefusal, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: str.ok, style: .default) { [weak self] _ in self?.selectedIndex = 1 })
            host?.present(alert, animated: true)
        case .drop:
            break
        }
    }

    // MARK: - Step 2 · apply the canonical change

    /// The canonical reassignment for `target` → `replacement`: physical block, the
    /// "start over" confirmation when a preparation would be discarded, Laravel's
    /// reason when the unit is not a direct match, then the durable
    /// `queue_line.switch_equipment` operation. `onApplied(replacement, reason, operationId)`
    /// runs once the operation is durably on this phone — the host performs its own local aftermath.
    func apply(_ target: Target, replacement: EquipmentCandidate, onApplied: @escaping (EquipmentCandidate, String?, String) -> Void) {
        if let current = target.currentEquipmentUniqueId, current == replacement.uniqueId { return }   // no-op, never an operation
        if let block = target.block {
            showAlertMessage(strMessage: block.message)
            return
        }
        guard target.confirmation != .none else {
            collectReasonThenEnqueue(target, replacement: replacement, onApplied: onApplied)
            return
        }
        let alert = UIAlertController(
            title: PreparationPolicy.substitutionTitle(),
            message: PreparationPolicy.substitutionMessage(currentCode: target.currentEquipmentCode ?? "",
                                                           replacementCode: replacement.displayId,
                                                           confirmation: target.confirmation),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Change Equipment & Start Over", style: .destructive) { [weak self] _ in
            self?.collectReasonThenEnqueue(target, replacement: replacement, onApplied: onApplied)
        })
        host?.present(alert, animated: true)
    }

    /// Laravel requires a reason for any replacement that is not a DIRECT match for the
    /// ordered product (the web board asks the same): the canonical picklist plus "Other",
    /// shown only when the server would refuse without it; cancelling cancels the change.
    private func collectReasonThenEnqueue(_ target: Target, replacement: EquipmentCandidate,
                                          onApplied: @escaping (EquipmentCandidate, String?, String) -> Void) {
        guard replacement.requiresReason else {
            enqueue(target, replacement: replacement, reason: nil, onApplied: onApplied)
            return
        }
        let sheet = UIAlertController(title: PreparationPolicy.switchReasonTitle(),
                                      message: PreparationPolicy.switchReasonMessage(replacementCode: replacement.displayId),
                                      preferredStyle: .actionSheet)
        for reason in PreparationPolicy.standardSwitchReasons {
            sheet.addAction(UIAlertAction(title: reason, style: .default) { [weak self] _ in
                self?.enqueue(target, replacement: replacement, reason: reason, onApplied: onApplied)
            })
        }
        sheet.addAction(UIAlertAction(title: "Other…", style: .default) { [weak self] _ in
            self?.collectOtherReason { reason in
                self?.enqueue(target, replacement: replacement, reason: reason, onApplied: onApplied)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController, let view = host?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        host?.present(sheet, animated: true)
    }

    /// "Other…" — a short free-text reason; empty text cancels the change.
    private func collectOtherReason(_ completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: PreparationPolicy.switchReasonTitle(), message: "Enter a short reason.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Reason"
            field.autocapitalizationType = .sentences
            field.accessibilityIdentifier = "switchReason.other"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                showAlertMessage(strMessage: "A reason is required for this equipment change. The unit was not changed.")
            } else {
                completion(text)
            }
        })
        host?.present(alert, animated: true)
    }

    private func enqueue(_ target: Target, replacement: EquipmentCandidate, reason: String?,
                         onApplied: @escaping (EquipmentCandidate, String?, String) -> Void) {
        guard let engine = KabbaSync.engine else {
            showAlertMessage(strMessage: "That change could not be saved on this phone. Try again.")
            return
        }
        guard let performedBy = target.performedByUniqueId, !performedBy.isEmpty else {
            showAlertMessage(strMessage: "We could not confirm who is making this change. Sign in again, then switch the unit.")
            return
        }
        let capture = EquipmentSubstitutionCapture(
            orderUniqueId: target.orderUniqueId,
            orderProductUniqueId: target.orderProductUniqueId,
            supersededExecutionId: target.supersededExecutionId,
            previousEquipmentUniqueId: target.currentEquipmentUniqueId,
            replacementEquipmentUniqueId: replacement.uniqueId,
            performedByUniqueId: performedBy,
            reason: reason,
            replacementName: replacement.name,
            replacementDisplayId: replacement.displayId)
        let operation: SyncOperation?
        do {
            operation = try PreparationOperationBuilder.enqueueSubstitution(capture, into: engine)
        } catch {
            showAlertMessage(strMessage: "That change could not be saved on this phone. Try again.")
            return
        }
        guard let op = operation else { return }   // same unit → nothing recorded, nothing to apply
        onApplied(replacement, reason, op.id)
    }

    // MARK: - UIPickerViewDataSource / Delegate (the checklist's wheel, verbatim)

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { rows.count }

    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        guard rows.indices.contains(row) else { return nil }
        let text = rows[row]
        if text.hasPrefix(Self.sectionPrefix) {
            return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Light, size: 8),
                .foregroundColor: UIColor.gray.withAlphaComponent(0.5),
            ])
        }
        return NSAttributedString(string: text, attributes: [
            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14),
            .foregroundColor: UIColor.background,
        ])
    }

    /// Section rows are not selectable — settle on the nearest unit row.
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard rows.indices.contains(row), rows[row].hasPrefix(Self.sectionPrefix) else { return }
        var next = row + 1
        while rows.indices.contains(next), rows[next].hasPrefix(Self.sectionPrefix) { next += 1 }
        if rows.indices.contains(next) {
            pickerView.selectRow(next, inComponent: component, animated: true)
            return
        }
        var previous = row - 1
        while rows.indices.contains(previous), rows[previous].hasPrefix(Self.sectionPrefix) { previous -= 1 }
        if rows.indices.contains(previous) { pickerView.selectRow(previous, inComponent: component, animated: true) }
    }
}

// MARK: - Bridges from the two data sources to the one candidate type

extension EquipmentCandidate {
    /// The checklist's fleet list: Laravel's reason rule mirrored on the unit's assigned product.
    init(machine: MachineModel, orderedProductId: Int?) {
        self.init(uniqueId: machine.unique_id ?? "",
                  displayId: machine.equipment_id ?? "",
                  name: machine.equipment_name ?? "",
                  statusLabel: machine.status ?? "",
                  requiresReason: PreparationPolicy.switchReasonRequired(replacementAssignedProductId: machine.assigned_product_id,
                                                                         orderedProductId: orderedProductId))
    }

    /// The canonical candidates read (`queue-line/{line}/equipment-candidates`): Laravel's own
    /// classification travels with the unit.
    init?(candidateJSON dict: [String: Any]) {
        guard let uid = dict["unique_id"] as? String, !uid.isEmpty else { return nil }
        self.init(uniqueId: uid,
                  displayId: dict["display_id"] as? String ?? "",
                  name: dict["name"] as? String ?? "",
                  statusLabel: (dict["status_label"] as? String) ?? (dict["status"] as? String) ?? "",
                  requiresReason: (dict["requires_reason"] as? Bool) ?? ((dict["match"] as? String) != "direct"))
    }
}
