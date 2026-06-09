//
//  DispatchListViewController.swift
//  RentnKing
//
//  Dispatch shows Deliveries + Returns combined for a driver, sorted by priority.
//  Differences from Schedule: no Delivery/Return toggle; combined list; Start/End point;
//  priority-based sort; Today/Tomorrow/All date chips; admin PIN to see all drivers.
//

import UIKit
import MessageUI

class DispatchListViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - Outlets

    @IBOutlet weak var tblView: UITableView!

    // Date filter chips
    @IBOutlet weak var btnToday: UIButton!
    @IBOutlet weak var btnTomorrow: UIButton!
    @IBOutlet weak var btnAll: UIButton!

    // Transport mode checkboxes
    @IBOutlet weak var imgCheckTruck: UIImageView!
    @IBOutlet weak var imgCheckStore: UIImageView!

    @IBOutlet var emptyDataView: EmptyDataView! {
        didSet {
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }

    @IBOutlet weak var objSearchIndicator: UIActivityIndicatorView!

    // MARK: - State

    var arrDispatchJobs: [DispatchJobModel] = []
    var isLoading = true
    var bool_Load = false
    var pageCount = 1
    var objRefresh: UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!

    // Filters
    var selectedDateFilter = "Today"   // "Today", "Tomorrow", "All"
    var isTruckSelected = true
    var isStoreSelected = false        // Dispatch is Truck-only by default per web spec

    // Admin PIN: when true shows all drivers; when false shows only self
    var isPinnedAdminView = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupRefreshControl()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigation()
        refreshList()
    }

    // MARK: - Navigation

    func setNavigation() {
        let pinIcon = isPinnedAdminView ? "icon_pin_active" : "icon_pin"
        setNavigationBarForButtons(
            controller: self,
            title: "Dispatch",
            isTransperent: true,
            hideShadowImage: true,
            leftIcon: "icon_back",
            rightIcon: [pinIcon],
            isFilter: false
        ) {
            self.navigationController?.popViewController(animated: true)
        } rightActionHandler: { sender, tag in
            // PIN toggle — lets admin see all drivers vs own jobs
            self.isPinnedAdminView.toggle()
            self.setNavigation()
            self.refreshList()
        }
    }

    // MARK: - Refresh / Load

    func setupRefreshControl() {
        objRefresh = UIRefreshControl()
        objRefresh?.tintColor = .primary
        objRefresh?.addTarget(self, action: #selector(refreshList), for: .valueChanged)
        tblView.addSubview(objRefresh!)
    }

    @objc func refreshList() {
        pageCount = 1
        bool_Load = true
        arrDispatchJobs = []
        tblView.reloadData()

        // Show cached data immediately
        let local = getLocalDispatchJobs(dateFilter: selectedDateFilter)
        if !local.isEmpty {
            arrDispatchJobs = local
            setTheView()
        }

        if NetworkReachabilityManager()!.isReachable {
            fetchDispatch()
        }
    }

    func fetchDispatch() {
        isLoading = true
        let params = DispatchListParameter(
            date_filter: selectedDateFilter,
            driver_id: isPinnedAdminView ? nil : nil   // nil = server defaults to self
        )

        callAPIforGetDispatchList(params: params) { [weak self] saved in
            guard let self = self else { return }
            isLoading = false
            stopAnimatingView()
            objRefresh?.endRefreshing()

            if saved {
                arrDispatchJobs = getLocalDispatchJobs(dateFilter: selectedDateFilter)
            } else {
                arrDispatchJobs = []
            }

            DispatchQueue.main.async { self.setTheView() }
        }
    }

    // MARK: - View State

    func setTheView() {
        objSearchIndicator?.isHidden = true
        objSearchIndicator?.stopAnimating()
        updateDateFilterUI()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.stopLoading()
            self.isLoading = false
            self.emptyDataView.isHidden = !self.arrDispatchJobs.isEmpty
            self.tblView.reloadData()
        }
    }

    func updateDateFilterUI() {
        let filters = ["Today": btnToday, "Tomorrow": btnTomorrow, "All": btnAll]
        filters.forEach { key, btn in
            let active = selectedDateFilter == key
            btn?.backgroundColor      = active ? .secondary : .clear
            btn?.setTitleColor(active ? .background : .primary, for: .normal)
            btn?.layer.cornerRadius   = 12
            btn?.layer.borderWidth    = 1
            btn?.layer.borderColor    = UIColor.secondary.cgColor
        }
        imgCheckTruck?.image = UIImage(named: isTruckSelected ? "icon_Check" : "icon_unCheck")
        imgCheckStore?.image = UIImage(named: isStoreSelected ? "icon_Check" : "icon_unCheck")
    }

    func stopLoading() {
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { }
    }
}

// MARK: - Button Actions

extension DispatchListViewController {

    @IBAction func btnTodayClicked(_ sender: UIButton) {
        guard selectedDateFilter != "Today" else { return }
        selectedDateFilter = "Today"
        refreshList()
    }

    @IBAction func btnTomorrowClicked(_ sender: UIButton) {
        guard selectedDateFilter != "Tomorrow" else { return }
        selectedDateFilter = "Tomorrow"
        refreshList()
    }

    @IBAction func btnAllClicked(_ sender: UIButton) {
        guard selectedDateFilter != "All" else { return }
        selectedDateFilter = "All"
        refreshList()
    }

    @IBAction func btnTruckCheckClicked(_ sender: UIButton) {
        isTruckSelected.toggle()
        updateDateFilterUI()
        refreshList()
    }

    @IBAction func btnStoreCheckClicked(_ sender: UIButton) {
        isStoreSelected.toggle()
        updateDateFilterUI()
        refreshList()
    }
}

// MARK: - Table View

extension DispatchListViewController: UITableViewDelegate, UITableViewDataSource, MFMessageComposeViewControllerDelegate, OrderDetailsDelegate {

    func setupTableView() {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tblView.frame.size.width, height: 40))
        _loadingView = UIActivityIndicatorView(style: .medium)
        _loadingView.color = .primary
        _loadingView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        _loadingView.center = CGPoint(x: footer.frame.size.width / 2, y: 15)
        _loadingView.isHidden = true
        footer.addSubview(_loadingView)
        tblView.tableFooterView = footer
    }

    func startAnimatingView() {
        _loadingView.center = CGPoint(x: tblView.frame.size.width / 2, y: _loadingView.center.y)
        _loadingView.startAnimating()
        _loadingView.isHidden = false
    }

    func stopAnimatingView() {
        _loadingView.stopAnimating()
        _loadingView.isHidden = true
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isLoading ? 5 : arrDispatchJobs.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "DispatchListCell") as? DispatchListCell else {
            return UITableViewCell()
        }

        cell.backgroundColor = .clear

        if isLoading {
            return cell
        }

        let job = arrDispatchJobs[indexPath.row]

        // Priority badge
        if let p = job.priority {
            cell.lblPriority.text = "\(p)"
            cell.lblPriority.isHidden = false
        } else {
            cell.lblPriority.isHidden = true
        }

        // Type badge — Delivery (blue) / Return (purple)
        let isDelivery = job.isDelivery
        cell.lblType.text = isDelivery ? "Delivery" : "Return"
        cell.lblType.backgroundColor = isDelivery ? UIColor(hex: "#007AFF")?.withAlphaComponent(0.15)
                                                   : UIColor(hex: "#9B59B6")?.withAlphaComponent(0.15)
        cell.lblType.textColor = isDelivery ? UIColor(hex: "#007AFF") : UIColor(hex: "#9B59B6")

        // Date / time
        cell.lblDateTime.configureLable(
            textColor: .primary.withAlphaComponent(0.6),
            fontName: GlobalMainConstants.APP_FONT_Roboto_Bold,
            fontSize: 14,
            text: "\(job.date ?? "") \(job.time ?? "")"
        )

        // Customer
        cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: job.customer_name ?? "")
        cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: job.customer_phone ?? "")
        imgColor(imgColor: cell.imgCall, colorHex: .secondary)

        // Equipment
        cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: job.equipment_name ?? job.product_name ?? "")

        // Address
        imgColor(imgColor: cell.imgMapAddress, colorHex: .secondary)
        cell.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: job.address ?? "")

        // Start / End point
        if isDelivery, let sp = job.start_point {
            cell.lblPoint.text = "Start: \(sp)"
            cell.lblPoint.isHidden = false
        } else if !isDelivery, let ep = job.end_point {
            cell.lblPoint.text = "End: \(ep)"
            cell.lblPoint.isHidden = false
        } else {
            cell.lblPoint.isHidden = true
        }

        // Complete button
        cell.btnUpdateOrder.tag = indexPath.row
        cell.btnUpdateOrder.addTarget(self, action: #selector(btnUpdateOrderClicked(_:)), for: .touchUpInside)

        cell.btnCall.tag = indexPath.row
        cell.btnCall.addTarget(self, action: #selector(btnCallClicked(_:)), for: .touchUpInside)

        cell.btnAddress.tag = indexPath.row
        cell.btnAddress.addTarget(self, action: #selector(btnMapClicked(_:)), for: .touchUpInside)

        cell.layoutIfNeeded()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !arrDispatchJobs.isEmpty else { return }
        let job = arrDispatchJobs[indexPath.row]

        let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let vc = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController {
            vc.delegate = self
            vc.selectIndex = indexPath.row
            vc.strOrderUniqueId = job.order_unique_id ?? ""
            vc.strOrderID = job.order_number ?? ""
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    func updateOrderDetails(selectIndex: Int, objOrderData: OrdersListModel) {}

    // MARK: - Row Actions

    @objc func btnUpdateOrderClicked(_ sender: UIButton) {
        guard arrDispatchJobs.indices.contains(sender.tag) else { return }
        let job = arrDispatchJobs[sender.tag]
        let typeLabel = job.isDelivery ? "delivered" : "picked up"
        let scheduleType = job.isDelivery ? "Delivery" : "Return"

        let alert = UIAlertController(
            title: Application.appName,
            message: "Are you sure you have \(typeLabel) '\(job.product_name ?? "")' for \(job.customer_name ?? "")?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: str.yes, style: .default) { _ in
            self.updateDispatchStatus(
                params: DispatchUpdateStatusParameter(
                    order_product_unique_id: job.unique_id ?? "",
                    schedule_type: scheduleType,
                    schedule_status: "Completed"
                ),
                index: sender.tag
            )
        })
        alert.addAction(UIAlertAction(title: str.no, style: .cancel))
        present(alert, animated: true)
    }

    @objc func btnCallClicked(_ sender: UIButton) {
        guard arrDispatchJobs.indices.contains(sender.tag) else { return }
        let job = arrDispatchJobs[sender.tag]
        var number = (job.customer_phone ?? "").replacingOccurrences(of: "+1", with: "")

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Call \(number)", style: .default) { _ in
            guard let url = URL(string: "tel://+1\(number)") else { return }
            UIApplication.shared.open(url)
        })
        sheet.addAction(UIAlertAction(title: "Send Message", style: .default) { _ in
            guard MFMessageComposeViewController.canSendText() else { return }
            let sms = MFMessageComposeViewController()
            sms.recipients = ["+1\(number)"]
            sms.messageComposeDelegate = self
            self.present(sms, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let presenter = sheet.popoverPresentationController {
            presenter.sourceView = sender
            presenter.sourceRect = sender.frame
        }
        present(sheet, animated: true)
    }

    @objc func btnMapClicked(_ sender: UIButton) {
        guard arrDispatchJobs.indices.contains(sender.tag) else { return }
        let job = arrDispatchJobs[sender.tag]
        openAddressInMap(address: job.address_full ?? job.address ?? "")
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        dismiss(animated: true)
    }
}

// MARK: - Cell

class DispatchListCell: UITableViewCell {
    @IBOutlet weak var lblPriority: UILabel!      // circular priority badge
    @IBOutlet weak var lblType: UILabel!          // "Delivery" / "Return" badge
    @IBOutlet weak var lblDateTime: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var imgMapAddress: UIImageView!
    @IBOutlet weak var lblPoint: UILabel!         // "Start: Store Name" or "End: Store Name"
    @IBOutlet weak var btnCall: UIButton!
    @IBOutlet weak var btnAddress: UIButton!
    @IBOutlet weak var btnUpdateOrder: UIButton!
    @IBOutlet weak var viewLine: UIView!
}
