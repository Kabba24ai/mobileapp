//
//  NextMissionPickerViewController.swift
//  RentnKing — Dispatch / Next Stop (2026-10-18)
//
//  The driver's remaining workday, offered as the next stop: Delivery, Return
//  and Manual Dispatch together, in the Dispatch board's own order.
//
//  It holds no Dispatch truth. The rows are a projection handed in from
//  DispatchListViewController, and selection hands an IDENTITY back for that
//  controller to re-resolve. So a mission that completed or was reassigned
//  while this screen sat open is refused by the owner of the truth, and the
//  driver is told plainly instead of being routed into somebody else's job.
//
//  An empty list is not one message but two: a genuinely finished day, and a
//  workload this phone has not downloaded. Collapsing those would tell a driver
//  with no signal that they were done.
//

import UIKit

/// Whether the remaining-work source could be read at all.
enum MissionSourceState: Equatable {
    /// Live or cached work is available (even if there happens to be none left).
    case available
    /// Offline and this phone holds no cached workload — unknown, not empty.
    case notDownloaded
}

final class NextMissionPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: Seams

    var missions: () -> [NextStopMission] = { [] }
    var sourceState: () -> MissionSourceState = { .available }

    /// Re-resolve + open, owned by Dispatch. false = that mission is no longer
    /// this driver's work.
    var openOrderMission: (String) -> Bool = { _ in false }
    var openManualMission: (String) -> Bool = { _ in false }

    /// Ends the shop stop, called BEFORE routing into a real mission.
    var clearShopStop: () -> Void = {}
    var refreshDispatch: () -> Void = {}

    // MARK: Rendered state

    private(set) var rows: [NextStopMission] = []
    private(set) var noticeText: String?

    var renderedKindLabels: [String] { rows.map(\.kindLabel) }
    var renderedPrimaryTexts: [String] { rows.map(\.primaryText) }

    /// What to say when there is nothing to show — and the two cases stay apart.
    var emptyText: String? {
        guard rows.isEmpty else { return nil }
        switch sourceState() {
        case .available:
            return "No remaining missions. You're done for now."
        case .notDownloaded:
            return "Your remaining work has not been downloaded to this phone. Connect once to load it."
        }
    }

    private let table = UITableView()
    private let empty = UILabel()
    private let notice = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Next Customer / Mission"
        view.backgroundColor = .systemBackground
        buildLayout()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    /// Re-projects the current workload.
    func reload() {
        rows = missions()
        guard isViewLoaded else { return }
        table.reloadData()
        empty.text = emptyText
        empty.isHidden = emptyText == nil
        notice.text = noticeText
        notice.isHidden = noticeText == nil
    }

    /// The driver picked a mission. Dispatch re-resolves the identity and opens it
    /// FIRST; only a mission that actually opened becomes the next stop, so only then
    /// does the shop stop end. A refusal means the mission completed or was reassigned
    /// while this screen sat open: the shop stop is left exactly as it was, the driver
    /// is told, Dispatch refreshes, and they choose again.
    func selectMission(at index: Int) {
        guard index >= 0, index < rows.count else { return }
        let mission = rows[index]

        let opened: Bool
        switch mission.identity {
        case let .orderProduct(uid): opened = openOrderMission(uid)
        case let .manualTask(uid):   opened = openManualMission(uid)
        }

        if opened {
            clearShopStop()
            return
        }

        noticeText = "This mission is no longer assigned here. Dispatch has been refreshed."
        refreshDispatch()
        reload()
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "mission") ??
                   UITableViewCell(style: .subtitle, reuseIdentifier: "mission")
        let mission = rows[indexPath.row]
        cell.textLabel?.text = "\(mission.kindLabel) · \(mission.primaryText)"
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cell.detailTextLabel?.text = mission.secondaryText
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectMission(at: indexPath.row)
    }

    // MARK: Layout

    private func buildLayout() {
        notice.font = .systemFont(ofSize: 14, weight: .medium)
        notice.textColor = .systemOrange
        notice.numberOfLines = 0
        notice.textAlignment = .center
        notice.isHidden = true

        empty.font = .systemFont(ofSize: 15)
        empty.textColor = .secondaryLabel
        empty.numberOfLines = 0
        empty.textAlignment = .center
        empty.isHidden = true

        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64

        [notice, empty, table].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            notice.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            notice.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            notice.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            empty.topAnchor.constraint(equalTo: notice.bottomAnchor, constant: 24),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            table.topAnchor.constraint(equalTo: notice.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
