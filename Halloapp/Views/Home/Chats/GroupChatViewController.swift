//
//  GroupChatViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 9/23/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CoreData
import CocoaLumberjackSwift
import UIKit

fileprivate struct ChatMessageData: Equatable, Hashable {
    let id: String
    let fromUserId: String
    let groupId: String
    let timestamp: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

fileprivate enum MessageRow: Hashable, Equatable {
    case chatMessage(ChatMessageData)
    case unreadCountHeader(Int32)
    case timeHeader(String)
    case groupChatEvent(GroupEvent)

    var timestamp: Date? {
        switch self {
        case .chatMessage(let data):
            return data.timestamp
        case .groupEvent(let data):
            return data.timestamp
        case .unreadCountHeader(_), .timeHeader(_):
            return nil
        }
    }

    var headerTime: String {
        switch self {
        case .chatMessage(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .groupChatEvent(let data):
            return data.timestamp.chatMsgGroupingTimestamp(Date())
        case .unreadCountHeader(_):
            return ""
        case .timeHeader(let timestamp):
            return timestamp
        }
    }

    // not all chat messages are counted when displaying unread counts.
    // in order to insert the unread bannber at the right location, we need this property
    var isCountedInUnreadCounts: Bool {
        switch self {
        case .chatMessage(_):
            return true
        case .timeHeader(_), .unreadCountHeader(_), .groupChatEvent(_):
            return false
        }
    }
}

fileprivate enum Section: Hashable {
    case chats
}

class GroupChatViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate {

    private let groupId: GroupID
    private var group: Group?

    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let messageCellViewTextReuseIdentifier = "MessageCellViewText"
    static private let messageCellViewMediaReuseIdentifier = "MessageCellViewMedia"
    static private let messageCellViewAudioReuseIdentifier = "MessageCellViewAudio"
    static private let messageCellViewLocationReuseIdentifier = "MessageCellViewLocation"
    static private let messageCellViewDocumentReuseIdentifier = "MessageCellViewDocument"
    static private let messageCellViewLinkPreviewReuseIdentifier = "MessageCellViewLinkPreview"
    static private let messageCellViewQuotedReuseIdentifier = "MessageCellViewQuoted"
    static private let messageCellViewEventReuseIdentifier = "MessageCellViewEvent"
    static private let messageCellViewCallReuseIdentifier = "MessageCellViewCall"

    private var chatMessageFetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var groupEventFetchedResultsController: NSFetchedResultsController<GroupEvent>?

    fileprivate typealias ChatDataSource = UICollectionViewDiffableDataSource<Section, MessageRow>
    fileprivate typealias ChatMessageSnapshot = NSDiffableDataSourceSnapshot<Section, MessageRow>

    private lazy var titleView: GroupTitleView = {
        let titleView = GroupTitleView()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        return titleView
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.primaryBg
        collectionView.allowsSelection = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.register(MessageViewCell.self, forCellWithReuseIdentifier: GroupChatViewController.messageViewCellReuseIdentifier)
        collectionView.register(MessageCellViewText.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewTextReuseIdentifier)
        collectionView.register(MessageCellViewMedia.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewMediaReuseIdentifier)
        collectionView.register(MessageCellViewAudio.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewAudioReuseIdentifier)
        collectionView.register(MessageCellViewLocation.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewLocationReuseIdentifier)
        collectionView.register(MessageCellViewLinkPreview.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewLinkPreviewReuseIdentifier)
        collectionView.register(MessageCellViewQuoted.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewQuotedReuseIdentifier)
        collectionView.register(MessageUnreadHeaderView.self, forCellWithReuseIdentifier: MessageUnreadHeaderView.elementKind)
        collectionView.register(MessageCellViewEvent.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewEventReuseIdentifier)
        collectionView.register(MessageCellViewCall.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewCallReuseIdentifier)
        collectionView.register(MessageTimeHeaderView.self, forCellWithReuseIdentifier: MessageTimeHeaderView.elementKind)
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var dataSource: ChatDataSource? = {
        let dataSource = ChatDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, messageRow) -> UICollectionViewCell? in
                switch messageRow {
                case .chatMessage(let chatMessageData):
                    if let self = self, let chatMessage = self.chatMessage(id: chatMessageData.id) {
                        return self.chatMessageCell(chatMessage: chatMessage, indexPath: indexPath)
                    }
                case .groupEvent(let groupEvent):
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GroupChatViewController.messageCellViewEventReuseIdentifier, for: indexPath)
                    (cell as? MessageCellViewEvent)?.configure(groupEvent: groupEvent)
                    return cell
                case .unreadCountHeader(let unreadCount):
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageUnreadHeaderView.elementKind,
                        for: indexPath)
                    if let itemCell = cell as? MessageUnreadHeaderView {
                        itemCell.configure(headerText: Localizations.unreadMessagesHeader(unreadCount: Int(unreadCount)))
                    }
                    return cell
                case .timeHeader(let timestamp):
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageTimeHeaderView.elementKind,
                        for: indexPath)
                    if let itemCell = cell as? MessageTimeHeaderView {
                        itemCell.configure(headerText: timestamp)
                    }
                    return cell
                }
                return nil
            })
        return dataSource
    }()

    func chatMessageCell(chatMessage: ChatMessage, indexPath: IndexPath) ->  UICollectionViewCell {
        if [.retracted, .retracting].contains(chatMessage.outgoingStatus) || [.retracted, .rerequesting, .unsupported].contains(chatMessage.incomingStatus) {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageViewCellReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageViewCell {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.media?.first?.type == .audio {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewAudioReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewAudio {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        } else if chatMessage.media?.first?.type == .video || chatMessage.media?.first?.type == .image {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewMediaReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewMedia {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        } else if chatMessage.media?.first?.type == .document {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewDocumentReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewDocument {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell

        }
        if let feedLinkPreviews = chatMessage.linkPreviews, feedLinkPreviews.first != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewLinkPreviewReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewLinkPreview {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.chatReplyMessageID != nil || chatMessage.feedPostId != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewQuotedReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewQuoted {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.location != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GroupChatViewController.messageCellViewLocationReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewLocation {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupChatViewController.messageCellViewTextReuseIdentifier,
            for: indexPath)
        if let itemCell = cell as? MessageCellViewText {
            self.configureCell(itemCell: itemCell, for: chatMessage)
        }
        return cell
    }

    private func configureCell(itemCell: MessageCellViewBase, for chatMessage: ChatMessage) {
        // TODO isPreviousMessageFromSameSender calculation
        let isPreviousMessageFromSameSender = false
        itemCell.configureWith(message: chatMessage, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        itemCell.textLabel.delegate = self
        //itemCell.chatDelegate = self
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)

        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }

    init(for groupId: GroupID) {
        self.groupId = groupId
        self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext)
        if let group = group {
            DDLogDebug("GroupChatViewController/init/\(group.id) [\(group.name))]")
        }
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupChatViewController/viewDidLoad currentUser: \(MainAppContext.shared.userData.userId) groupId: \(String(describing: groupId))")
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.constrain(to: view)
        setupUI()

        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        titleView.delegate = self

        titleView.animateInfoLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupChatViewController/viewWillAppear")
        super.viewWillAppear(animated)
        titleView.update(with: groupId)
        navigationController?.navigationBar.tintColor = UIColor.groupFeedTopNav
    }

    private func setupUI() {
        collectionView.dataSource = dataSource
        setupChatMessageFetchedResultsController()
        setupGroupEventFetchedResultsController()
        updateCollectionViewData()
    }

    // MARK: Chat Message FetchedResults
    private func setupChatMessageFetchedResultsController() {
        let fetchChatMessageRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchChatMessageRequest.relationshipKeyPathsForPrefetching = [
            "media",
            "linkPreviews",
            "reactions",
        ]
        let currentUserID = MainAppContext.shared.userData.userId
        fetchChatMessageRequest.predicate = NSPredicate(format: "(toGroupID = %@)", groupId)
        fetchChatMessageRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true)
        ]

        chatMessageFetchedResultsController = NSFetchedResultsController<ChatMessage>(fetchRequest: fetchChatMessageRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        chatMessageFetchedResultsController?.delegate = self
        do {
            DDLogError("GroupChatViewController/initFetchedResultsController/fetching chat messages for user: \(currentUserID)")
            try chatMessageFetchedResultsController?.performFetch()
        } catch {
            DDLogError("GroupChatViewController/initFetchedResultsController/failed to fetch  chat messages for user:\(currentUserID)")
        }
    }

    private func setupGroupEventFetchedResultsController() {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \GroupEvent.timestamp, ascending: true)
        ]

        let fetchRequest = GroupEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@", groupId)
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        groupEventFetchedResultsController = NSFetchedResultsController<GroupEvent>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        groupEventFetchedResultsController?.delegate = self
        do {
            DDLogError("GroupChatViewController/setupGroupEventFetchedResultsController/fetching group events from chat group: \(groupId)")
            try groupEventFetchedResultsController!.performFetch()
        } catch {
            DDLogError("GroupChatViewController/setupGroupEventFetchedResultsController/failed to fetch  group events from chat group: \(groupId)")
            return
        }
    }

    func updateCollectionViewData() {
        DDLogInfo("GroupChatViewController/updateCollectionViewData/called")
        var messageRows: [MessageRow] = []
        var snapshot = ChatMessageSnapshot()
        var lastMessageHeaderTime: String?

        // Add messages
        if let chatMessages = chatMessageFetchedResultsController?.fetchedObjects {
            DDLogInfo("GroupChatViewController/updateCollectionViewData/ number of chat messages: \(chatMessages.count) groupId: \(groupId)")

            chatMessages.forEach { chatMessage in
                if let groupId = chatMessage.toGroupId {
                    messageRows.append(MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, groupId: groupId, timestamp: chatMessage.timestamp)))
                }
            }
        }
        // Add Group Events
        if let chatEvents = groupEventFetchedResultsController?.fetchedObjects {
            chatEvents.forEach { chatEvent in
                messageRows.append(MessageRow.groupEvent(chatEvent))
            }
        }
        // Sort all messages by timestamp
        messageRows = messageRows.sorted {
            ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture)
        }

        // Insert all messages into snapshot sorted by timestamp and grouped into sections by headerTime
        snapshot.appendSections([ .chats ])
        var tempMessageRows: [MessageRow] = []
        //var previousChatMessageData: ChatMessageData? = nil
        for messageRow in messageRows {
            let currentTime = messageRow.headerTime
            if lastMessageHeaderTime != currentTime {
                lastMessageHeaderTime = currentTime
                tempMessageRows.append(MessageRow.timeHeader(currentTime))
            }
            tempMessageRows.append(messageRow)
        }
        // batch add of message Rows
        snapshot.appendItems(tempMessageRows, toSection: .chats)
        // Apply the new snapshot
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    func chatMessage(id chatMessageId: ChatMessageID) -> ChatMessage? {
        return chatMessageFetchedResultsController?.fetchedObjects?.first { $0.id == chatMessageId}
    }
}

extension GroupChatViewController: TextLabelDelegate {
    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                URLRouter.shared.handleOrOpen(url: url)
            }
        case .userMention:
            if let userID = link.userID {
                showUserFeed(for: userID)
            }
        default:
            break
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        label.numberOfLines = 0
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }
}

// MARK: Title View Delegates
extension GroupChatViewController: GroupTitleViewDelegate {

    func groupTitleViewRequestsOpenGroupInfo(_ groupTitleView: GroupTitleView) {
        let vc = GroupInfoViewController(for: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    func groupTitleViewRequestsOpenGroupFeed(_ groupTitleView: GroupTitleView) {
        // N/A
    }
}

