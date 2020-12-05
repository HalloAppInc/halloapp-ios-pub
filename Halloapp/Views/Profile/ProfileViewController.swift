//
//  ProfileViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import SwiftUI
import UIKit

private extension Localizations {

    static var titleProfile: String {
        NSLocalizedString("title.profile", value: "Profile", comment: "Third tab in the main app interface.")
    }

    static var archive: String {
        NSLocalizedString("profile.row.archive", value: "Archive", comment: "Row in Profile screen.")
    }

    static var inviteFriends: String {
        NSLocalizedString("profile.row.invite", value: "Invite Friends & Family", comment: "Row in Profile screen.")
    }

    static var help: String {
        NSLocalizedString("profile.row.help", value: "Help", comment: "Row in Profile screen.")
    }

    static var about: String {
        NSLocalizedString("profile.row.about", value: "About HalloApp", comment: "Row in Profile screen.")
    }
}

class ProfileViewController: UITableViewController {

    private var cancellables = Set<AnyCancellable>()
    private var headerViewController: ProfileHeaderViewController!

    // MARK: Table View Data Source and Rows

    private enum Section {
        case one
        case two
    }

    private enum Row {
        case feed
        case archive
        case settings
        case invite
        case help
        case about
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    private let cellMyPosts = SettingsTableViewCell(text: Localizations.titleMyPosts, image: UIImage(named: "profile.my.posts"))
    private let cellArchive = SettingsTableViewCell(text: Localizations.archive, image: UIImage(named: "profile.archive"))
    private let cellSettings = SettingsTableViewCell(text: Localizations.titleSettings, image: UIImage(named: "profile.settings"))
    private let cellInviteFriends = SettingsTableViewCell(text: Localizations.inviteFriends, image: UIImage(named: "profile.invite"))
    private let cellHelp = SettingsTableViewCell(text: Localizations.help, image: UIImage(named: "profile.help"))
    private let cellAbout = SettingsTableViewCell(text: Localizations.about, image: UIImage(named: "profile.about"))

    // MARK: View Controller

    init() {
        super.init(style: .grouped)
        title = Localizations.titleProfile
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

        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .feed: return self.cellMyPosts
            case .archive: return self.cellArchive
            case .settings: return self.cellSettings
            case .invite: return self.cellInviteFriends
            case .help: return self.cellHelp
            case .about: return self.cellAbout
            }
        })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one, .two ])
        snapshot.appendItems([ .feed, .settings, .help ], toSection: .one)
        snapshot.appendItems([ .about, .invite ], toSection: .two)
        dataSource.apply(snapshot, animatingDifferences: false)

        headerViewController = ProfileHeaderViewController()
        headerViewController.isEditingAllowed = true
        headerViewController.view.layoutMargins.bottom = 32
        cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
            guard let self = self else { return }
            self.headerViewController.configureForCurrentUser(withName: userName)
            self.viewIfLoaded?.setNeedsLayout()
        }))
        tableView.tableHeaderView = headerViewController.view
        addChild(headerViewController)
        headerViewController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
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
        case .feed:
            openMyFeed()
        case .archive:
            openArchive()
        case .settings:
            openSettings()
        case .invite:
            openInviteFriends()
        case .help:
            openHelp()
        case .about:
            openAbout()
        }
    }

    private func openMyFeed() {
        let viewController = UserFeedViewController(userId: MainAppContext.shared.userData.userId)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openArchive() {

    }

    private func openSettings() {
        let viewController = SettingsViewController()
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openInviteFriends() {
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteView = InvitePeopleView(dismiss: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let viewController = UIHostingController(rootView: inviteView)
        present(UINavigationController(rootViewController: viewController), animated: true) {
            if let indexPath = self.dataSource.indexPath(for: .invite) {
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    private func openHelp() {
        let viewController = HelpViewController(title: Localizations.help)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openAbout() {
        if let viewController = UIStoryboard.init(name: "AboutView", bundle: Bundle.main).instantiateInitialViewController() {
            viewController.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(viewController, animated: true)
        }
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
