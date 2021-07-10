//
//  ProfileViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import SwiftUI
import UIKit

private extension Localizations {

    static var archive: String {
        NSLocalizedString("profile.row.archive", value: "Archive", comment: "Row in Profile screen.")
    }

    static var inviteFriends: String {
        NSLocalizedString("profile.row.invite", value: "Invite to HalloApp", comment: "Row in Profile screen.")
    }

    static var help: String {
        NSLocalizedString("profile.row.help", value: "Help", comment: "Row in Profile screen.")
    }

    static var about: String {
        NSLocalizedString("profile.row.about", value: "About", comment: "Row in Profile screen.")
    }
    
    static var accountRow: String {
        NSLocalizedString("profile.row.account", value: "Account", comment: "Row in Profile Screen")
    }
    
    static var shareRow: String {
        NSLocalizedString("profile.row.share", value: "Share HalloApp", comment: "Row in Profile Screen.")
    }
    
    static var shareHalloAppString: String {
        NSLocalizedString("settings.share.text", value: "Join me on HalloApp, download for free at halloapp.com/dl", comment: "String to auto-fill if a user tried to share to a friend.")
    }
}

class SettingsViewController: UITableViewController {

    private var cancellables = Set<AnyCancellable>()
    private var headerViewController: ProfileHeaderViewController!

    // MARK: Table View Data Source and Rows

    private enum Section {
        case one
        case two
        case three
    }

    private enum Row {
        case profile
        case feed
        case archive
        case settings
        case notifications
        case privacy
        case invite
        case help
        case about
        case account
        case share
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    private let cellProfile = UITableViewCell()
    private let cellMyPosts = SettingsTableViewCell(text: Localizations.titleMyPosts, image: UIImage(named: "settingsMyPosts"))
    private let cellArchive = SettingsTableViewCell(text: Localizations.archive, image: UIImage(named: "settingsArchive"))
    private let cellSettings = SettingsTableViewCell(text: Localizations.titleSettings, image: UIImage(named: "settingsSettings"))
    private let cellNotifications = SettingsTableViewCell(text: Localizations.titleNotifications, image: UIImage(named: "settingsNotifications"))
    private let cellPrivacy = SettingsTableViewCell(text: Localizations.titlePrivacy, image: UIImage(named: "settingsPrivacy"))
    private let cellInviteFriends = SettingsTableViewCell(text: Localizations.inviteFriends, image: UIImage(named: "settingsInvite"))
    private let cellHelp = SettingsTableViewCell(text: Localizations.help, image: UIImage(named: "settingsHelp"))
    private let cellAbout = SettingsTableViewCell(text: Localizations.about, image: UIImage(named: "settingsAbout"))
    private let cellAccount = SettingsTableViewCell(text: Localizations.accountRow, image: UIImage(named: "settingsAccount"))
    private let cellShare = SettingsTableViewCell(text: Localizations.shareRow, image: UIImage(named: "settingsShare"))

    // MARK: View Controller

    init(title: String) {
        super.init(style: .insetGrouped)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()

        #if DEBUG
        let showDeveloperMenu = true
        #else
        let showDeveloperMenu = ServerProperties.isInternalUser
        #endif
        if showDeveloperMenu {
            let image = UIImage(systemName: "hammer", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(openDeveloperMenu))
        }

        tableView.backgroundColor = .feedBackground
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 10))

        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .profile: return self.cellProfile
            case .feed: return self.cellMyPosts
            case .archive: return self.cellArchive
            case .settings: return self.cellSettings
            case .notifications: return self.cellNotifications
            case .privacy: return self.cellPrivacy
            case .invite: return self.cellInviteFriends
            case .help: return self.cellHelp
            case .about: return self.cellAbout
            case .account: return self.cellAccount
            case .share: return self.cellShare
            }
        })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one, .two, .three ])
        snapshot.appendItems([ .profile, .feed ], toSection: .one)
        snapshot.appendItems([ .account, .notifications, .privacy ], toSection: .two)
        snapshot.appendItems([ .help, .about, .invite, .share ], toSection: .three)
        dataSource.apply(snapshot, animatingDifferences: false)

        headerViewController = ProfileHeaderViewController()
        headerViewController.isEditingAllowed = true
        headerViewController.configureAsHorizontal()
        
        addChild(headerViewController)
        headerViewController.didMove(toParent: self)
        
        cellProfile.contentView.addSubview(headerViewController.view)
        cellProfile.separatorInset = .zero

        headerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        headerViewController.view.constrain(to: cellProfile.contentView)
        
        cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
            guard let self = self else { return }
            self.headerViewController.configureForCurrentUser(withName: userName)
            self.viewIfLoaded?.setNeedsLayout()
        }))
        
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("SettingsViewController/viewWillAppear")
        super.viewWillAppear(animated)

        // This VC pushes SwiftUI views that hide the tab bar and use `navigationBarTitle` to display custom titles.
        // These titles aren't reset when the SwiftUI views are dismissed, so we need to manually update the title
        // here or the tab bar will show the wrong title when it reappears.
        navigationController?.title = title
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update header's height: necessary when user changes text size setting.
        if let headerView = tableView.tableHeaderView {
            var targetSize = UIView.layoutFittingCompressedSize
            targetSize.width = tableView.bounds.width
            let headerViewHeight = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            if headerView.bounds.height != headerViewHeight {
                headerView.bounds.size.height = headerViewHeight
                tableView.tableHeaderView = headerView
            }
        }
    }

    // MARK: Presenting View Controllers

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .profile:
            break
        case .feed:
            openMyFeed()
        case .archive:
            openArchive()
        case .settings:
            openSettings()
        case .notifications:
            openNotifications()
        case .privacy:
            openPrivacy()
        case .invite:
            openInviteFriends()
        case .help:
            openHelp()
        case .about:
            openAbout()
        case .account:
            openAccountSettings()
        case .share: openShareMenu()
        }
    }

    private func openMyFeed() {
        let viewController = UserFeedViewController(userId: MainAppContext.shared.userData.userId)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openArchive() {

    }

    private func openSettings() {
        let viewController = SettingsNotificationsViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openNotifications() {
        let viewController = SettingsNotificationsViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openPrivacy() {
        let viewController = PrivacyViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openInviteFriends() {
        if let indexPath = self.dataSource.indexPath(for: .invite) {
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        present(UINavigationController(rootViewController: inviteVC), animated: true)
    }

    private func openHelp() {
        let viewController = HelpViewController(title: Localizations.help)
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openAbout() {
        if let viewController = UIStoryboard.init(name: "AboutView", bundle: Bundle.main).instantiateInitialViewController() {
            viewController.hidesBottomBarWhenPushed = false
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
    
    private func openAccountSettings() {
        let viewController = SettingsAccountViewController() // UIHostingController(rootView: AccountSettingsList())
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openShareMenu() {
        if let indexPath = self.dataSource.indexPath(for: .share) {
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
        
        let ac = UIActivityViewController(activityItems: [Localizations.shareHalloAppString], applicationActivities: nil)
        present(ac, animated: true)
    }

    @objc private func openDeveloperMenu() {
        var developerMenuView = DeveloperMenuView()
        developerMenuView.dismiss = {
            self.navigationController?.popViewController(animated: true)
        }
        let viewController = UIHostingController(rootView: developerMenuView)
        viewController.hidesBottomBarWhenPushed = true
        viewController.title = "Developer Menu"
        navigationController?.pushViewController(viewController, animated: true)
    }
}
