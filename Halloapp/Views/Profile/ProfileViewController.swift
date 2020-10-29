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

    static var myPosts: String {
        NSLocalizedString("profile.row.my.posts", value: "My Posts", comment: "Row in Profile screen.")
    }

    static var archive: String {
        NSLocalizedString("profile.row.archive", value: "Archive", comment: "Row in Profile screen.")
    }

    static var settings: String {
        NSLocalizedString("profile.row.settings", value: "Settings", comment: "Row in Profile screen.")
    }

    static var inviteFriends: String {
        NSLocalizedString("profile.row.invite", value: "Invite Friends & Family", comment: "Row in Profile screen.")
    }

    static var help: String {
        NSLocalizedString("profile.row.help", value: "Help", comment: "Row in Profile screen.")
    }
}

class ProfileViewController: UITableViewController {

    private var cancellables = Set<AnyCancellable>()

    // MARK: Table View Data Source and Rows

    private enum Section {
        case one
        case two
    }

    private enum Row {
        case feed
        case archive
        case settings
        case developer
        case invite
        case help
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    private let cellMyPosts = SettingsTableViewCell(text: Localizations.myPosts, image: UIImage(named: "profile.my.posts"))
    private let cellArchive = SettingsTableViewCell(text: Localizations.archive, image: UIImage(named: "profile.archive"))
    private let cellSettings = SettingsTableViewCell(text: Localizations.settings, image: UIImage(named: "profile.settings"))
    private let cellDeveloper = SettingsTableViewCell(text: "Developer Menu", image: UIImage(systemName: "hammer"))
    private let cellInviteFriends = SettingsTableViewCell(text: Localizations.inviteFriends, image: UIImage(named: "profile.invite"))
    private let cellHelp = SettingsTableViewCell(text: Localizations.help, image: UIImage(named: "profile.help"))

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

        tableView.backgroundColor = .feedBackground

        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .feed: return self.cellMyPosts
            case .archive: return self.cellArchive
            case .settings: return self.cellSettings
            case .developer: return self.cellDeveloper
            case .invite: return self.cellInviteFriends
            case .help: return self.cellHelp
            }
        })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one, .two ])
        snapshot.appendItems([ .feed, .settings ], toSection: .one)
        #if DEBUG
        let showDeveloperMenu = true
        #else
        let showDeveloperMenu = ServerProperties.isInternalUser
        #endif
        if showDeveloperMenu {
            snapshot.appendItems([ .developer ], toSection: .one)
        }
        snapshot.appendItems([ .invite, .help ], toSection: .two)
        dataSource.apply(snapshot, animatingDifferences: false)

        let tableWidth = view.frame.width
        let headerView = UserProfileTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.layoutMargins.bottom = 32
        headerView.canEditProfile = true
        headerView.avatarViewButton.addTarget(self, action: #selector(presentProfileEditScreen), for: .touchUpInside)
        let headerTapGesture = UITapGestureRecognizer(target: self, action: #selector(presentProfileEditScreen))
        headerView.addGestureRecognizer(headerTapGesture)
        tableView.tableHeaderView = headerView

        cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
            guard let self = self else { return }
            headerView.updateMyProfile(name: userName)
            self.view.setNeedsLayout()
        }))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // This VC pushes SwiftUI views that hide the tab bar and use `navigationBarTitle` to display custom titles.
        // These titles aren't reset when the SwiftUI views are dismissed, so we need to manually update the title
        // here or the tab bar will show the wrong title when it reappears.
        navigationController?.title = title
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let currentOverlay = overlay {
            overlayContainer.dismiss(currentOverlay)
            overlay = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showNUXIfNecessary()

        InviteManager.shared.requestInvitesIfNecessary()
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
        case .developer:
            openDeveloperMenu()
        case .invite:
            openInviteFriends()
        case .help:
            openHelp()
        }
    }

    private func openMyFeed() {
        let viewController = MyFeedViewController(title: Localizations.myPosts)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openArchive() {

    }

    private func openSettings() {
        let viewController = UIHostingController(rootView: SettingsView())
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openInviteFriends() {
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

    @objc private func openDeveloperMenu() {
        let developerMenuView = DeveloperMenuView(
            useTestServer: MainAppContext.shared.userData.useTestServer,
            useProtobuf: MainAppContext.shared.userData.useProtobuf,
            dismiss: {
                self.navigationController?.popViewController(animated: true)
            })
        let viewController = UIHostingController(rootView: developerMenuView)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc private func presentProfileEditScreen() {
        var profileEditView = ProfileEditView()
        profileEditView.dismiss = { self.dismiss(animated: true) }
        present(UIHostingController(rootView: NavigationView(content: { profileEditView } )), animated: true)
    }

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.constrain(to: view)
        return overlayContainer
    }()

    private var overlay: Overlay?

    private func showNUXIfNecessary() {
        if MainAppContext.shared.nux.isIncomplete(.profileIntro) {
            let popover = NUXPopover(NUX.profileContent) { MainAppContext.shared.nux.didComplete(.profileIntro) }
            overlayContainer.display(popover)
            overlay = popover
        }
    }

}
