//
//  NextStopViewController.swift
//  RentnKing — Dispatch / Next Stop (2026-10-18)
//
//  "What are you doing next?" — the screen a driver lands on the moment a
//  Delivery, Return or Manual Dispatch is effectively complete, instead of
//  being dropped back on the Dispatch board to work out the next step.
//
//  Two paths, and only ever two: the next assigned mission, or back to a shop.
//  This screen owns NEITHER. Missions belong to Dispatch and are handed in as
//  closures; the shop stop is the one destination Dispatch does not model, so
//  it is the only thing persisted here.
//
//  Local-first, in the order that matters: the shop reaches disk BEFORE Maps is
//  asked to open, because the next thing the driver does is leave the app. A
//  geocode failure therefore costs the trip to Maps, never the destination.
//
//  Shops come from the tenant's own active store list (getStoreList /
//  kStoreList). No store name or address is hard-coded: Rent N King sees Bon
//  Aqua and Waverly because those are its active stores, and another company
//  sees its own for the same reason.
//
//  Route events (2026-10-20): every answer the driver gives here — the next
//  mission, Return to Shop, Arrived at <shop> — is also handed to the Sync
//  Engine as a next_stop.event, the evidence Kabba's Driver Efficiency report
//  rebuilds the actual route from. Recording never blocks the driver and
//  never changes what this screen does.
//

import UIKit

final class NextStopViewController: UIViewController {

    // MARK: Seams — every outside edge, with its production default

    /// The durable shop stop.
    var loadState: () -> NextStopState = { NextStopCoordinator.state() }
    /// Throwing on purpose: a shop stop that did not reach disk is not a shop
    /// stop, and the screen must not pretend otherwise.
    var persistState: (NextStopState) throws -> Void = { try NextStopCoordinator.save($0) }

    /// The tenant's active stores: what this phone already holds, then an
    /// opportunistic refresh.
    var cachedStores: () -> [StoreModel] = { getStoreListData() }
    var refreshStores: (@escaping ([StoreModel]) -> Void) -> Void = { done in getStoreList(completion: done) }

    /// Navigation to an address.
    var openMap: (String, @escaping (Bool) -> Void) -> Void = { address, done in
        openAddressInMap(address: address, completion: done)
    }

    /// Dispatch's remaining workload and how to enter one of its missions.
    var missions: () -> [NextStopMission] = { [] }
    var missionSourceState: () -> MissionSourceState = { .available }
    var openOrderMission: (String) -> Bool = { _ in false }
    var openManualMission: (String) -> Bool = { _ in false }
    var refreshDispatch: () -> Void = {}

    var now: () -> Date = Date.init

    /// The mission whose completion opened this screen — where the driver is
    /// standing. nil when it was opened some other way.
    var completedMission: NextStopPlace?

    /// Hands one answer to the Sync Engine (best-effort; see NextStopCoordinator.record).
    var recordRouteEvent: (NextStopRouteEvent?) -> Void = { NextStopCoordinator.record($0) }

    // MARK: Rendered state (read by the UI and by the tests)

    private(set) var state: NextStopState = .idle
    private(set) var shopChoices: [NextStopShop] = []
    private(set) var isShowingShopList = false

    /// Where the driver is, from what they did on THIS screen — kept for the
    /// whole session (the shop stop itself ends when a mission opens, but a
    /// driver who backs out and picks again is still standing in the same
    /// place). A shop stop loaded from disk was set before the job just
    /// completed, so it is not where the driver is: answers then start from
    /// that job.
    private(set) var reachedShop: NextStopShop?
    /// A shop chosen on this screen and not reached yet.
    private(set) var headingToShopId: String?

    /// Where this screen's answers start from.
    var answerOrigin: NextStopPlace? {
        if let shop = reachedShop { return .shop(storeUniqueId: shop.uniqueId) }
        if completedMission == nil, case let .arrivedAtShop(shop, _, _) = state { return .shop(storeUniqueId: shop.uniqueId) }
        return completedMission
    }

    let headlineText = "What are you doing next?"

    /// The forward choices, which depend on where the driver is in a shop stop.
    var primaryChoiceTitles: [String] {
        switch state {
        case .idle, .shopSelected:
            return isShowingShopList ? ["Next Customer / Mission"] : ["Next Customer / Mission", "Return to Shop"]
        case .arrivedAtShop:
            return ["Choose Next Mission"]
        }
    }

    /// What the driver is currently doing, when a shop stop is open.
    var currentDestinationText: String? {
        switch state {
        case .idle:                       return nil
        case let .shopSelected(shop, _):  return "Heading to \(shop.name)"
        case let .arrivedAtShop(shop, _, _): return "At \(shop.name)"
        }
    }

    /// The arrival action, named after the shop so the driver confirms the right one.
    var arrivedActionTitle: String? {
        guard case let .shopSelected(shop, _) = state else { return nil }
        return "Arrived at \(shop.name)"
    }

    /// Shown instead of a shop list when this phone has never downloaded one.
    /// Factual: an empty cache is not "you have no shops".
    var shopUnavailableText: String? {
        guard isShowingShopList, shopChoices.isEmpty else { return nil }
        return "Your shops have not been downloaded to this phone yet. Connect once to load them."
    }

    // MARK: UI

    private let stack = UIStackView()
    private let headline = UILabel()
    private let destination = UILabel()
    private let unavailable = UILabel()
    private let choices = UIStackView()
    private let shopList = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Next Stop"
        view.backgroundColor = .systemBackground
        buildLayout()
        refreshFromDurableState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from Maps or from a backgrounded app: the durable state is
        // the truth, not whatever this screen last rendered.
        refreshFromDurableState()
    }

    /// Re-reads the shop stop and redraws. Safe to call repeatedly.
    func refreshFromDurableState() {
        state = loadState()
        if state.shop != nil { isShowingShopList = false }
        render()
    }

    // MARK: Actions

    @objc func nextCustomerTapped() {
        let picker = NextMissionPickerViewController()
        picker.missions = missions
        picker.sourceState = missionSourceState
        picker.openOrderMission = openOrderMission
        picker.openManualMission = openManualMission
        picker.refreshDispatch = refreshDispatch
        // Recorded BEFORE the shop stop ends: where the driver is choosing from
        // depends on it.
        picker.missionChosen = { [weak self] mission in self?.recordNextMission(mission) }
        // Choosing a real mission ends the shop stop — the mission is the next
        // stop now, and it carries no Next Stop state of its own.
        picker.clearShopStop = { [weak self] in
            // Best-effort: the driver is already moving on to a real mission, so
            // a failed delete must never block them. The stale shop stop is
            // harmless — the next mission is the destination now.
            try? self?.persistState(NextStopTransition.finishShopStop(self?.state ?? .idle))
            self?.state = .idle
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc func returnToShopTapped() {
        isShowingShopList = true
        shopChoices = NextStopViewController.shops(from: cachedStores())
        render()

        // Opportunistic refresh. It may replace the list, but an empty or failed
        // refresh must never blank the list the driver is already looking at.
        refreshStores { [weak self] stores in
            guard let self = self else { return }
            let fresh = NextStopViewController.shops(from: stores)
            guard !fresh.isEmpty else { return }
            self.shopChoices = fresh
            self.render()
        }
    }

    /// The driver picked a shop. Durable FIRST, then navigation.
    func selectShop(at index: Int) {
        guard index >= 0, index < shopChoices.count else { return }
        let shop = shopChoices[index]

        let at = now()
        let chosen = NextStopTransition.selectShop(shop, at: at)
        // Durable FIRST. If the write cannot land there is no destination to
        // show and nowhere to send the driver, so nothing advances.
        do {
            try persistState(chosen)
        } catch {
            showAlertMessage(strMessage: str.somethingWentWrong)
            return
        }

        state = chosen
        isShowingShopList = false
        render()

        // Leaving for the shop from where the driver is. Picking the SAME shop
        // again only reopens Maps (there is no other way back to navigation)
        // and is not a new answer; a different shop is a change of plan.
        if headingToShopId != shop.uniqueId {
            recordRouteEvent(.returnToShop(from: answerOrigin, shopUniqueId: shop.uniqueId, at: at))
        }
        headingToShopId = shop.uniqueId

        guard !shop.fullAddress.isEmpty else { return }
        openMap(shop.fullAddress) { _ in
            // Whether Maps opened or not, the shop stop stands — it is on disk.
        }
    }

    @objc func arrivedTapped() {
        let at = now()
        let arrived = NextStopTransition.arrive(state, at: at)
        guard arrived != state else { return }
        // An arrival nobody recorded is not an arrival: leave the driver
        // heading there, with the action still available to retry.
        do {
            try persistState(arrived)
        } catch {
            showAlertMessage(strMessage: str.somethingWentWrong)
            return
        }
        state = arrived
        if let shop = arrived.shop {
            reachedShop = shop
            headingToShopId = nil
        }
        render()

        if let shop = arrived.shop {
            recordRouteEvent(.arrivedAtShop(shopUniqueId: shop.uniqueId, at: at))
        }
    }

    /// "Next Customer / Mission": the mission the driver actually opened, and
    /// where they chose it from — the shop they reached on this screen, else
    /// the mission they just completed.
    func recordNextMission(_ mission: NextStopMission) {
        let from = answerOrigin
        // Chose a mission on the way, before reaching the shop they picked here.
        let headingToShop = headingToShopId != nil && reachedShop == nil

        let to: NextStopPlace
        switch mission.identity {
        case let .orderProduct(uid): to = .orderLeg(orderProductUniqueId: uid, isReturn: mission.isReturnLeg)
        case let .manualTask(uid):   to = .manualTask(uniqueId: uid)
        }
        recordRouteEvent(.nextMission(from: from, to: to, headingToShop: headingToShop, at: now()))
    }

    // MARK: Store mapping

    /// A tenant store as a shop. `address` is the server's full_address; when a
    /// cached row predates that, the address is composed from its parts rather
    /// than left blank.
    static func shops(from stores: [StoreModel]) -> [NextStopShop] {
        return stores.compactMap { store in
            let name = (store.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let composed = [store.address, store.city, store.state, store.zip_code]
                .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
            let address = (store.fullAddress?.isEmpty == false) ? store.fullAddress! : composed
            return NextStopShop(uniqueId: store.unique_id ?? name,
                                name: name,
                                fullAddress: address)
        }
    }

    // MARK: Layout

    private func buildLayout() {
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        headline.text = headlineText
        headline.font = .systemFont(ofSize: 24, weight: .bold)
        headline.numberOfLines = 0
        headline.textAlignment = .center

        destination.font = .systemFont(ofSize: 16, weight: .semibold)
        destination.textColor = .secondaryLabel
        destination.numberOfLines = 0
        destination.textAlignment = .center

        unavailable.font = .systemFont(ofSize: 14)
        unavailable.textColor = .secondaryLabel
        unavailable.numberOfLines = 0
        unavailable.textAlignment = .center

        choices.axis = .vertical
        choices.spacing = 12
        shopList.axis = .vertical
        shopList.spacing = 10

        [headline, destination, unavailable, choices, shopList].forEach { stack.addArrangedSubview($0) }
    }

    private func render() {
        guard isViewLoaded else { return }

        destination.text = currentDestinationText
        destination.isHidden = currentDestinationText == nil
        unavailable.text = shopUnavailableText
        unavailable.isHidden = shopUnavailableText == nil

        choices.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let arrived = arrivedActionTitle {
            choices.addArrangedSubview(button(arrived, filled: true, action: #selector(arrivedTapped)))
        }
        for title in primaryChoiceTitles {
            let isShop = title == "Return to Shop"
            choices.addArrangedSubview(button(title,
                                              filled: !isShop && arrivedActionTitle == nil,
                                              action: isShop ? #selector(returnToShopTapped) : #selector(nextCustomerTapped)))
        }

        shopList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        shopList.isHidden = !isShowingShopList || shopChoices.isEmpty
        for (i, shop) in shopChoices.enumerated() {
            let b = button(shop.name, filled: false, action: #selector(shopTapped(_:)))
            b.tag = i
            shopList.addArrangedSubview(b)
        }
    }

    @objc private func shopTapped(_ sender: UIButton) {
        selectShop(at: sender.tag)
    }

    private func button(_ title: String, filled: Bool, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.titleLabel?.numberOfLines = 0
        b.backgroundColor = filled ? (UIColor.secondaryView ?? .systemBlue) : .clear
        b.setTitleColor(filled ? .white : (UIColor.secondaryView ?? .systemBlue), for: .normal)
        b.layer.cornerRadius = 10
        b.layer.borderWidth = filled ? 0 : 1
        b.layer.borderColor = (UIColor.secondaryView ?? .systemBlue).cgColor
        b.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }
}
