//
//  MyFeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class MyFeedViewController: FeedTableViewController {

    private var cancellables = Set<AnyCancellable>()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        installFloatingActionMenu()

        let tableWidth = view.frame.width
        let headerView = UserProfileTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        floatingMenu.setState(.collapsed, animated: true)
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

    @objc private func presentProfileEditScreen() {
        var profileEditView = ProfileEditView()
        profileEditView.dismiss = { self.dismiss(animated: true) }
        present(UIHostingController(rootView: NavigationView(content: { profileEditView } )), animated: true)
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
                    accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityCamera,
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityTextPost,
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
        let newPostViewController = NewPostViewController(source: source, destination: .userFeed) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@ AND groupId == nil", MainAppContext.shared.userData.userId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func shouldOpenFeed(for userID: UserID) -> Bool {
        return userID != MainAppContext.shared.userData.userId
    }
}
