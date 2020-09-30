//
//  ProfileView.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class ProfileViewController: FeedTableViewController {

    private var cancellables = Set<AnyCancellable>()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()
        installFloatingActionMenu()

        var rightBarButtonItems = [ UIBarButtonItem(image: UIImage(named: "NavbarSettings"), style: .plain, target: self, action: #selector(presentSettingsScreen)) ]
        #if DEBUG
        let showDeveloperMenu = true
        #else
        let showDeveloperMenu = ServerProperties.isInternalUser
        #endif
        if showDeveloperMenu {
            rightBarButtonItems.append(UIBarButtonItem(image: UIImage(systemName: "hammer"), style: .plain, target: self, action: #selector(presentDeveloperMenu)))
        }
        navigationItem.rightBarButtonItems = rightBarButtonItems

        let tableWidth = view.frame.width
        let headerView = UserProfileTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.canEditProfile = true
        headerView.avatarViewButton.addTarget(self, action: #selector(presentProfileEditScreen), for: .touchUpInside)
        tableView.tableHeaderView = headerView

        cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
            guard let self = self else { return }
            headerView.updateMyProfile(name: userName)
            self.view.setNeedsLayout()
        }))
        
        let headerTapGesture = UITapGestureRecognizer(target: self, action: #selector(presentProfileEditScreen))
        headerView.addGestureRecognizer(headerTapGesture)
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

        floatingMenu.setState(.collapsed, animated: true)
        if let currentOverlay = overlay {
            overlayContainer.dismiss(currentOverlay)
            overlay = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showNUXIfNecessary()
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

    // MARK: UI Actions

    @objc private func presentDeveloperMenu() {
        let developerMenuView = DeveloperMenuView(
            useTestServer: MainAppContext.shared.userData.useTestServer,
            useProtobuf: MainAppContext.shared.userData.useProtobuf,
            dismiss: { self.dismiss(animated: true) })
        present(UIHostingController(rootView: developerMenuView), animated: true)
    }

    @objc private func presentSettingsScreen() {
        let viewController = UIHostingController(rootView: SettingsView())
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

    // MARK: New post

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                expandedRotation: 45),
            expandedButtons: [
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Photo",
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Camera",
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Text",
                    action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            ]
        )
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", MainAppContext.shared.userData.userId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func shouldOpenFeed(for userID: UserID) -> Bool {
        return userID != MainAppContext.shared.userData.userId
    }
}
