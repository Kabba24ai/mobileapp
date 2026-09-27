//
//  TermsAndConditionViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 31/01/24.
//

import UIKit
import WebKit
import Alamofire

protocol TermsDelegate : NSObject {
    /// The SERVER recorded the acceptance (the hosted page reached its thank-you step).
    func termsSucess(selectIndex : Int)
    /// Dispatch offline Phase 5: the customer signed on THIS phone (a terms.sign operation). Never an
    /// in-memory "Accepted" — the operation decides, so a signature the server refuses stops counting.
    func termsSignedOnThisPhone(selectIndex : Int)
}


class TermsAndConditionViewController: UIViewController, UIGestureRecognizerDelegate {

    @IBOutlet var objWebKit: WKWebView!

    var signUrl : String = ""
    var isOrderFrom : Bool = false
    var selectIndex : Int = -1
    weak var delegate: TermsDelegate?
    var strOrderUniqueId : String = ""
    // Local-first T&C (order workflow only): the signing page records the
    // acceptance server-side; these ids let the phone keep durable evidence
    // of it too (terms.accept), so a force-quit or stale feed can never
    // resurrect a false "terms missing" exception. The new-order flow
    // (isOrderFrom == false) never enqueues — its server-fresh path stands.
    var strProductUniqueId : String = ""
    var isReturnLeg : Bool = false
    var strOrderNumber : String = ""
    // Dispatch offline Phase 5: the order's terms_status as the calling screen knows it.
    var strTermsStatus : String = ""

    /// Phase 5: what the screen shows (TermsScreenPresentation — one pure decision).
    private(set) var presentation: TermsScreenPresentation?
    /// The VERIFIED agreement the local page is showing (the only one a signing may name).
    private(set) var renderedAgreement: TermsAgreement?
    /// Whether the screen asks the server first (live copy) — injectable for the hosted tests.
    var isReachable: () -> Bool = { NetworkReachabilityManager()?.isReachable == true }
    private var hasResolved = false
    private var isRecording = false
    private var messageProxy: TermsSigningMessageProxy?

    deinit {
        objWebKit?.configuration.userContentController.removeScriptMessageHandler(forName: TermsSigningShell.messageHandlerName)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: "Terms & Conditions", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {
            
          
        }
        
        //SET  VIEW
        self.setTheView()
        
    }
    
    func setTheView(){
        // Dispatch offline Phase 5: the order workflow uses ONE local-first screen, online and
        // offline — the order's frozen agreement, verified, rendered locally, signed locally.
        // The new-order flow (isOrderFrom == false) keeps its server page, unchanged.
        guard self.isOrderFrom, !self.strOrderUniqueId.isEmpty, KabbaSync.termsAgreements != nil else {
            self.setTheHostedView()
            return
        }
        guard !self.hasResolved else { return }  // never reload a page the customer may be signing
        self.hasResolved = true

        if self.isReachable() {
            indicatorShow()
            TermsAgreementClient.fetch(orderUniqueId: self.strOrderUniqueId) { [weak self] live in
                indicatorHide()
                guard let self = self else { return }
                self.apply(TermsScreenPresentation.resolve(self.presentationInputs(live: live)))
            }
        } else {
            self.apply(TermsScreenPresentation.resolve(self.presentationInputs(live: nil)))
        }
    }

    func presentationInputs(live: TermsScreenPresentation.Live?) -> TermsScreenPresentation.Inputs {
        TermsScreenPresentation.Inputs(orderUniqueId: self.strOrderUniqueId,
                                       knownTermsStatus: self.strTermsStatus,
                                       live: live,
                                       stored: KabbaSync.termsAgreements?.current(orderUniqueId: self.strOrderUniqueId),
                                       storedUnavailable: KabbaSync.termsAgreements?.isUnavailable(orderUniqueId: self.strOrderUniqueId) ?? false,
                                       operations: KabbaSync.engine?.snapshot() ?? [],
                                       signUrl: self.signUrl)
    }

    func apply(_ presentation: TermsScreenPresentation) {
        self.presentation = presentation
        self.renderedAgreement = nil
        switch presentation {
        case .document(let agreement):
            self.renderLocal(agreement)
        case .hostedPage(let url):
            self.hideBoundary()
            self.loadHosted(url)
        case .notRequired:
            self.showBoundary { $0.termsNotRequired() }
        case .alreadyAccepted:
            self.showBoundary { $0.termsAlreadyAccepted() }
        case .signedOnThisPhone(let state):
            self.showBoundary { $0.termsSignedOnThisPhone(synced: state == .synced) }
        case .unableToVerify:
            self.showBoundary { $0.termsUnableToVerify() }
        case .agreementUnavailable:
            self.showBoundary { $0.termsAgreementUnavailable() }
        case .notDownloaded:
            self.showBoundary { $0.termsNotDownloaded() }
        case .couldNotLoad:
            self.showBoundary { $0.termsCouldNotLoad() }
        case .unavailable:
            self.showBoundary { $0.termsUnavailable() }
        }
    }

    /// The order's verified frozen agreement, as an inert local page (TermsSigningShell).
    private func renderLocal(_ agreement: TermsAgreement) {
        guard let html = TermsSigningShell.html(for: agreement) else {
            self.showBoundary { $0.termsUnavailable() }
            return
        }
        self.hideBoundary()
        let controller = self.objWebKit.configuration.userContentController
        controller.removeScriptMessageHandler(forName: TermsSigningShell.messageHandlerName)
        let proxy = TermsSigningMessageProxy(target: self)
        controller.add(proxy, name: TermsSigningShell.messageHandlerName)
        self.messageProxy = proxy
        self.renderedAgreement = agreement
        self.objWebKit.navigationDelegate = self
        self.objWebKit.loadHTMLString(html, baseURL: nil)
    }

    /// The page posted a signing. Recorded durably FIRST (terms.sign), then the calling screen
    /// re-evaluates from the engine (no in-memory "Accepted") and the screen pops.
    func didReceiveSigning(_ body: Any) {
        guard !self.isRecording, let agreement = self.renderedAgreement, case .document? = self.presentation else { return }
        guard let message = body as? [String: Any],
              let identity = message["identity"] as? String, identity == agreement.identity,
              let approvals = (message["approvals_confirmed"] as? NSNumber)?.intValue, approvals == agreement.approvalsRequired,
              let dataURL = message["signature"] as? String, let png = Self.signaturePNG(fromDataURL: dataURL) else {
            self.resetPage("The signature couldn't be read. Please sign again.")
            return
        }
        self.isRecording = true
        guard let operationId = KabbaTermsSync.recordSigned(agreement: agreement,
                                                            orderProductUniqueId: self.strProductUniqueId,
                                                            isReturnLeg: self.isReturnLeg,
                                                            approvalsConfirmed: approvals,
                                                            signaturePNG: png) else {
            self.isRecording = false
            self.resetPage("The signature couldn't be saved on this phone. Please try again.")
            return
        }
        KabbaSync.showStatusToast(for: operationId)
        self.delegate?.termsSignedOnThisPhone(selectIndex: self.selectIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.routeAfterSigning()
        }
    }

    /// Sign Terms → Main Order (Driver Delivery Process Flow §10.2): the Order Details that
    /// opened it, whatever lies beneath; a stack without one keeps its old single pop.
    func routeAfterSigning() {
        CustomerSiteNavigation.goToMainOrder(on: self.navigationController)
    }

    /// The pad's PNG data URL → its bytes, or nil when the shared signature contract refuses it
    /// (TermsSignatureImage — form, base64, PNG structure, size, dimensions): nothing the server
    /// would refuse on those grounds is ever recorded. Decoding the image data is the server's
    /// check alone (GD) — ImageIO accepts corrupt PNG data silently, so the phone does not pretend
    /// to; the pad's own output always decodes (TermsSignatureMeasurementHostedTests).
    static func signaturePNG(fromDataURL dataURL: String) -> Data? {
        guard case .success(let png) = TermsSignatureImage.validatedPNG(fromDataURL: dataURL) else { return nil }
        return png
    }

    private func resetPage(_ message: String) {
        guard let json = TermsSigningShell.scriptSafeJSON(["message": message]) else { return }
        self.objWebKit.evaluateJavaScript("window.kabbaTermsReset && window.kabbaTermsReset(\(json).message);", completionHandler: nil)
    }

    private func loadHosted(_ url: URL) {
        indicatorShow()
        self.objWebKit.navigationDelegate = self
        self.objWebKit.load(URLRequest(url: url))
    }

    /// The pre-Phase-5 hosted signing page (the new-order flow, or no agreement store).
    func setTheHostedView(){
        
        //SET WEBVIEW
        switch Self.boundary(reachable: NetworkReachabilityManager()?.isReachable == true, signUrl: self.signUrl) {
        case .load(let url):
            self.hideBoundary()
            indicatorShow()
            
            self.objWebKit.navigationDelegate = self
            let request  = URLRequest(url: url)
            self.objWebKit.load(request)
        case .needsConnection:
            // Dispatch offline Phase 4 (P4-D8): signing happens on the server's page — say so, never a
            // blank web view. T&C stays unmet; the leg completes through the existing override.
            self.showBoundary { $0.termsNeedConnection() }
        case .unavailable:
            self.showBoundary { $0.termsUnavailable() }
        }
        
    }

    // MARK: - Offline boundary (Dispatch offline Phase 4, P4-D8)

    enum Boundary: Equatable {
        case load(URL)
        /// Offline: signing needs a connection (Phase 5 makes it work offline).
        case needsConnection
        /// Online, but the order has no usable signing link (never a force-unwrap crash).
        case unavailable
    }

    static func boundary(reachable: Bool, signUrl: String) -> Boundary {
        guard reachable else { return .needsConnection }
        let trimmed = signUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return .unavailable }
        return .load(url)
    }

    private(set) var boundaryView: EmptyDataView?

    private func showBoundary(_ configure: (EmptyDataView) -> Void) {
        let view = self.boundaryView ?? EmptyDataView(frame: self.view.bounds)
        configure(view)
        view.backgroundColor = .background
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if view.superview == nil { self.view.addSubview(view) }
        self.boundaryView = view
    }

    private func hideBoundary() {
        self.boundaryView?.removeFromSuperview()
        self.boundaryView = nil
    }
}

extension TermsAndConditionViewController:WKNavigationDelegate{
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    {
        indicatorHide()
        guard self.renderedAgreement == nil else { return } // a cancelled navigation on the local page is not an error
        showAlertMessage(strMessage: "\(str.somethingWentWrong)")
    }
    
    
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        indicatorHide()
        
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("dicCommit :")
        
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Phase 5: the local agreement page may load itself and go nowhere else.
        if self.renderedAgreement != nil {
            decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
            return
        }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString.contains("thank-you")
        {

            // Order workflow: the signing page has already recorded the
            // acceptance server-side — make the phone's knowledge of it
            // durable FIRST (engine-first, SyncDriverChecklist pattern), then
            // flip the in-memory state via the existing delegate. When the
            // engine is unavailable the legacy in-session behaviour stands
            // alone, exactly as before.
            var termsOperationId: String? = nil
            if self.isOrderFrom {
                termsOperationId = KabbaTermsSync.recordAccepted(orderUniqueId: self.strOrderUniqueId,
                                                                 orderProductUniqueId: self.strProductUniqueId,
                                                                 isReturnLeg: self.isReturnLeg,
                                                                 orderNumber: self.strOrderNumber)
            }
            if let termsOperationId = termsOperationId {
                KabbaSync.showStatusToast(for: termsOperationId)
            } else {
                showAlertMessage(strMessage: "Terms and conditions updated successfully.")
            }
            if self.isOrderFrom{
                self.delegate?.termsSucess(selectIndex: self.selectIndex)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                if self.isOrderFrom{
                    self.routeAfterSigning()
                }
                else{
                    //TERMS AND CONDITION
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                        newViewController.strOrderUniqueId = self.strOrderUniqueId
                        newViewController.isOrderScreen = true
                        self.navigationController?.pushViewController(newViewController, animated: true)
                    }
                }
            }
            
        }
        
        decisionHandler(.allow)
        
    }
    
}

/// Holds the screen weakly: WKUserContentController retains its handlers.
final class TermsSigningMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: TermsAndConditionViewController?

    init(target: TermsAndConditionViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.didReceiveSigning(message.body)
    }
}
