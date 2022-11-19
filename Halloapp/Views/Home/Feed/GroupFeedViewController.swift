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
import CoreCommon
import CoreData
import UIKit
import UserNotifications

class GroupFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    private struct GroupPostScrollPosition {
        let postID: FeedPostID
        let offset: CGFloat
    }

    private static var cachedScrollPositions: [GroupID: GroupPostScrollPosition] = [:]

    private let groupId: GroupID
    private var group: Group?

    private var theme: Int32 = 0 {
        didSet {
            guard oldValue != theme else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.setThemeColors(theme: self.theme)
            }
        }
    }

    override var isThemed: Bool {
        return theme != 0
    }
    
    private var currentUnreadThreadGroupCount = 0
    private var currentUnseenGroupFeedList: [GroupID: Int] = [:]

    private var isTopNavShadowShown: Bool = false
    private var shouldShowInviteSheet = false

    private var cancellableSet: Set<AnyCancellable> = []

    private var shouldRestoreScrollPosition: Bool

    private var recentSelfPostIDs = Set<FeedPostID>()
    private var recentSelfPostShareCarouselDisplayTimes = Dictionary<FeedPostID, Date>()

    override var feedPostIdToScrollTo: FeedPostID? {
        didSet {
            if feedPostIdToScrollTo != nil {
                shouldRestoreScrollPosition = false
            }
        }
    }

    var groupEventToScrollTo: GroupEvent? {
        didSet {
            if groupEventToScrollTo != nil {
                shouldRestoreScrollPosition = false
            }
        }
    }

    init(group: Group, shouldShowInviteSheet: Bool = false) {
        self.groupId = group.id
        self.group = group
        self.theme = group.background
        self.shouldShowInviteSheet = shouldShowInviteSheet
        shouldRestoreScrollPosition = Self.cachedScrollPositions[groupId] != nil
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
            let group = MainAppContext.shared.chatData.chatGroup(groupId: id, in: MainAppContext.shared.chatData.viewContext)
        else {
            return nil
        }
        self.init(group: group)
        self.feedPostIdToScrollTo = metadata.postId
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
                    self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext)
                    self.theme = self.group?.background ?? 0
                    self.populateEvents()
                    self.titleView.update(with: groupID)
                    self.updateFloatingActionMenu()
                }
            }
        )

        // Mark all posts as read on first view of group.
        // This is tracked by whether we have a cached scroll position
        if !shouldRestoreScrollPosition, feedPostIdToScrollTo == nil {
            markAllPostsAsViewed()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupFeedViewController/viewWillAppear")
        super.viewWillAppear(animated)
        titleView.update(with: groupId)

        navigationController?.navigationBar.tintColor = UIColor.groupFeedTopNav

        updateTopNavShadow()

        MainAppContext.shared.chatData.syncGroupIfNeeded(for: groupId)
        UNUserNotificationCenter.current().removeDeliveredGroupPostNotifications(groupId: groupId)
        UNUserNotificationCenter.current().removeDeliveredGroupAddNotification(groupId: groupId)
        updateFloatingActionMenu()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Analytics.openScreen(.groupFeed)

        if shouldShowInviteSheet {
            shouldShowInviteSheet = false

            let member = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId,
                                                                        memberUserId: MainAppContext.shared.userData.userId,
                                                                        in: MainAppContext.shared.chatData.viewContext)

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

        memoizeScrollPosition()
    }

    func memoizeScrollPosition() {
        guard let collectionViewDataSource = collectionViewDataSource else {
            return
        }

        // Find a visible feedPost to serve as an anchor for positioning
        for indexPath in collectionView.indexPathsForVisibleItems {
            if let feedDisplayItem = collectionViewDataSource.itemIdentifier(for: indexPath),
               case .post(let feedPost) = feedDisplayItem,
               let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) {
                let offset = collectionView.contentOffset.y - layoutAttributes.frame.minY
                Self.cachedScrollPositions[groupId] = GroupPostScrollPosition(postID: feedPost.id, offset: offset)
                break
            }
        }
    }

    override func viewDidLayoutSubviews() {
        // Adjust bottom inset before any scrolling occurs in super.didLayoutSubviews
        let bottomInset = view.bounds.maxY - newPostButton.frame.minY - collectionView.safeAreaInsets.bottom
        if bottomInset != collectionView.contentInset.bottom {
            collectionView.contentInset.bottom = bottomInset
        }

        super.viewDidLayoutSubviews()

        // On 16+ we don't get another layoutSubviews where collectionView.contentSize != .zero
        if #available(iOS 16.0, *) {
            guard feedPostIdToScrollTo == nil else {
                return
            }
        } else {
            guard collectionView.contentSize != .zero, feedPostIdToScrollTo == nil else {
                return
            }
        }

        if let groupEvent = groupEventToScrollTo {
            groupEventToScrollTo = nil

            if let index = feedDataSource.index(of: groupEvent) {
                let indexPath = IndexPath(item: index, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
                collectionView.layoutIfNeeded()
                collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            }
            return
        }

        guard shouldRestoreScrollPosition, let scrollPosition = Self.cachedScrollPositions[groupId] else {
            return
        }

        // Only restore on initial load
        shouldRestoreScrollPosition = false

        // If we have a specific post to scroll to or can no longer find the anchor post, do not adjust scroll postion.
        guard let index = feedDataSource.index(of: scrollPosition.postID) else {
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        // LayoutAttributes gives estimated sizes until initial render, so scroll to relative position then finalize
        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        collectionView.layoutIfNeeded()
        if let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) {
            collectionView.contentOffset = CGPoint(x: 0, y: layoutAttributes.frame.minY + scrollPosition.offset)
        }

        if feedDataSource.hasUnreadPosts, !isNearTop(100) {
            showNewPostsIndicator()
        }
    }

    override func showGroupName() -> Bool {
        return false
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)


        let shouldHideAccessoryView = scrollView.contentSize.height > scrollView.bounds.inset(by: scrollView.adjustedContentInset).height && scrollView.contentOffset.y > 0

        // if we didn't use a DispatchQueue here, we'd get some issues when restoring scroll position
        DispatchQueue.main.async { [weak self] in
            guard let newPostButton = self?.newPostButton, newPostButton.accessoryView.isHidden != shouldHideAccessoryView else {
                return
            }

            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: .allowUserInteraction,
                animations: {
                    newPostButton.accessoryView.isHidden = shouldHideAccessoryView
                    newPostButton.layoutIfNeeded()
                })
        }
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)

        if case .event(let feedEvent) = feedDataSource.item(at: indexPath.item) {
            switch feedEvent {
            case .groupEvent(let groupEvent):
                MainAppContext.shared.chatData.markGroupEventAsRead(groupEvent: groupEvent)
            case .collapsedGroupEvents(let groupEvents):
                groupEvents.forEach { MainAppContext.shared.chatData.markGroupEventAsRead(groupEvent: $0) }
            default:
                break
            }
        }

        if let feedItem = feedDataSource.item(at: indexPath.item), case .shareCarousel(let feedPostID) = feedItem {
            recentSelfPostShareCarouselDisplayTimes[feedPostID] = Date()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didEndDisplaying: cell, forItemAt: indexPath)

        if let feedItem = feedDataSource.item(at: indexPath.item), case .shareCarousel(let feedPostID) = feedItem {
            if let displayStart = recentSelfPostShareCarouselDisplayTimes[feedPostID], -displayStart.timeIntervalSinceNow > 2 {
                recentSelfPostIDs.remove(feedPostID)
                feedDataSource.removeItem(feedItem)
            }
            recentSelfPostShareCarouselDisplayTimes[feedPostID] = nil
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateTopNavShadow()
    }

    private var userBelongsToGroup: Bool {
        MainAppContext.shared.chatData.chatGroupMember(
            groupId: groupId,
            memberUserId: MainAppContext.shared.userData.userId,
            in: MainAppContext.shared.chatData.viewContext) != nil
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
    }

    // MARK: Datasource

    override func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType) {
        super.itemDidChange(item, change: type)

        if type == .insert, case .post(let feedPost) = item, feedPost.userID == MainAppContext.shared.userData.userId, -feedPost.timestamp.timeIntervalSinceNow < 5 * 60 {
            recentSelfPostIDs.insert(feedPost.id)
        }
    }

    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var result = items
        guard let group = self.group else { return result }

        let sharedNUX = MainAppContext.shared.nux
        let sharedUserData = MainAppContext.shared.userData
        let sharedChatData = MainAppContext.shared.chatData
        let viewContext = MainAppContext.shared.chatData.viewContext
        let welcomePostExist = sharedNUX.welcomePostExist(id: self.groupId)
        let isZeroZone = sharedNUX.state == .zeroZone
        let isSampleGroup = sharedNUX.sampleGroupID() == self.groupId
        let showWelcomePostIfNeeded = welcomePostExist || isZeroZone

        guard let groupMember = sharedChatData?.chatGroupMember(groupId: group.id, memberUserId: sharedUserData.userId, in: viewContext) else { return result }
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
        }

        // Insert share carousels last, so any other operations will not interfere with positioning
        var idx = 0
        while idx < result.count {
            if case .post(let feedPost) = result[idx], recentSelfPostIDs.contains(feedPost.id) {
                result.insert(.shareCarousel(feedPost.id), at: idx + 1)
            }
            idx += 1
        }

        return result
    }

    private func populateEvents() {
        let groupFeedEvents = MainAppContext.shared.chatData.groupFeedEvents(with: self.groupId, in: MainAppContext.shared.chatData.viewContext)
        let feedEvents: [FeedEvent] = groupFeedEvents.map { .groupEvent($0) }

        feedDataSource.events = feedEvents
        feedDataSource.refresh()
    }

    // MARK: New post

    private lazy var newPostButton: AccessorizedFloatingButton = {
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

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let plusImage = UIImage(systemName: "plus", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)

        let button = AccessorizedFloatingButton(icon: plusImage, accessoryView: labelContainer)
        button.addTarget(self, action: #selector(presentNewPostController), for: .touchUpInside)
        return button
    }()

    @objc private func presentNewPostController() {
        guard let group = group else { return }
        let state = NewPostState(mediaSource: .unified)

        let newPostViewController = NewPostViewController(state: state, destination: ShareDestination.destination(from: group), showDestinationPicker: false) { didPost, _ in
            MainAppContext.shared.privacySettings.activeType = .all
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

    private func updateFloatingActionMenu() {
        newPostButton.isHidden = !userBelongsToGroup
        newPostButton.isUserInteractionEnabled = userBelongsToGroup
    }

    private func installFloatingActionMenu() {
        newPostButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newPostButton)
        
        NSLayoutConstraint.activate([
            newPostButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            newPostButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -20)
        ])
    }

    override func newPostsIndicatorTapped() {
        super.newPostsIndicatorTapped()
        markAllPostsAsViewed()
    }

    private func markAllPostsAsViewed() {
        for feedPost in feedDataSource.posts {
            AppContext.shared.coreFeedData.sendSeenReceiptIfNecessary(for: feedPost)
            UNUserNotificationCenter.current().removeDeliveredPostNotifications(postId: feedPost.id)
            UNUserNotificationCenter.current().removeDeliveredGroupAddNotification(groupId: feedPost.groupID)
        }
    }
}

// MARK: Title View Delegates
extension GroupFeedViewController: GroupTitleViewDelegate {

    func groupTitleViewRequestsOpenGroupInfo(_ groupTitleView: GroupTitleView) {
        let vc = GroupInfoViewController(for: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    func groupTitleViewRequestsOpenGroupFeed(_ groupTitleView: GroupTitleView) {
        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
            let vc = GroupFeedViewController(group: group)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
