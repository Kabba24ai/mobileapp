//
//  QueueLineStagePopup.swift
//  RentnKing
//
//  Popups opened from a Queue Line card's thumbs-up (DESIGN ONLY):
//   • QueueLineStageViewController      — "Mark as Staged" form (pending items)
//   • QueueLineStagedInfoViewController — "Staged" details    (staged items)
//

import UIKit

// MARK: - Shared palette / helpers

private enum PopupPalette {
    static let page    = UIColor.background
    static let card    = UIColor(hex: 0x162232)                      // raised slate surface — stands out from the page
    static let box     = UIColor.white.withAlphaComponent(0.05)      // faint elevated fill
    static let border  = UIColor.secondary.withAlphaComponent(0.35)  // cyan-tinted outline
    static let ink     = UIColor.primary
    static let subtle  = UIColor(hex: 0xC7CED8)
    static let cyan    = UIColor.secondary
    static let amber   = UIColor.secondaryText
    static let green   = UIColor(hex: 0x1FA155)
    static let red     = UIColor(hex: 0xE05A5A)
}

private func pFont(_ name: String, _ size: Double) -> UIFont { SetTheFont(fontName: name, size: size) }
private func pBold(_ s: Double) -> UIFont { pFont(GlobalMainConstants.APP_FONT_Roboto_Bold, s) }
private func pMed(_ s: Double) -> UIFont { pFont(GlobalMainConstants.APP_FONT_Roboto_Medium, s) }

// MARK: - Base modal (dimmed background + centered card)

class QueueLinePopupBase: UIViewController {

    let cardView = UIView()
    let contentStack = UIStackView()
    private let scrollView = UIScrollView()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)

        // Tap outside to dismiss
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        cardView.backgroundColor = PopupPalette.card
        cardView.layer.cornerRadius = 16
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = PopupPalette.border.cgColor
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            cardView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.92).withPriority(.defaultHigh),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: cardView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            // Card hugs its content height (scrolls only when it would exceed the top/bottom limits).
            scrollView.heightAnchor.constraint(equalTo: contentStack.heightAnchor).withPriority(.defaultHigh),
        ])
    }

    @objc func dismissTapped() { dismiss(animated: true) }

    // MARK: reusable builders

    func header(title: String, subtitle: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(19)])

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = PopupPalette.subtle
        closeBtn.setContentHuggingPriority(.required, for: .horizontal)
        closeBtn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeBtn.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), closeBtn])
        topRow.axis = .horizontal
        topRow.alignment = .center

        let sub = UILabel()
        sub.attributedText = NSAttributedString(string: subtitle, attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)])
        sub.numberOfLines = 0

        let v = UIStackView(arrangedSubviews: [topRow, sub])
        v.axis = .vertical
        v.spacing = 4
        return v
    }

    func infoRow(_ label: String, _ value: String) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        let s = NSMutableAttributedString(string: label, attributes: [.foregroundColor: PopupPalette.cyan, .font: pMed(13)])
        s.append(NSAttributedString(string: value, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(13)]))
        l.attributedText = s
        return l
    }

    func box(_ views: [UIView], bg: UIColor, border: UIColor) -> UIView {
        let container = UIView()
        container.backgroundColor = bg
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = border.cgColor
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    /// Filled (tinted background) badge — used for the Fuel/Key state tags.
    func filledBadge(_ text: String, color: UIColor) -> UIView {
        let l = PopupPaddedLabel()
        l.text = text
        l.font = pBold(11)
        l.textColor = color
        l.backgroundColor = color.withAlphaComponent(0.18)
        l.insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        l.layer.cornerRadius = 5
        l.clipsToBounds = true
        return l
    }

    func badge(_ text: String, color: UIColor) -> UIView {
        let l = PopupPaddedLabel()
        l.text = text
        l.font = pBold(11)
        l.textColor = color
        l.insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        l.layer.cornerRadius = 5
        l.layer.borderWidth = 1
        l.layer.borderColor = color.withAlphaComponent(0.6).cgColor
        l.clipsToBounds = true
        return l
    }

    func dropdown(_ placeholder: String) -> UIView {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: placeholder, attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)])
        l.numberOfLines = 1

        let chevron = UIImageView(image: UIImage(named: "icon_Down")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = PopupPalette.cyan
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let row = UIStackView(arrangedSubviews: [l, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.backgroundColor = PopupPalette.box
        row.layer.cornerRadius = 10
        row.layer.borderWidth = 1
        row.layer.borderColor = PopupPalette.border.cgColor
        return row
    }

    func fieldTitle(_ text: String, required: Bool) -> UILabel {
        let l = UILabel()
        let s = NSMutableAttributedString(string: text, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(13)])
        if required { s.append(NSAttributedString(string: " *", attributes: [.foregroundColor: PopupPalette.red, .font: pBold(13)])) }
        l.attributedText = s
        return l
    }

    func filledButton(_ title: String, bg: UIColor, fg: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = pBold(15)
        b.setTitleColor(fg, for: .normal)
        b.backgroundColor = bg
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return b
    }

    func outlineButton(_ title: String, color: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = pBold(15)
        b.setTitleColor(color, for: .normal)
        b.layer.cornerRadius = 10
        b.layer.borderWidth = 1.5
        b.layer.borderColor = color.cgColor
        b.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return b
    }
}

extension QueueLinePopupBase: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only dismiss when tapping the dimmed area, not the card.
        return touch.view == self.view
    }
}

// MARK: - Mark as Staged (pending)

final class QueueLineStageViewController: QueueLinePopupBase {

    var item: QueueLineModel?
    var employees: [EmployeesModel] = []          // passed in from the list screen
    var categories: [CategoryModel] = []          // for Reassign → Category
    var allEquipment: [MachineModel] = []         // for Reassign → Equipment (filtered by category)
    var onChanged: (() -> Void)?                  // called after a successful stage
    var onStaged: ((QueueLineModel) -> Void)?     // called AFTER a successful stage → open Delivery Checklist

    private var selectedEmployeeId = ""           // id to send to the mark-staged API
    private var selectedCategoryId: Int?
    private var selectedEquipmentId = ""          // reassigned equipment unique_id
    private var filteredEquipment: [MachineModel] = []
    private let stagedByButton = UIButton(type: .system)
    private let categoryButton = UIButton(type: .system)
    private let equipmentButton = UIButton(type: .system)

    private var equipmentOptions: [RadioOption] = []
    private let fuelSegment = UISegmentedControl(items: ["Not Full", "Full"])
    private let keySegment  = UISegmentedControl(items: ["Missing", "With Machine"])

    // Sectioned equipment picker (replicates CheckListViewController's btnMachineIdClicked)
    private let eqHiddenField = UITextField(frame: .zero)   // host for inputView/accessory
    private let eqPicker = UIPickerView()
    private var eqSelectedIndex = 0
    private var eqPickerData: [String] = []
    private var eqPickerList: [MachineModel] = []           // source list backing the current pickerData

    override func viewDidLoad() {
        super.viewDidLoad()
        setupEquipmentPicker()

        let eq = item?.equipment
        let productName = item?.product?.name ?? ""
        let orderNo = item?.order_number ?? ""

        contentStack.addArrangedSubview(header(title: "Mark as Staged", subtitle: "ID: \(orderNo) — \(productName)"))

        // Order info (blue-tinted)
        contentStack.addArrangedSubview(box([
            infoRow("Order ID: ", "#\(orderNo)"),
            infoRow("Customer: ", item?.customer_name ?? ""),
            infoRow("Product Ordered: ", productName),
        ], bg: PopupPalette.cyan.withAlphaComponent(0.10), border: PopupPalette.cyan.withAlphaComponent(0.35)))

        // Equipment: two radios on one row — Use Currently Assigned | Reassign
        let useCurrent = RadioOption(title: "Assigned")
        useCurrent.isSelected = true
        let reassign = RadioOption(title: "Reassign")
        equipmentOptions = [useCurrent, reassign]
        useCurrent.addTarget(self, action: #selector(equipmentChanged(_:)), for: .touchUpInside)
        reassign.addTarget(self, action: #selector(equipmentChanged(_:)), for: .touchUpInside)

        let radioRow = UIStackView(arrangedSubviews: [useCurrent, reassign])
        radioRow.axis = .horizontal
        radioRow.spacing = 8
        radioRow.alignment = .center
        radioRow.distribution = .fillEqually

        // Currently-assigned details (shown when "Use Currently Assigned")
        let eqName = eq?.name ?? ""
        let eqId = eq?.display_id.map { "#\($0)" } ?? ""
        let detail = UILabel(); detail.numberOfLines = 0; detail.attributedText = codeLine(eqName, eqId)
        var detailViews: [UIView] = [detail]
        if let sl = eq?.status_label, eq?.status == "maintenance" {
            let holdRow = UIStackView(arrangedSubviews: [badge(sl, color: PopupPalette.amber),
                                                         plain("at \(item?.store?.name ?? "")", PopupPalette.subtle)])
            holdRow.axis = .horizontal; holdRow.spacing = 8; holdRow.alignment = .center
            detailViews.append(leftAligned(holdRow))
        }
        let currentDetails = UIStackView(arrangedSubviews: detailViews)
        currentDetails.axis = .vertical; currentDetails.spacing = 6

        // Assigned box (radios + current equipment details)
        let equipmentBox = box([radioRow, currentDetails],
                               bg: PopupPalette.green.withAlphaComponent(0.10),
                               border: PopupPalette.green.withAlphaComponent(0.45))
        contentStack.addArrangedSubview(equipmentBox)

        // Reassign fields in their OWN separate box — shown only when "Reassign" is picked.
        styleDropdownButton(categoryButton, placeholder: "Select Category", action: #selector(categoryTapped(_:)))
        styleDropdownButton(equipmentButton, placeholder: "Select Equipment", action: #selector(equipmentTapped(_:)))
        let category = labeledField("Category", required: false, control: categoryButton)
        let equipment = labeledField("Equipment", required: true, control: equipmentButton)
        let reassignBox = box([category, equipment], bg: PopupPalette.box, border: PopupPalette.border)
        reassignBox.isHidden = true
        contentStack.addArrangedSubview(reassignBox)

        self.currentDetailsView = currentDetails
        self.reassignFieldsView = reassignBox

        // Staged By — tappable employee picker
        contentStack.addArrangedSubview(labeledField("Staged By", required: true, control: makeStagedByField()))
        contentStack.addArrangedSubview(plain("Staging is attributed to the employee selected above.", PopupPalette.subtle, pMed(11)))

        // Fuel + Key — shown only when the equipment actually has fuel / a key.
        var fuelKeyCols: [UIView] = []
        if item?.equipment?.is_fuel == true {
            styleSegment(fuelSegment, selected: 0)
            fuelKeyCols.append(labeledField("Fuel", required: true, control: fuelSegment))
        }
        if item?.equipment?.is_key == true {
            styleSegment(keySegment, selected: 0)
            fuelKeyCols.append(labeledField("Key", required: true, control: keySegment))
        }
        if !fuelKeyCols.isEmpty {
            let fuelKey = UIStackView(arrangedSubviews: fuelKeyCols)
            fuelKey.axis = .horizontal; fuelKey.spacing = 16; fuelKey.distribution = .fillEqually; fuelKey.alignment = .top
            contentStack.addArrangedSubview(fuelKey)
            contentStack.setCustomSpacing(26, after: fuelKey)
        }

        // Buttons — extra gap above so they aren't cramped against Fuel/Key
        let cancel = outlineButton("Cancel", color: PopupPalette.subtle)
        cancel.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        let markStaged = filledButton("Mark as Staged", bg: PopupPalette.green, fg: .white)
        markStaged.addTarget(self, action: #selector(markStagedTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, markStaged])
        buttons.axis = .horizontal; buttons.spacing = 12; buttons.distribution = .fillEqually
        contentStack.addArrangedSubview(buttons)
    }

    private var currentDetailsView: UIView?
    private var reassignFieldsView: UIView?

    // MARK: - Dropdown pickers
    private func makeStagedByField() -> UIView {
        styleDropdownButton(stagedByButton, placeholder: "Select Employee", action: #selector(stagedByTapped(_:)))
        return stagedByButton
    }

    /// Styles a button to look like the app's dropdown field (cyan icon_Down chevron).
    private func styleDropdownButton(_ button: UIButton, placeholder: String, action: Selector) {
        button.contentHorizontalAlignment = .left
        button.setTitle(placeholder, for: .normal)
        button.setTitleColor(PopupPalette.subtle, for: .normal)
        button.titleLabel?.font = pMed(13)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.backgroundColor = PopupPalette.box
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = PopupPalette.border.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 36)
        button.addTarget(self, action: action, for: .touchUpInside)

        let chevron = UIImageView(image: UIImage(named: "icon_Down")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = PopupPalette.cyan
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    // Category → filters equipment for that category.
    @objc private func categoryTapped(_ sender: UIButton) {
        guard !categories.isEmpty else { return }
        let names = categories.compactMap { $0.name }
        let current = categoryButton.title(for: .normal) ?? ""
        actionPicker(sender, strTitle: "Select Category", arrData: names, selectValue: current) { [weak self] index, value in
            guard let self = self, index < self.categories.count else { return }
            let cat = self.categories[index]
            self.selectedCategoryId = cat.id
            self.categoryButton.setTitle(value, for: .normal)
            self.categoryButton.setTitleColor(PopupPalette.ink, for: .normal)

            if value == "All" {
                self.filteredEquipment = self.allEquipment
            } else {
                self.filteredEquipment = self.allEquipment.filter { $0.category_id == cat.id }
            }
            self.selectedEquipmentId = ""
            self.equipmentButton.setTitle(self.filteredEquipment.isEmpty ? "No equipment available" : "Select Equipment", for: .normal)
            self.equipmentButton.setTitleColor(PopupPalette.subtle, for: .normal)
        }
    }

    // Equipment → opens the SAME sectioned picker as CheckListViewController (grouped by status).
    @objc private func equipmentTapped(_ sender: UIButton) {
        // Category is optional — with none chosen, show all equipment (like the checklist).
        let list = (selectedCategoryId != nil) ? filteredEquipment : allEquipment
        guard !list.isEmpty else { return }
        eqPickerList = list
        setEqPickerData(from: list)
        // Preselect the first non-section row so a section header is never "selected".
        eqSelectedIndex = eqPickerData.firstIndex(where: { !$0.hasPrefix("Section:") }) ?? 0
        eqOpenPicker()
    }

    // MARK: - Sectioned equipment picker (mirrors CheckListViewController.openPicker)

    private func setupEquipmentPicker() {
        eqPicker.dataSource = self
        eqPicker.delegate = self
        eqPicker.backgroundColor = .white

        eqHiddenField.translatesAutoresizingMaskIntoConstraints = false
        eqHiddenField.isHidden = true
        view.addSubview(eqHiddenField)

        let pickerHeight: CGFloat = 260
        let headerHeight: CGFloat = 56

        let host = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: headerHeight + pickerHeight))
        host.backgroundColor = .black
        host.isOpaque = true

        let head = buildEqPickerHeader(title: "Select Equipment ID")
        head.frame.origin = .zero

        eqPicker.frame = CGRect(x: 0, y: headerHeight, width: host.bounds.width, height: pickerHeight)
        eqPicker.autoresizingMask = [.flexibleWidth]
        eqPicker.backgroundColor = .white
        eqPicker.roundCornersView(onTopLeft: true, topRight: true, bottomLeft: false, bottomRight: false, radius: 15)

        host.addSubview(head)
        host.addSubview(eqPicker)

        eqHiddenField.inputAccessoryView = nil
        eqHiddenField.inputView = host
    }

    private func buildEqPickerHeader(title: String) -> UIView {
        let h: CGFloat = 56
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: h))
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
        cancel.addTarget(self, action: #selector(eqCancelTapped), for: .touchUpInside)

        let select = UIButton(type: .system)
        select.setTitle("Select", for: .normal)
        select.setTitleColor(.white, for: .normal)
        select.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        select.backgroundColor = UIColor.systemBlue
        select.layer.cornerRadius = pillH / 2
        select.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        select.frame = CGRect(x: header.bounds.width - 14 - 92, y: y, width: 92, height: pillH)
        select.autoresizingMask = [.flexibleLeftMargin]
        select.addTarget(self, action: #selector(eqDoneTapped), for: .touchUpInside)

        let titleBtn = UIButton(type: .system)
        titleBtn.setTitle(title, for: .normal)
        titleBtn.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
        titleBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleBtn.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        titleBtn.layer.cornerRadius = pillH / 2
        titleBtn.isUserInteractionEnabled = false

        let leftMaxX = cancel.frame.maxX + 12
        let rightMinX = select.frame.minX - 12
        let midW = max(0, rightMinX - leftMaxX)
        titleBtn.frame = CGRect(x: leftMaxX, y: y, width: midW, height: pillH)
        titleBtn.autoresizingMask = [.flexibleWidth]

        header.addSubview(cancel)
        header.addSubview(titleBtn)
        header.addSubview(select)
        return header
    }

    private func setEqPickerData(from list: [MachineModel]) {
        eqPickerData.removeAll()
        let grouped = Dictionary(grouping: list, by: { $0.status ?? "" })
        let sortedGroups = grouped.sorted { $0.key < $1.key }
        for (section, items) in sortedGroups {
            eqPickerData.append("Section: \(section)")
            for obj in items {
                eqPickerData.append("\(obj.equipment_name ?? "")    ||    \(obj.equipment_id ?? "")")
            }
        }
    }

    private func eqOpenPicker() {
        eqPicker.reloadAllComponents()
        if eqPickerData.indices.contains(eqSelectedIndex) {
            eqPicker.selectRow(eqSelectedIndex, inComponent: 0, animated: false)
        }
        eqHiddenField.becomeFirstResponder()
    }

    @objc private func eqCancelTapped() {
        eqHiddenField.resignFirstResponder()
    }

    @objc private func eqDoneTapped() {
        eqSelectedIndex = eqPicker.selectedRow(inComponent: 0)
        eqHiddenField.resignFirstResponder()

        guard eqPickerData.indices.contains(eqSelectedIndex) else { return }
        let input = eqPickerData[eqSelectedIndex]
        guard !input.hasPrefix("Section:") else { return }

        if let code = input.components(separatedBy: "||").last?.trimmingCharacters(in: .whitespaces) {
            let ids = eqPickerList.map { $0.equipment_id }
            if let index = ids.firstIndex(of: code) {
                let obj = eqPickerList[index]
                self.selectedEquipmentId = obj.unique_id ?? ""
                self.equipmentButton.setTitle("\(obj.equipment_name ?? "")   ·   \(obj.equipment_id ?? "")", for: .normal)
                self.equipmentButton.setTitleColor(PopupPalette.ink, for: .normal)
            }
        }
    }

    @objc private func stagedByTapped(_ sender: UIButton) {
        guard !employees.isEmpty else { return }
        let names = employees.compactMap { $0.name }
        let current = stagedByButton.title(for: .normal) ?? ""
        actionPicker(sender, strTitle: "Select Employee", arrData: names, selectValue: current) { [weak self] index, value in
            guard let self = self, index < self.employees.count else { return }
            let emp = self.employees[index]
            self.selectedEmployeeId =  emp.unique_id ?? ""
            self.stagedByButton.setTitle(value, for: .normal)
            self.stagedByButton.setTitleColor(PopupPalette.ink, for: .normal)
        }
    }

    // MARK: - Mark as Staged
    @objc private func markStagedTapped() {
        guard let id = item?.order_product_unique_id, !id.isEmpty else { return }

        // Determine equipment: reassigned selection vs. currently assigned.
        let isReassign = (equipmentOptions.last?.isSelected == true)
        let equipmentUniqueId: String
        if isReassign {
            // Category is optional; Equipment is required.
            guard !selectedEquipmentId.isEmpty else {
                showAlertMessage(strMessage: "Please select the equipment to assign.")
                return
            }
            equipmentUniqueId = selectedEquipmentId
        } else {
            equipmentUniqueId = item?.equipment?.unique_id ?? ""
        }

        // Validation: an employee (Staged By) is required.
        guard !selectedEmployeeId.isEmpty else {
            showAlertMessage(strMessage: "Please select the employee who staged this machine.")
            return
        }

        var params: [String: Any] = [
            "equipment_unique_id": equipmentUniqueId,
            "performed_by": selectedEmployeeId
        ]
        // Only send fuel / key when the equipment actually has them.
        if item?.equipment?.is_fuel == true {
            params["fuel_full"] = (fuelSegment.selectedSegmentIndex == 1)          // "Full"
        }
        if item?.equipment?.is_key == true {
            params["key_with_machine"] = (keySegment.selectedSegmentIndex == 1)    // "With Machine"
        }

        let strURL = "\(Url.queueLineMarkStaged(id).absoluteString ?? "")"
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "markStaged"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = params
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPIwithCompletation { [weak self] data, _, _, error in
            indicatorHide()
            guard let self = self else { return }
            let ok = (error == nil) && (data?.getStringForID(key: "success") == "1")
            // Navigate to the Delivery Checklist ONLY after staging succeeds.
            if ok {
                let staged = self.item
                self.dismiss(animated: true) {
                    self.onChanged?()
                    if let staged = staged { self.onStaged?(staged) }
                }
            }
            else {
                // Staging rejected (e.g. QUEUE_FUEL_NOT_FULL) — keep the popup open and surface the
                // server's message plus its corrective action so the employee knows what to fix.
                let message = data?.getStringForID(key: "message")
                if message != ""{
                    showAlertMessage(strMessage: message ?? "")
                }
            }
        }
    }

    @objc private func equipmentChanged(_ sender: RadioOption) {
        equipmentOptions.forEach { $0.isSelected = ($0 == sender) }
        let reassignPicked = (equipmentOptions.last == sender)   // "Reassign" is the second option
        reassignFieldsView?.isHidden = !reassignPicked
        // Assigned equipment details stay visible in both states.
    }

    private func codeLine(_ name: String, _ id: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: name, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(14)])
        if !id.isEmpty {
            s.append(NSAttributedString(string: "   ·   \(id)", attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)]))
        }
        return s
    }

    private func plain(_ text: String, _ color: UIColor, _ font: UIFont? = nil) -> UILabel {
        let l = UILabel(); l.numberOfLines = 0
        l.attributedText = NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font ?? pMed(13)])
        return l
    }

    private func leftAligned(_ v: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [v, UIView()])
        row.axis = .horizontal; row.alignment = .center
        return row
    }

    private func labeledField(_ title: String, required: Bool, control: UIView) -> UIStackView {
        let s = UIStackView(arrangedSubviews: [fieldTitle(title, required: required), control])
        s.axis = .vertical; s.spacing = 8
        return s
    }

    /// Styles a segmented control exactly like the app's Fuel/Keys control.
    private func styleSegment(_ seg: UISegmentedControl, selected: Int) {
        seg.selectedSegmentIndex = selected
        seg.selectedSegmentTintColor = PopupPalette.cyan
        seg.backgroundColor = .clear
        seg.layer.borderWidth = 1
        seg.layer.borderColor = PopupPalette.cyan.cgColor
        seg.layer.cornerRadius = 8
        seg.layer.masksToBounds = true
        seg.apportionsSegmentWidthsByContent = false
        seg.setTitleTextAttributes([.foregroundColor: PopupPalette.cyan, .font: pMed(12)], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: PopupPalette.page, .font: pBold(12)], for: .selected)
        seg.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
}

// MARK: - Equipment picker data source/delegate (sectioned by status, like CheckListViewController)

extension QueueLineStageViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return eqPickerData.count
    }

    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        guard row >= 0, row < eqPickerData.count else { return nil }
        let text = eqPickerData[row]

        if text.hasPrefix("Section:") {
            return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Light, size: 8),
                .foregroundColor: UIColor.gray.withAlphaComponent(0.5)
            ])
        }

        return NSAttributedString(string: text, attributes: [
            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14),
            .foregroundColor: UIColor.background
        ])
    }

    // Prevent landing on a section header — hop to the nearest selectable row.
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard eqPickerData.indices.contains(row) else { return }
        guard eqPickerData[row].hasPrefix("Section:") else { return }

        var nextRow = row + 1
        while eqPickerData.indices.contains(nextRow), eqPickerData[nextRow].hasPrefix("Section:") {
            nextRow += 1
        }
        if eqPickerData.indices.contains(nextRow) {
            pickerView.selectRow(nextRow, inComponent: component, animated: true)
        } else {
            var previousRow = row - 1
            while eqPickerData.indices.contains(previousRow), eqPickerData[previousRow].hasPrefix("Section:") {
                previousRow -= 1
            }
            if eqPickerData.indices.contains(previousRow) {
                pickerView.selectRow(previousRow, inComponent: component, animated: true)
            }
        }
    }
}

// MARK: - Staged details

final class QueueLineStagedInfoViewController: QueueLinePopupBase {

    var item: QueueLineModel?
    /// Called after a successful "Return to Pending" so the list can refresh.
    var onChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        let eq = item?.equipment
        let eqName = eq?.name ?? ""
        let eqId = eq?.display_id.map { "#\($0)" } ?? ""
        let orderNo = item?.order_number ?? ""
        let productName = item?.product?.name ?? ""

        contentStack.addArrangedSubview(header(title: "Staged", subtitle: "ID: \(orderNo) — \(productName)"))

        let code = UILabel()
        let cs = NSMutableAttributedString(string: eqName, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(14)])
        if !eqId.isEmpty { cs.append(NSAttributedString(string: "   ·   \(eqId)", attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)])) }
        code.attributedText = cs
        let ready = UILabel()
        ready.attributedText = NSAttributedString(string: "Fueled, staged — ready for handoff.", attributes: [.foregroundColor: PopupPalette.green, .font: pMed(12)])
        contentStack.addArrangedSubview(box([code, ready], bg: PopupPalette.green.withAlphaComponent(0.10), border: PopupPalette.green.withAlphaComponent(0.45)))

        // Entered By — the employee who staged it (staged_by).
        contentStack.addArrangedSubview(detailRow("Entered By", item?.staged_by ?? ""))

        // Fuel / Key state tags — shown only when the equipment has them.
        if item?.equipment?.is_fuel == true {
            let verified = (item?.fuel?.state == "verified")
            contentStack.addArrangedSubview(detailRowBadge("Fuel",
                filledBadge(verified ? "Full — Verified" : "Not Verified",
                            color: verified ? PopupPalette.green : PopupPalette.amber)))
        }
        if item?.equipment?.is_key == true {
            let confirmed = (item?.key?.state == "confirmed")
            contentStack.addArrangedSubview(detailRowBadge("Key",
                filledBadge(confirmed ? "With Machine — Confirmed" : "Missing",
                            color: confirmed ? PopupPalette.green : PopupPalette.amber)))
        }

        // Staged — timestamp it was staged (staged_at).
        contentStack.addArrangedSubview(detailRow("Staged", formatStagedDate(item?.staged_at)))

        let ret = outlineButton("Return to Pending", color: PopupPalette.amber)
        ret.addTarget(self, action: #selector(returnToPendingTapped), for: .touchUpInside)
        let close = outlineButton("Close", color: PopupPalette.subtle)
        close.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [ret, close])
        buttons.axis = .horizontal; buttons.spacing = 12; buttons.distribution = .fillEqually
        contentStack.addArrangedSubview(buttons)
    }

    // MARK: - Return to Pending
    @objc private func returnToPendingTapped() {
        guard let id = item?.order_product_unique_id, !id.isEmpty else { return }
        // performed_by expects an employee id (same as mark-staged), not a display name.
//        let performedBy = UserDefaults.standard.user?.unique_id ?? "\(UserDefaults.standard.user?.id ?? "")"

        let strURL = "\(Url.queueLineReturnToPending(id).absoluteString ?? "")"
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "returnToPending"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = ["performed_by": ""]
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true

        webHelper.callAPIwithCompletation { [weak self] data, _, _, error in
            indicatorHide()
            guard let self = self else { return }
            let ok = (error == nil) && (data?.getStringForID(key: "success") == "1")
            if ok {
                self.dismiss(animated: true) { self.onChanged?() }
            }
        }
    }

    /// "2026-07-20T21:41:06-05:00" → "Mon Jul 20  ·  9:41 PM".
    private func formatStagedDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        var date = parser.date(from: iso)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: iso)
        }
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "EEE MMM d  ·  h:mm a"
        return out.string(from: d)
    }

    private func detailRow(_ label: String, _ value: String) -> UIView {
        let l = UILabel(); l.attributedText = NSAttributedString(string: label, attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)])
        let v = UILabel(); v.attributedText = NSAttributedString(string: value, attributes: [.foregroundColor: PopupPalette.ink, .font: pBold(13)]); v.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [l, UIView(), v])
        row.axis = .horizontal; row.alignment = .center
        return row
    }
    private func detailRowBadge(_ label: String, _ badge: UIView) -> UIView {
        let l = UILabel(); l.attributedText = NSAttributedString(string: label, attributes: [.foregroundColor: PopupPalette.subtle, .font: pMed(13)])
        let row = UIStackView(arrangedSubviews: [l, UIView(), badge])
        row.axis = .horizontal; row.alignment = .center
        return row
    }
}

// MARK: - Change Equipment (design only)

/// "Confirm / Update Equipment" popup opened from a Queue Line card's menu.
/// DESIGN ONLY — the Select button just dismisses (no change-equipment API is wired yet).
/// The equipment picker shows ONLY Available + Maint. Hold machines.
final class QueueLineChangeEquipmentViewController: QueueLinePopupBase {

    var item: QueueLineModel?
    var employees: [EmployeesModel] = []
    var categories: [CategoryModel] = []
    var allEquipment: [MachineModel] = []
    var onChanged: (() -> Void)?

    private var selectedEmployeeId = ""
    private var selectedReason = ""
    private var selectedCategoryId: Int?
    private var selectedEquipmentId = ""
    private var filteredEquipment: [MachineModel] = []

    private let performedByButton = UIButton(type: .system)
    private let reasonButton = UIButton(type: .system)
    private let categoryButton = UIButton(type: .system)
    private let equipmentButton = UIButton(type: .system)

    /// Non-direct assignment reasons.
    private let reasons = ["Reserved unit unavailable",
                           "Original unit down for maintenance or damage",
                           "Better-suited unit available",
                           "Correcting a mis-assignment",
                           "Customer request",
                           "Other…"]

    /// The pool of units the user can switch to. Populated from the AVAILABLE equipment
    /// (currently_assigned = 0), restricted to Available + Maint. Hold. If that fetch yields
    /// nothing (e.g. offline), it falls back to whatever list the parent handed us.
    private var equipmentPool: [MachineModel] = []
    private var loadedAvailablePool = false

    /// Available + Maint. Hold only.
    private func availableOnly(_ list: [MachineModel]) -> [MachineModel] {
        list.filter { ($0.status == "Available") || ($0.status == "Maint. Hold") }
    }

    // Sectioned equipment picker infra (mirrors CheckListViewController.openPicker)
    private let eqHiddenField = UITextField(frame: .zero)
    private let eqPicker = UIPickerView()
    private var eqSelectedIndex = 0
    private var eqPickerData: [String] = []
    private var eqPickerList: [MachineModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupEquipmentPicker()

        let eq = item?.equipment
        let orderNo = item?.order_number ?? ""
        let productName = item?.product?.name ?? ""
        let currentName = eq?.name ?? ""
        let currentId = eq?.display_id.map { " · \($0)" } ?? ""
        // order_number may already include a leading "#" — avoid showing "##".
        let orderLabel = orderNo.hasPrefix("#") ? orderNo : "#\(orderNo)"

        // "currently …" goes on its own second line.
        contentStack.addArrangedSubview(header(title: "Confirm / Update Equipment",
                                               subtitle: "Order \(orderLabel) — \(productName)\ncurrently \(currentName)\(currentId)"))

        // Row 1: Performed By (required) + Reason
        styleDropdownButton(performedByButton, placeholder: "Select yourself…", action: #selector(performedByTapped(_:)))
        styleDropdownButton(reasonButton, placeholder: "Select a reason…", action: #selector(reasonTapped(_:)))
        let row1 = UIStackView(arrangedSubviews: [
            labeledField("Performed By", required: true, control: performedByButton),
            labeledField("Reason", required: false, control: reasonButton),
        ])
        row1.axis = .horizontal; row1.spacing = 12; row1.distribution = .fillEqually; row1.alignment = .top
        contentStack.addArrangedSubview(row1)

        // Row 2: Category + Equipment (sectioned picker, filtered to Available + Maint. Hold)
        styleDropdownButton(categoryButton, placeholder: "Select category…", action: #selector(categoryTapped(_:)))
        styleDropdownButton(equipmentButton, placeholder: "Search Equipment ID", action: #selector(equipmentTapped(_:)))
        contentStack.addArrangedSubview(labeledField("Category", required: false, control: categoryButton))
        contentStack.addArrangedSubview(labeledField("Equipment", required: true, control: equipmentButton))

        // Seed the pool from whatever the parent passed (immediate), then refresh from the
        // AVAILABLE-equipment endpoint so the picker shows units that can actually be assigned.
        equipmentPool = availableOnly(allEquipment)
        preselectCurrentCategory()
        loadAvailableEquipment()

        // Buttons
        let cancel = outlineButton("Cancel", color: ChangeEqPalette.subtle)
        cancel.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        let select = filledButton("Select", bg: ChangeEqPalette.cyan, fg: ChangeEqPalette.page)
        select.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, select])
        buttons.axis = .horizontal; buttons.spacing = 12; buttons.distribution = .fillEqually
        contentStack.addArrangedSubview(buttons)
    }

    @objc private func selectTapped() {
        guard let id = item?.order_product_unique_id, !id.isEmpty else {
            showAlertMessage(strMessage: "Missing order reference.")
            return
        }
        // Performed By and Equipment are required; Reason is optional.
        guard !selectedEmployeeId.isEmpty else {
            showAlertMessage(strMessage: "Please select who performed this change.")
            return
        }
        guard !selectedEquipmentId.isEmpty else {
            showAlertMessage(strMessage: "Please select the equipment to switch to.")
            return
        }

        var params: [String: Any] = [
            "equipment_unique_id": selectedEquipmentId,
            "performed_by": selectedEmployeeId,
            // Guards against a duplicate switch if the request is retried.
            "idempotency_token": UUID().uuidString
        ]
        if !selectedReason.isEmpty {
            params["reason"] = selectedReason
        }

        let strURL = "\(Url.queueLineSwitchEquipment(id).absoluteString ?? "")"
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "switchEquipment"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = params
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPIwithCompletation { [weak self] data, _, _, error in
            indicatorHide()
            guard let self = self else { return }
            let ok = (error == nil) && (data?.getStringForID(key: "success") == "1")
            if ok { self.dismiss(animated: true) { self.onChanged?() } }
        }
    }

    /// Pre-select the Category to the order's current equipment category and pre-filter the
    /// Equipment picker to that category.
    private func preselectCurrentCategory() {
        guard let catId = item?.equipment_collection?.category_id,
              let match = categories.first(where: { $0.id == catId }) else {
            refreshEquipmentField()   // Unknown category → leave equipment unfiltered.
            return
        }
        selectedCategoryId = match.id
        categoryButton.setTitle(match.name, for: .normal)
        categoryButton.setTitleColor(ChangeEqPalette.ink, for: .normal)
        refreshEquipmentField()
    }

    /// Fetches the AVAILABLE equipment pool (currently_assigned = 0) so units that can be
    /// switched to actually appear. Uses the search endpoint, which does NOT overwrite the
    /// shared equipment cache. Falls back to the parent list if the fetch is empty (offline).
    private func loadAvailableEquipment() {
        equipmentButton.setTitle("Loading available equipment…", for: .normal)
        equipmentButton.setTitleColor(ChangeEqPalette.subtle, for: .normal)

        getFilterEquipmentList(strType: "Checklist", int_assigned: 0) { [weak self] arr in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadedAvailablePool = true
                if !arr.isEmpty {
                    self.equipmentPool = self.availableOnly(arr)
                } else if self.equipmentPool.isEmpty {
                    // Offline / empty response → let the user pick from the passed list.
                    self.equipmentPool = self.allEquipment
                }
                self.selectedEquipmentId = ""
                self.refreshEquipmentField()
            }
        }
    }

    /// Recomputes the filtered equipment for the current category and updates the field state.
    private func refreshEquipmentField() {
        if let catId = selectedCategoryId {
            filteredEquipment = equipmentPool.filter { $0.category_id == catId }
        } else {
            filteredEquipment = equipmentPool
        }
        let list = (selectedCategoryId != nil) ? filteredEquipment : equipmentPool
        let stillLoading = !loadedAvailablePool && equipmentPool.isEmpty
        if stillLoading {
            equipmentButton.setTitle("Loading available equipment…", for: .normal)
        } else {
            equipmentButton.setTitle(list.isEmpty ? "No equipment available" : "Search Equipment ID", for: .normal)
        }
        equipmentButton.setTitleColor(ChangeEqPalette.subtle, for: .normal)
    }

    // MARK: Dropdown pickers

    @objc private func performedByTapped(_ sender: UIButton) {
        guard !employees.isEmpty else { return }
        let names = employees.compactMap { $0.name }
        let current = performedByButton.title(for: .normal) ?? ""
        actionPicker(sender, strTitle: "Select Employee", arrData: names, selectValue: current) { [weak self] index, value in
            guard let self = self, index < self.employees.count else { return }
            self.selectedEmployeeId = self.employees[index].unique_id ?? ""
            self.performedByButton.setTitle(value, for: .normal)
            self.performedByButton.setTitleColor(ChangeEqPalette.ink, for: .normal)
        }
    }

    @objc private func reasonTapped(_ sender: UIButton) {
        let current = reasonButton.title(for: .normal) ?? ""
        actionPicker(sender, strTitle: "Select Reason", arrData: reasons, selectValue: current) { [weak self] index, value in
            guard let self = self, index < self.reasons.count else { return }
            self.selectedReason = self.reasons[index]
            self.reasonButton.setTitle(value, for: .normal)
            self.reasonButton.setTitleColor(ChangeEqPalette.ink, for: .normal)
        }
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        guard !categories.isEmpty else { return }
        let names = categories.compactMap { $0.name }
        let current = categoryButton.title(for: .normal) ?? ""
        actionPicker(sender, strTitle: "Select Category", arrData: names, selectValue: current) { [weak self] index, value in
            guard let self = self, index < self.categories.count else { return }
            let cat = self.categories[index]
            self.selectedCategoryId = (value == "All") ? nil : cat.id
            self.categoryButton.setTitle(value, for: .normal)
            self.categoryButton.setTitleColor(ChangeEqPalette.ink, for: .normal)

            self.selectedEquipmentId = ""
            self.refreshEquipmentField()
        }
    }

    @objc private func equipmentTapped(_ sender: UIButton) {
        // Available + Maint. Hold, optionally filtered by the chosen category.
        let list = (selectedCategoryId != nil) ? filteredEquipment : equipmentPool
        guard !list.isEmpty else { return }
        eqPickerList = list
        setEqPickerData(from: list)
        eqSelectedIndex = eqPickerData.firstIndex(where: { !$0.hasPrefix("Section:") }) ?? 0
        eqOpenPicker()
    }

    private func styleDropdownButton(_ button: UIButton, placeholder: String, action: Selector) {
        button.contentHorizontalAlignment = .left
        button.setTitle(placeholder, for: .normal)
        button.setTitleColor(ChangeEqPalette.subtle, for: .normal)
        button.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 13)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.backgroundColor = ChangeEqPalette.box
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = ChangeEqPalette.border.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 36)
        button.addTarget(self, action: action, for: .touchUpInside)

        let chevron = UIImageView(image: UIImage(named: "icon_Down")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = ChangeEqPalette.cyan
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func labeledField(_ title: String, required: Bool, control: UIView) -> UIStackView {
        let s = UIStackView(arrangedSubviews: [fieldTitle(title, required: required), control])
        s.axis = .vertical; s.spacing = 8
        return s
    }

    // MARK: Sectioned equipment picker (mirrors CheckListViewController.openPicker)

    private func setupEquipmentPicker() {
        eqPicker.dataSource = self
        eqPicker.delegate = self
        eqPicker.backgroundColor = .white

        eqHiddenField.translatesAutoresizingMaskIntoConstraints = false
        eqHiddenField.isHidden = true
        view.addSubview(eqHiddenField)

        let pickerHeight: CGFloat = 260
        let headerHeight: CGFloat = 56
        let host = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: headerHeight + pickerHeight))
        host.backgroundColor = .black
        host.isOpaque = true

        let head = buildEqPickerHeader(title: "Select Equipment ID")
        head.frame.origin = .zero

        eqPicker.frame = CGRect(x: 0, y: headerHeight, width: host.bounds.width, height: pickerHeight)
        eqPicker.autoresizingMask = [.flexibleWidth]
        eqPicker.backgroundColor = .white
        eqPicker.roundCornersView(onTopLeft: true, topRight: true, bottomLeft: false, bottomRight: false, radius: 15)

        host.addSubview(head)
        host.addSubview(eqPicker)

        eqHiddenField.inputAccessoryView = nil
        eqHiddenField.inputView = host
    }

    private func buildEqPickerHeader(title: String) -> UIView {
        let h: CGFloat = 56
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: h))
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
        cancel.addTarget(self, action: #selector(eqCancelTapped), for: .touchUpInside)

        let select = UIButton(type: .system)
        select.setTitle("Select", for: .normal)
        select.setTitleColor(.white, for: .normal)
        select.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        select.backgroundColor = UIColor.systemBlue
        select.layer.cornerRadius = pillH / 2
        select.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        select.frame = CGRect(x: header.bounds.width - 14 - 92, y: y, width: 92, height: pillH)
        select.autoresizingMask = [.flexibleLeftMargin]
        select.addTarget(self, action: #selector(eqDoneTapped), for: .touchUpInside)

        let titleBtn = UIButton(type: .system)
        titleBtn.setTitle(title, for: .normal)
        titleBtn.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
        titleBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleBtn.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        titleBtn.layer.cornerRadius = pillH / 2
        titleBtn.isUserInteractionEnabled = false

        let leftMaxX = cancel.frame.maxX + 12
        let rightMinX = select.frame.minX - 12
        let midW = max(0, rightMinX - leftMaxX)
        titleBtn.frame = CGRect(x: leftMaxX, y: y, width: midW, height: pillH)
        titleBtn.autoresizingMask = [.flexibleWidth]

        header.addSubview(cancel)
        header.addSubview(titleBtn)
        header.addSubview(select)
        return header
    }

    private func setEqPickerData(from list: [MachineModel]) {
        eqPickerData.removeAll()
        let grouped = Dictionary(grouping: list, by: { $0.status ?? "" })
        let sortedGroups = grouped.sorted { $0.key < $1.key }
        for (section, items) in sortedGroups {
            eqPickerData.append("Section: \(section)")
            for obj in items {
                eqPickerData.append("\(obj.equipment_name ?? "")    ||    \(obj.equipment_id ?? "")")
            }
        }
    }

    private func eqOpenPicker() {
        eqPicker.reloadAllComponents()
        if eqPickerData.indices.contains(eqSelectedIndex) {
            eqPicker.selectRow(eqSelectedIndex, inComponent: 0, animated: false)
        }
        eqHiddenField.becomeFirstResponder()
    }

    @objc private func eqCancelTapped() {
        eqHiddenField.resignFirstResponder()
    }

    @objc private func eqDoneTapped() {
        eqSelectedIndex = eqPicker.selectedRow(inComponent: 0)
        eqHiddenField.resignFirstResponder()

        guard eqPickerData.indices.contains(eqSelectedIndex) else { return }
        let input = eqPickerData[eqSelectedIndex]
        guard !input.hasPrefix("Section:") else { return }

        if let code = input.components(separatedBy: "||").last?.trimmingCharacters(in: .whitespaces) {
            let ids = eqPickerList.map { $0.equipment_id }
            if let index = ids.firstIndex(of: code) {
                let obj = eqPickerList[index]
                self.selectedEquipmentId = obj.unique_id ?? ""
                self.equipmentButton.setTitle("\(obj.equipment_name ?? "")   ·   \(obj.equipment_id ?? "")", for: .normal)
                self.equipmentButton.setTitleColor(ChangeEqPalette.ink, for: .normal)
            }
        }
    }
}

extension QueueLineChangeEquipmentViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { eqPickerData.count }

    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        guard row >= 0, row < eqPickerData.count else { return nil }
        let text = eqPickerData[row]
        if text.hasPrefix("Section:") {
            return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Light, size: 8),
                .foregroundColor: UIColor.gray.withAlphaComponent(0.5)
            ])
        }
        return NSAttributedString(string: text, attributes: [
            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14),
            .foregroundColor: UIColor.background
        ])
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard eqPickerData.indices.contains(row) else { return }
        guard eqPickerData[row].hasPrefix("Section:") else { return }
        var nextRow = row + 1
        while eqPickerData.indices.contains(nextRow), eqPickerData[nextRow].hasPrefix("Section:") { nextRow += 1 }
        if eqPickerData.indices.contains(nextRow) {
            pickerView.selectRow(nextRow, inComponent: component, animated: true)
        } else {
            var previousRow = row - 1
            while eqPickerData.indices.contains(previousRow), eqPickerData[previousRow].hasPrefix("Section:") { previousRow -= 1 }
            if eqPickerData.indices.contains(previousRow) {
                pickerView.selectRow(previousRow, inComponent: component, animated: true)
            }
        }
    }
}

/// File-local palette alias so the Change Equipment popup matches the app dark theme.
private enum ChangeEqPalette {
    static let page   = UIColor.background
    static let box    = UIColor.white.withAlphaComponent(0.05)
    static let border = UIColor.secondary.withAlphaComponent(0.35)
    static let ink    = UIColor.primary
    static let subtle = UIColor(red: 199/255, green: 206/255, blue: 216/255, alpha: 1)
    static let cyan   = UIColor.secondary
}

// MARK: - Small controls

/// Radio row: a circle (filled when selected) + title. Behaves like a button.
final class RadioOption: UIControl {
    private let outer = UIView()
    private let inner = UIView()
    private let title = UILabel()

    override var isSelected: Bool { didSet { refresh() } }

    init(title text: String) {
        super.init(frame: .zero)

        outer.layer.cornerRadius = 10
        outer.layer.borderWidth = 2
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.isUserInteractionEnabled = false
        outer.widthAnchor.constraint(equalToConstant: 20).isActive = true
        outer.heightAnchor.constraint(equalToConstant: 20).isActive = true

        inner.backgroundColor = PopupPalette.cyan
        inner.layer.cornerRadius = 5
        inner.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: outer.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: outer.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 10),
            inner.heightAnchor.constraint(equalToConstant: 10),
        ])

        title.text = text
        title.font = pBold(14)
        title.textColor = PopupPalette.ink
        title.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [outer, title])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        inner.isHidden = !isSelected
        outer.layer.borderColor = (isSelected ? PopupPalette.cyan : PopupPalette.subtle).cgColor
    }
}

/// Cyan segmented control — selected pill is cyan-filled, others cyan-outlined.
final class PopupSegment: UIView {
    private var buttons: [UIButton] = []
    private(set) var selectedIndex: Int = 0

    init(items: [String], selected: Int) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fillEqually
        stack.layer.cornerRadius = 10
        stack.layer.borderWidth = 1.5
        stack.layer.borderColor = PopupPalette.cyan.cgColor
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (i, title) in items.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = pBold(13)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.titleLabel?.lineBreakMode = .byClipping
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            b.tag = i
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append(b)
            stack.addArrangedSubview(b)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        select(selected)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped(_ sender: UIButton) { select(sender.tag) }

    private func select(_ index: Int) {
        selectedIndex = index
        for (i, b) in buttons.enumerated() {
            let on = (i == index)
            b.backgroundColor = on ? PopupPalette.cyan : .clear
            b.setTitleColor(on ? PopupPalette.page : PopupPalette.cyan, for: .normal)
        }
    }
}

private final class PopupPaddedLabel: UILabel {
    var insets = UIEdgeInsets.zero
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ p: UILayoutPriority) -> NSLayoutConstraint { priority = p; return self }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1.0)
    }
}
