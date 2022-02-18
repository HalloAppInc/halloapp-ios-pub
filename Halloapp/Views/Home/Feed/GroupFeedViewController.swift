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
    private var shouldShowInviteSheet = false

    private var cancellableSet: Set<AnyCancellable> = []
    
    init(groupId: GroupID, shouldShowInviteSheet: Bool = false) {
        self.groupId = groupId
        self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        self.theme = group?.background ?? 0
        self.shouldShowInviteSheet = shouldShowInviteSheet
        super.init(title: nil, fetchRequest: FeedDataSource.groupFeedRequest(groupID: groupId))
        self.hidesBottomBarWhenPushed = true
        self.populateEvents()
    }
    
    /// For when the user responds to a group notification.
    ///
    /// This will make the VC scroll to the post referenced in the notification.
    convenience init?(metadata: NotificationMetadata) {
        guard
            let id = metadata.groupId,
            let _ = MainAppContext.shared.chatData.chatGroup(groupId: id)
        else {
            return nil
        }
        
        self.init(groupId: id)
        self.feedPostIdToScrollTo = metadata.postData()?.id
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        setThemeColors(theme: theme)

        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        titleView.delegate = self

        titleView.animateInfoLabel()

        installFloatingActionMenu()

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
                guard groupID == self?.groupId else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupID)
                    self.theme = self.group?.background ?? 0
                    self.populateEvents()
                    self.titleView.update(with: groupID)
                    self.updateFloatingActionMenu()
                }
            }
        )

        cancellableSet.insert(MainAppContext.shared.callManager.hasActiveCallPublisher.sink(receiveValue: { [weak self] hasActiveCall in
            self?.composeVoiceNoteButton?.button.isEnabled = !hasActiveCall
        }))
        
        if let idForScroll = feedPostIdToScrollTo, scrollTo(postId: idForScroll) == true {
            feedPostIdToScrollTo = nil
        }
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if shouldShowInviteSheet {
            shouldShowInviteSheet = false

            let member = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId,
                                                                        memberUserId: MainAppContext.shared.userData.userId)

            guard member?.type == .admin, let groupInviteLink = group?.inviteLink.map({ ChatData.formatGroupInviteLink($0) }) else {
                DDLogError("GroupFeedViewController/Failed fetch group invite link")
                return
            }

            present(GroupInviteSheetViewController(groupInviteLink: groupInviteLink), animated: true)
        }
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

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        let fabAccessoryState: FloatingMenu.AccessoryState = scrollView.contentOffset.y <= 0 ? .accessorized : .plain
        floatingMenu.setAccessoryState(fabAccessoryState, animated: true)
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

    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var result = items
        guard let group = self.group else { return result }

        let sharedNUX = MainAppContext.shared.nux
        let sharedUserData = MainAppContext.shared.userData
        let sharedChatData = MainAppContext.shared.chatData
        let welcomePostExist = sharedNUX.welcomePostExist(id: self.groupId)
        let isZeroZone = sharedNUX.state == .zeroZone
        let isSampleGroup = sharedNUX.sampleGroupID() == self.groupId
        let showWelcomePostIfNeeded = welcomePostExist || isZeroZone

        guard let groupMember = sharedChatData?.chatGroupMember(groupId: group.groupId, memberUserId: sharedUserData.userId) else { return result }
        guard groupMember.type == .admin else { return result }

        if showWelcomePostIfNeeded {
            if welcomePostExist {
                // don't show post if post was closed by user or expired
                if sharedNUX.showWelcomePost(id: self.groupId) {
                    result.append(FeedDisplayItem.groupWelcome(self.groupId))
                }
            } else {
                sharedNUX.recordWelcomePost(id: self.groupId, type: .group)
                result.append(FeedDisplayItem.groupWelcome(self.groupId))
            }
        }

        // one time update to mark sample group welcome post as seen if not seen before
        if isSampleGroup, let seen = sharedNUX.sampleGroupWelcomePostSeen(), !seen {
            sharedNUX.markSampleGroupWelcomePostSeen() // user will see welcome post once loaded since it's at the top
            MainAppContext.shared.chatData.updateUnreadThreadGroupsCount() // refresh bottom nav groups badge
            MainAppContext.shared.chatData.triggerGroupThreadUpdate(self.groupId) // refresh groups list thread unread count
        }

        return result
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

    private var composeVoiceNoteButton: FloatingMenuButton?

    private lazy var floatingMenu: FloatingMenu = {
        var expandedButtons: [FloatingMenuButton] = [
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityTextPost,
                action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityCamera,
                action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
        ]

        if ServerProperties.isVoicePostsEnabled {
            let button = FloatingMenuButton.standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_voice")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityVoiceNote,
                action: { [weak self] in self?.presentNewPostViewController(source: .voiceNote) })
            composeVoiceNoteButton = button
            expandedButtons.insert(button, at: 1)
        }

        let postLabel = UILabel()
        postLabel.translatesAutoresizingMaskIntoConstraints = false
        postLabel.font = .quicksandFont(ofFixedSize: 21, weight: .bold)
        postLabel.text = Localizations.fabPostButton
        postLabel.textColor = .white

        let labelContainer = UIView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)
        labelContainer.addSubview(postLabel)
        postLabel.constrainMargins(to: labelContainer)

        return FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                accessoryView: labelContainer,
                expandedRotation: 45),
            expandedButtons: expandedButtons,
            expandedHeader: Localizations.newPost)
    }()

    private func updateFloatingActionMenu() {
        floatingMenu.isHidden = !userBelongsToGroup
        floatingMenu.isUserInteractionEnabled = userBelongsToGroup
    }

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        collectionView.contentInset.bottom = floatingMenu.suggestedContentInsetHeight
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        if source == .voiceNote && MainAppContext.shared.callManager.isAnyCallActive {
            // When we have an active call ongoing: we should not record audio.
            // We should present an alert saying that this action is not allowed.
            let alert = UIAlertController(
                title: Localizations.failedActionDuringCallTitle,
                message: Localizations.failedActionDuringCallNoticeText,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
                DDLogInfo("GroupFeedViewController/presentNewPostViewController/failedActionDuringCall/dismiss")
            }))
            present(alert, animated: true)
        } else {
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
