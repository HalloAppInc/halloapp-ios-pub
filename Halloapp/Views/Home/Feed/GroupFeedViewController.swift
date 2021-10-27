//
//  GroupFeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import UIKit

class GroupFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    private let groupId: GroupID
    private var group: ChatGroup?

    private var theme: Int32 = 0 {
        didSet {
            guard oldValue != theme else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.setThemeColors(theme: self.theme)
            }
        }
    }
    
    private var currentUnreadThreadGroupCount = 0
    private var currentUnseenGroupFeedList: [GroupID: Int] = [:]

    private var isTopNavShadowShown: Bool = false

    private var cancellableSet: Set<AnyCancellable> = []

    init(groupId: GroupID) {
        self.groupId = groupId
        self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        self.theme = group?.background ?? 0
        super.init(title: nil, fetchRequest: FeedDataSource.groupFeedRequest(groupID: groupId))
        self.hidesBottomBarWhenPushed = true
        self.setupDatasource()
        self.populateEvents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        setThemeColors(theme: theme)

        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.8))
        ])

        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        titleView.delegate = self

        titleView.animateInfoLabel()

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupFeed.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard groupID != self.groupId else { return }

                if self.currentUnseenGroupFeedList[groupID] == nil {
                    self.currentUnseenGroupFeedList[groupID] = 1
                } else {
                    self.currentUnseenGroupFeedList[groupID]? += 1
                }

                DispatchQueue.main.async {
                    self.updateBackButtonUnreadCount(num: self.currentUnseenGroupFeedList.count)
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard groupID == self.groupId else { return }
                self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupID)
                self.theme = self.group?.background ?? 0

                DispatchQueue.main.async {
                    self.populateEvents()
                }
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupFeedViewController/viewWillAppear")
        super.viewWillAppear(animated)
        titleView.update(with: groupId)

        navigationController?.navigationBar.tintColor = UIColor.groupFeedTopNav

        updateTopNavShadow()

        MainAppContext.shared.chatData.syncGroupIfNeeded(for: groupId)
        UNUserNotificationCenter.current().removeDeliveredChatNotifications(groupId: groupId)
        updateFloatingActionMenu()
        tabBarController?.hideTabBar(vc: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupFeedViewController/viewWillDisappear")
        super.viewWillDisappear(animated)

        navigationController?.navigationBar.tintColor = .label
        navigationController?.navigationBar.backItem?.backBarButtonItem = UIBarButtonItem()

        hideTopNavShadow()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func showGroupName() -> Bool {
        return false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateTopNavShadow()
    }

    private var userBelongsToGroup: Bool {
        MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil
    }

    private func updateBackButtonUnreadCount(num: Int) {
        let backButton = UIBarButtonItem()
        backButton.title = num > 0 ? String(num) : " \u{00a0}"

        navigationController?.navigationBar.backItem?.backBarButtonItem = backButton
        navigationController?.navigationBar.tintColor = .primaryBlue
    }

    private lazy var titleView: GroupTitleView = {
        let titleView = GroupTitleView()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        return titleView
    }()

    private func updateTopNavShadow() {
        if isNearTop(100) {
            hideTopNavShadow()
        } else {
            showTopNavShadow()
        }
    }

    private func showTopNavShadow() {
        guard !isTopNavShadowShown else { return }
        isTopNavShadowShown = true
        
        UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            guard let self = self else { return }
            self.navigationController?.navigationBar.layer.shadowColor = UIColor.groupFeedTopNavShadow.cgColor
            self.navigationController?.navigationBar.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
            self.navigationController?.navigationBar.layer.shadowRadius = 15.0
            self.navigationController?.navigationBar.layer.shadowOpacity = 1.0
        })

    }

    private func hideTopNavShadow() {
        guard isTopNavShadowShown else { return }
        isTopNavShadowShown = false
        UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            guard let self = self else { return }
            self.navigationController?.navigationBar.layer.shadowOpacity = 0
        })
    }

    private func setThemeColors(theme: Int32) {
        let backgroundColor = ChatData.getThemeBackgroundColor(for: theme)
        view.backgroundColor = backgroundColor

        let navAppearance = UINavigationBarAppearance()
        navAppearance.backgroundColor = UIColor.primaryBg
        navAppearance.shadowColor = nil
        navAppearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance
    }

    // MARK: Datasource

    private func setupDatasource() {
        feedDataSource.modifyItems = { [weak self] items in
            var result = items
            guard let self = self else { return result }
            guard let group = self.group else { return result }

            let sharedNUX = MainAppContext.shared.nux
            let sharedUserData = MainAppContext.shared.userData
            let sharedChatData = MainAppContext.shared.chatData

            let isZeroZone = sharedNUX.state == .zeroZone
            guard isZeroZone else { return result }

            guard let groupMember = sharedChatData?.chatGroupMember(groupId: group.groupId, memberUserId: sharedUserData.userId) else { return result }
            guard groupMember.type == .admin else { return result }

            // brittle string comparison, should migrate to storing groupID once zero zone feature stabilizes
            let isGroupCreatedForUser = group.name == Localizations.groupsNUXuserGroupName(MainAppContext.shared.userData.name)

            result.append(FeedDisplayItem.groupWelcome(self.groupId))

            // one time update to mark welcome post as seen in the special group created for the user
            if isGroupCreatedForUser {
                sharedNUX.didComplete(.seenUserGroupWelcomePost) // user will see welcome post once loaded since it's at the top
                MainAppContext.shared.chatData.updateUnreadThreadGroupsCount() // refresh bottom nav groups badge
                MainAppContext.shared.chatData.triggerGroupThreadUpdate(self.groupId) // refresh groups list thread unread count
            }

            return result
        }
    }

    private func populateEvents() {
        let groupFeedEvents = MainAppContext.shared.chatData.groupFeedEvents(with: self.groupId)
        var feedEvents = [FeedEvent]()
        groupFeedEvents.forEach {
            let text = $0.event?.text ?? ""
            let timestamp = $0.timestamp ?? Date()
            feedEvents.append((FeedEvent(description: text, timestamp: timestamp, isThemed: theme != 0)))
        }

        feedDataSource.events = feedEvents
        feedDataSource.refresh()
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

    private func updateFloatingActionMenu() {
        guard userBelongsToGroup else {
            removeFloatingActionMenu()
            return
        }
        if floatingMenu.superview == nil {
            installFloatingActionMenu()
        }
    }

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        collectionView.contentInset.bottom = floatingMenu.suggestedContentInsetHeight
    }

    private func removeFloatingActionMenu() {
        floatingMenu.removeFromSuperview()
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source, destination: .groupFeed(groupId)) { didPost in
            self.dismiss(animated: true)
            if didPost { self.scrollToTop(animated: true) }
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)

        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func isScrolledFromTop(by fromTop: CGFloat) -> Bool {
        return collectionView.contentOffset.y < fromTop
    }
}

// MARK: Title View Delegates
extension GroupFeedViewController: GroupTitleViewDelegate {

    func groupTitleViewRequestsOpenGroupInfo(_ groupTitleView: GroupTitleView) {
        let vc = GroupInfoViewController(for: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    func groupTitleViewRequestsOpenGroupFeed(_ groupTitleView: GroupTitleView) {
        if MainAppContext.shared.chatData.chatGroup(groupId: groupId) != nil {
            let vc = GroupFeedViewController(groupId: groupId)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
