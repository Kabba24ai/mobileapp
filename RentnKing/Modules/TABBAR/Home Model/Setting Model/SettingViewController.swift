//
//  SettingViewController.swift
//  Kabba Extension
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit

class SettingViewController: UIViewController, UIGestureRecognizerDelegate, NavigationDelegate {
    func selectSearch() {
        
    }
    @IBOutlet weak var lblName : UILabel!
    @IBOutlet weak var lblEmail : UILabel!

    @IBOutlet weak var viewLogOut : UIView!
    @IBOutlet weak var btnLogOut : UIButton!
    @IBOutlet weak var con_Button: NSLayoutConstraint!

    /// About / release-notes section (built once, below the email).
    private let aboutStack = UIStackView()

    /// Release data now lives in the AppReleaseInfo model object.
    private var releases: [AppRelease] { AppReleaseInfo.all }

    //SET NAVIGATION BAR
    @IBOutlet weak var con_NavigationBar : NSLayoutConstraint!
    @IBOutlet private weak var viewNavigation: NavigationBar!{
        didSet{
            viewNavigation.setSearchButton(isHidden: false)
            viewNavigation.delegate = self
        }
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
        self.con_NavigationBar.constant = GlobalMainConstants.NavigationHeight
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = false
        
        //SET THE VIEW
        self.setTheView()
    }
    
   
    
    
    //SET THE VIEW
    func setTheView() {
        
        //SET COLLECTION HEIGHT
        self.con_Button.constant = manageWidth(size: 330)
        
        //SET FONT
        if let objUser = UserDefaults.standard.user{
            self.lblName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 22.0, text: objUser.full_name ?? "")
            self.lblEmail.configureLable(textColor: .gray.withAlphaComponent(0.8), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: objUser.email ?? "")
        }
        
//        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter email")
//        self.txtPassword.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter password")
        
        
        self.btnLogOut.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Log Out")
        
        
        //SET VIEW
        self.viewLogOut.backgroundColor = .clear
        self.viewLogOut.viewBorderCorneRadius(borderColour: .secondary)
        self.viewLogOut.viewCorneRadius(radius: 0, isRound: true)

        //SET ABOUT / RELEASE NOTES SECTION
        self.setupAboutSection()
    }

    /// Builds the About block: Version, Release Date, Release Notes list, Full Archive.
    func setupAboutSection() {
        guard aboutStack.superview == nil else { return }   // build once

        let bold = GlobalMainConstants.APP_FONT_Roboto_Bold
        let regular = GlobalMainConstants.APP_FONT_Roboto_Regular
        let cyan = UIColor.secondary
        let grayValue = UIColor.gray.withAlphaComponent(0.9)

        // "Label:  value" — cyan label + gray value.
        func keyValue(_ label: String, _ value: String) -> UILabel {
            let l = UILabel(); l.numberOfLines = 0
            let s = NSMutableAttributedString(string: label,
                    attributes: [.foregroundColor: cyan, .font: SetTheFont(fontName: bold, size: 17)])
            s.append(NSAttributedString(string: value,
                    attributes: [.foregroundColor: grayValue, .font: SetTheFont(fontName: regular, size: 16)]))
            l.attributedText = s
            return l
        }

        let latest = AppReleaseInfo.latest
        let versionLabel = keyValue("Version:  ", AppReleaseInfo.versionDisplay)
        let releaseDateLabel = keyValue("Release Date:  ", latest?.date ?? "")

        let notesHeader = UILabel()
        notesHeader.attributedText = NSAttributedString(string: "Release Notes",
                attributes: [.foregroundColor: cyan, .font: SetTheFont(fontName: bold, size: 18)])

        let notesLabel = UILabel()
        notesLabel.numberOfLines = 0
        let notesPara = NSMutableParagraphStyle(); notesPara.lineSpacing = 6
        notesLabel.attributedText = NSAttributedString(
            string: (latest?.notes ?? []).map { "~ \($0)" }.joined(separator: "\n"),
            attributes: [.foregroundColor: grayValue, .font: SetTheFont(fontName: regular, size: 16),
                         .paragraphStyle: notesPara])

        let fullArchive = UIButton(type: .system)
        fullArchive.setTitle("Full Archive", for: .normal)
        fullArchive.titleLabel?.font = SetTheFont(fontName: bold, size: 16)
        fullArchive.setTitleColor(cyan, for: .normal)
        fullArchive.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        fullArchive.layer.cornerRadius = 8
        fullArchive.layer.borderWidth = 1.5
        fullArchive.layer.borderColor = cyan.cgColor
        fullArchive.addTarget(self, action: #selector(btnFullArchiveClicked), for: .touchUpInside)

        aboutStack.axis = .vertical
        aboutStack.alignment = .leading
        aboutStack.spacing = 16
        aboutStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(aboutStack)

        aboutStack.addArrangedSubview(versionLabel)
        aboutStack.addArrangedSubview(releaseDateLabel)

        // Sync status (Phase 2): what is still on this phone waiting for Kabba, and the
        // diagnostics screen (Retry / Discard / Sync Now, ids for support).
        let syncSummary = SyncStatusSummaryView(theme: .kabba)
        syncSummary.onTap = { [weak self] in
            self?.navigationController?.pushViewController(SyncStatusViewController(theme: .kabba), animated: true)
        }
        aboutStack.addArrangedSubview(syncSummary)

        aboutStack.addArrangedSubview(notesHeader)
        aboutStack.addArrangedSubview(notesLabel)
//        aboutStack.addArrangedSubview(fullArchive)
        aboutStack.setCustomSpacing(24, after: releaseDateLabel)
        aboutStack.setCustomSpacing(10, after: notesHeader)

        NSLayoutConstraint.activate([
            aboutStack.topAnchor.constraint(equalTo: lblEmail.bottomAnchor, constant: 28),
            aboutStack.leadingAnchor.constraint(equalTo: lblName.leadingAnchor),
            aboutStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
        ])
    }

    @objc func btnFullArchiveClicked() {
        // Present every past release (version, date, notes) in a scrollable dark sheet.
        let archive = ReleaseArchiveViewController()
        archive.entries = releases.map { ($0.version, $0.date, $0.notes) }
        archive.modalPresentationStyle = .overFullScreen
        archive.modalTransitionStyle = .crossDissolve
        self.present(archive, animated: true)
    }
}


//MARK: - BUTTON ACTION
extension SettingViewController{
    @IBAction func btnLogOutClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.showLogoutAlert()
    }
    
    
    func showLogoutAlert() {
        let alert = UIAlertController(
            title: "Logout",
            message: "Are you sure you want to log out?",
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        let logoutAction = UIAlertAction(title: "Logout", style: .destructive) { _ in
            self.LogOutUser()
        }

        alert.addAction(cancelAction)
        alert.addAction(logoutAction)

        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }
    
    
    func LogOutUser()  {
        RemoveAllDataLogout()
        
        //NVIGATE WELCOME SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LoginViewController") as? LoginViewController{
            /* Initiating instance of ui-navigation-controller with view-controller */
            let navigationController = UINavigationController()
            navigationController.viewControllers = [newViewController]
            GlobalMainConstants.appDelegate?.window?.rootViewController = navigationController
            GlobalMainConstants.appDelegate?.window?.makeKeyAndVisible()
        }
    }
    
    func RemoveAllDataLogout() {
        // Phase 5: revoke THIS device's session on the server (fire-and-forget — the local
        // sign-out never waits for it). Other devices of the same employee stay signed in.
        KabbaSession.revokeCurrentOnServer()

        // Sync Engine: stop sending; stored operations stay on the phone for the next session.
        KabbaSync.sessionDidEnd()

        //REMOVE ALL DATA
        UserDefaults.standard.user = nil
        UserDefaults.standard.accessToken = nil          // clears the shared Keychain item (extension included)
        
        //SAVE OBJECT
        UserDefaults.standard.baseURL = ""
        
        //SET DATA TO EXTENSION
        defaultsToExtension?.set("", forKey: "api_url")
        defaultsToExtension?.removeObject(forKey: "auth_token")
        defaultsToExtension?.synchronize()
    }

}


// MARK: - Release Archive (all past versions + notes)

final class ReleaseArchiveViewController: UIViewController {

    /// (version, date, notes) — newest first.
    var entries: [(version: String, date: String, notes: [String])] = []

    private let bold = GlobalMainConstants.APP_FONT_Roboto_Bold
    private let regular = GlobalMainConstants.APP_FONT_Roboto_Regular

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)

        let cyan = UIColor.secondary
        let grayValue = UIColor.gray.withAlphaComponent(0.9)

        // Card
        let card = UIView()
        card.backgroundColor = .background
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = cyan.withAlphaComponent(0.35).cgColor
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        // Header row: title + close
        let title = UILabel()
        title.attributedText = NSAttributedString(string: "Release Archive",
                attributes: [.foregroundColor: cyan, .font: SetTheFont(fontName: bold, size: 19)])

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = grayValue
        close.setContentHuggingPriority(.required, for: .horizontal)
        close.widthAnchor.constraint(equalToConstant: 26).isActive = true
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [title, UIView(), close])
        headerRow.axis = .horizontal
        headerRow.alignment = .center

        // Scrollable list of releases
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 22
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        for entry in entries {
            contentStack.addArrangedSubview(releaseBlock(entry, cyan: cyan, grayValue: grayValue))
        }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.addSubview(contentStack)

        let outer = UIStackView(arrangedSubviews: [headerRow, scroll])
        outer.axis = .vertical
        outer.spacing = 16
        outer.isLayoutMarginsRelativeArrangement = true
        outer.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        outer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(outer)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),

            outer.topAnchor.constraint(equalTo: card.topAnchor),
            outer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
    }

    private func releaseBlock(_ entry: (version: String, date: String, notes: [String]),
                              cyan: UIColor, grayValue: UIColor) -> UIView {
        let head = UILabel()
        head.numberOfLines = 0
        let s = NSMutableAttributedString(string: "Version \(entry.version)",
                attributes: [.foregroundColor: cyan, .font: SetTheFont(fontName: bold, size: 17)])
        s.append(NSAttributedString(string: "   \(entry.date)",
                attributes: [.foregroundColor: grayValue, .font: SetTheFont(fontName: regular, size: 14)]))
        head.attributedText = s

        let notes = UILabel()
        notes.numberOfLines = 0
        let para = NSMutableParagraphStyle(); para.lineSpacing = 6
        notes.attributedText = NSAttributedString(
            string: entry.notes.map { "~ \($0)" }.joined(separator: "\n"),
            attributes: [.foregroundColor: grayValue, .font: SetTheFont(fontName: regular, size: 15),
                         .paragraphStyle: para])

        let block = UIStackView(arrangedSubviews: [head, notes])
        block.axis = .vertical
        block.spacing = 8
        return block
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}
