//
//  ChatViewControllerNew.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/2/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CocoaLumberjackSwift
import Combine
import ContactsUI
import UIKit
import CoreData
import Photos
import SafariServices

fileprivate struct ChatMessageData: Equatable, Hashable {
    let id: String
    let fromUserId: String
    let timestamp: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

fileprivate struct ChatEventData: Equatable, Hashable {
    let timestamp: Date?
    let indexPath: IndexPath

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.indexPath == rhs.indexPath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(indexPath)
    }
}

fileprivate enum MessageRow: Hashable, Equatable {
    case chatMessage(ChatMessageData)
    case chatEvent(ChatEventData)
    case chatCall(ChatCallData)
    case unreadCountHeader(Int32)
    case addToContactBook
    case timeHeader(String)

    var timestamp: Date? {
        switch self {
        case .chatEvent(let data):
            return data.timestamp
        case .chatMessage(let data):
            return data.timestamp
        case .chatCall(let data):
            return data.timestamp
        case .addToContactBook:
            return Calendar.current.startOfDay(for: Date())
        case .unreadCountHeader(_), .timeHeader(_):
            return nil
        }
    }
    
    var headerTime: String {
        switch self {
        case .chatEvent(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .chatMessage(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .chatCall(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .addToContactBook:
            let time = timestamp ?? Calendar.current.startOfDay(for: Date())
            return  time.chatMsgGroupingTimestamp(Date())
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
        case .chatCall(let data):
            return data.isMissedCall ? true : false
        case .chatEvent(_), .addToContactBook, .timeHeader(_), .unreadCountHeader(_):
            return false
        }
    }
}

fileprivate enum Section: Hashable {
    case chats
}

protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ chatViewController: ChatViewControllerNew, userActioned: Bool)
    func chatViewController(_ chatViewController: GroupChatViewController, userActioned: Bool)
}

class ChatViewControllerNew: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, UIViewControllerMediaSaving {

    // Wait for ios to create a cell if it does not exist
    let waitForCellDelay: TimeInterval = 0.25

    weak var chatViewControllerDelegate: ChatViewControllerDelegate?
    var previousChatSenderInfo: [ChatMessageID: Bool] = [:]

    /// The `userID` of the user the client is receiving messages from
    private var fromUserId: String?
    private var feedPostId: FeedPostID?
    private var feedPostMediaIndex: Int32 = 0

    private var chatReplyMessageID: String?
    private var chatReplyMessageSenderID: String?
    private var chatReplyMessageMediaIndex: Int32 = 0
    private var firstActionHappened = false
    private var hasShownAddToContact = false
    private var isFirstLaunch = true
    // This variable is used to determine if the unread banner is visible, if so update its count when the ChatThread unreadCount is updated
    private var unreadMessagesHeaderVisible = false
    private var unreadCount: Int32 = 0
    private var scrollToLastMessageOnNextUpdate = false
    private var didReceiveIncoming = false
    private var scrollToUnreadBanner = false

    fileprivate typealias ChatDataSource = UICollectionViewDiffableDataSource<Section, MessageRow>
    fileprivate typealias ChatMessageSnapshot = NSDiffableDataSourceSnapshot<Section, MessageRow>

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
    private var chatEventFetchedResultsController: NSFetchedResultsController<ChatEvent>?
    private var callHistoryFetchedResultsController: NSFetchedResultsController<Core.Call>?

    private var transitionSnapshot: UIView?

    private lazy var fromUserDestination: ShareDestination? = {
        guard let fromUserId = fromUserId else { return nil }
        guard let contact = MainAppContext.shared.contactStore.contact(withUserId: fromUserId, in: MainAppContext.shared.contactStore.viewContext) else { return nil }

        return ShareDestination.destination(from: contact)
    }()

    private var cancellableSet: Set<AnyCancellable> = []

    // MARK: Jump Button

    private var jumpButtonUnreadCount: Int32 = 0
    private var jumpButtonConstraint: NSLayoutConstraint?

    private lazy var jumpButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ jumpButtonUnreadCountLabel, jumpButtonImageView ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 5
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            jumpButtonImageView.widthAnchor.constraint(equalToConstant: 30),
            jumpButtonImageView.heightAnchor.constraint(equalToConstant: 30)
        ])

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.9)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(scrollToLastMessage))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var jumpButtonUnreadCountLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .systemBlue
        return label
    }()

    private lazy var jumpButtonImageView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(systemName: "chevron.down.circle")
        view.contentMode = .scaleAspectFill
        view.tintColor = .systemBlue

        view.layer.masksToBounds = true

        return view
    }()

    private lazy var titleView: ChatTitleView = {
        let titleView = ChatTitleView()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        titleView.delegate = self
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
        collectionView.register(MessageViewCell.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageViewCellReuseIdentifier)
        collectionView.register(MessageCellViewText.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewTextReuseIdentifier)
        collectionView.register(MessageCellViewMedia.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewMediaReuseIdentifier)
        collectionView.register(MessageCellViewAudio.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewAudioReuseIdentifier)
        collectionView.register(MessageCellViewLocation.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewLocationReuseIdentifier)
        collectionView.register(MessageCellViewDocument.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewDocumentReuseIdentifier)
        collectionView.register(MessageCellViewLinkPreview.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewLinkPreviewReuseIdentifier)
        collectionView.register(MessageCellViewQuoted.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewQuotedReuseIdentifier)
        collectionView.register(MessageUnreadHeaderView.self, forCellWithReuseIdentifier: MessageUnreadHeaderView.elementKind)
        collectionView.register(MessageCellViewEvent.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewEventReuseIdentifier)
        collectionView.register(MessageCellViewCall.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewCallReuseIdentifier)
        collectionView.register(MessageTimeHeaderView.self, forCellWithReuseIdentifier: MessageTimeHeaderView.elementKind)
        collectionView.register(MessageChatHeaderView.self, forSupplementaryViewOfKind: MessageChatHeaderView.elementKind, withReuseIdentifier: MessageChatHeaderView.elementKind)
        collectionView.delegate = self
        return collectionView
    }()

    func chatMessage(id chatMessageId: ChatMessageID) -> ChatMessage? {
        return chatMessageFetchedResultsController?.fetchedObjects?.first { $0.id == chatMessageId}
    }

    func chatMessageCell(chatMessage: ChatMessage, indexPath: IndexPath) ->  UICollectionViewCell {
        if [.retracted, .retracting].contains(chatMessage.outgoingStatus) || [.retracted, .rerequesting, .unsupported].contains(chatMessage.incomingStatus) {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageViewCellReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageViewCell {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.media?.first?.type == .audio {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewAudioReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewAudio {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        } else if chatMessage.media?.first?.type == .video || chatMessage.media?.first?.type == .image {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewMediaReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewMedia {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        } else if chatMessage.media?.first?.type == .document {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewDocumentReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewDocument {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell

        }
        if let feedLinkPreviews = chatMessage.linkPreviews, feedLinkPreviews.first != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewLinkPreviewReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewLinkPreview {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.chatReplyMessageID != nil || chatMessage.feedPostId != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewQuotedReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewQuoted {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        if chatMessage.location != nil {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatViewControllerNew.messageCellViewLocationReuseIdentifier,
                for: indexPath)
            if let itemCell = cell as? MessageCellViewLocation {
                self.configureCell(itemCell: itemCell, for: chatMessage)
            }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatViewControllerNew.messageCellViewTextReuseIdentifier,
            for: indexPath)
        if let itemCell = cell as? MessageCellViewText {
            self.configureCell(itemCell: itemCell, for: chatMessage)
        }
        return cell
    }

    fileprivate var documentInteractionController: UIDocumentInteractionController?

    private lazy var dataSource: ChatDataSource? = {
        let dataSource = ChatDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, messageRow) -> UICollectionViewCell? in
                switch messageRow {
                case .chatMessage(let chatMessageData):
                    if let self = self, let chatMessage = self.chatMessage(id: chatMessageData.id) {
                        return self.chatMessageCell(chatMessage: chatMessage, indexPath: indexPath)
                    }
                case .chatEvent(let chatEventData):
                    guard let self = self, let chatEvent = self.chatEventFetchedResultsController?.optionalObjectfor(at: chatEventData.indexPath) as? ChatEvent else { break }
                    if (chatEvent.type == .whisperKeysChange || chatEvent.type == .blocked || chatEvent.type == .unblocked), let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatViewControllerNew.messageCellViewEventReuseIdentifier, for: indexPath) as? MessageCellViewEvent {
                        let fullname = MainAppContext.shared.contactStore.fullName(for: chatEvent.userID, in: MainAppContext.shared.contactStore.viewContext)
                        switch chatEvent.type {
                        case .whisperKeysChange:
                            cell.configure(chatLogEventType: .whisperKeysChange, userID: chatEvent.userID)
                        case .blocked:
                            cell.configure(chatLogEventType: .blocked, userID: chatEvent.userID)
                        case .unblocked:
                            cell.configure(chatLogEventType: .unblocked, userID: chatEvent.userID)
                        default:
                            break
                        }
                        cell.delegate = self
                        return cell
                    }
                case .chatCall(let callData):
                    if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatViewControllerNew.messageCellViewCallReuseIdentifier, for: indexPath) as? MessageCellViewCall {
                        cell.configure(callData)
                        cell.delegate = self
                        return cell
                    }
                case .addToContactBook:
                    if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatViewControllerNew.messageCellViewEventReuseIdentifier, for: indexPath) as? MessageCellViewEvent {
                        if let fromUserId = self?.fromUserId {
                            cell.configure(chatLogEventType: .addToAddressBook, userID: fromUserId)
                        }
                        cell.delegate = self
                        return cell
                    }
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
        dataSource.supplementaryViewProvider = { [weak self] ( view, kind, index) in
            if kind == MessageChatHeaderView.elementKind {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageChatHeaderView.elementKind, for: index)
                if let messageChatHeaderView = headerView as? MessageChatHeaderView, let self = self, let fromUserId = self.fromUserId {
                    messageChatHeaderView.delegate = self
                    return messageChatHeaderView
                }
            }
            return nil
        }
        return dataSource
    }()

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            DDLogInfo("ChatViewControllerNew/didChange type insert")
            if let chatMessage = anObject as? ChatMessage, chatMessage.userId == fromUserId {
                didReceiveIncoming = true
            } else {
                didReceiveIncoming = false
                scrollToLastMessageOnNextUpdate = true
            }
            updateCollectionViewData()
        case .delete:
            DDLogInfo("ChatViewControllerNew/didChange type delete")
            updateCollectionViewData()
        case .update:
            DDLogInfo("ChatViewControllerNew/didChange type update")
            if let chatMessage = anObject as? ChatMessage {
                // Is audio message, is status played return
                if !shouldUpdateAudioCell(chatMessage: chatMessage) {
                    return
                }
                guard var snapshot = dataSource?.snapshot() else { return }
                for item in snapshot.itemIdentifiers {
                    switch item {
                    case .chatMessage(let data):
                        if data.id == chatMessage.id {
                            snapshot.reloadItems([item])
                            let isScrolledTobottom = isScrolledTobottom()
                            self.dataSource?.apply(snapshot, animatingDifferences: false)
                            if isScrolledTobottom {
                                scrollToLastMessage(animated: false)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        default:
            break
        }
    }

    private func isScrolledTobottom() -> Bool {
        return abs(collectionView.contentOffset.y - (collectionView.contentSize.height - (collectionView.bounds.height - collectionView.adjustedContentInset.bottom))) < 1.ulp
    }

    func updateCollectionViewData() {
        DDLogInfo("ChatViewControllerNew/updateCollectionViewData/called")
        var messageRows: [MessageRow] = []
        var snapshot = ChatMessageSnapshot()
        var lastMessageHeaderTime: String?

        // Add messages
        if let chatMessages = chatMessageFetchedResultsController?.fetchedObjects {
            if let fromUserId = fromUserId {
                DDLogInfo("ChatViewControllerNew/updateCollectionViewData/ number of chat messages: \(chatMessages.count) fromUser: \(fromUserId)")
            }

            chatMessages.forEach { chatMessage in
                messageRows.append(MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, timestamp: chatMessage.timestamp)))
            }
        }
        // Add call events
        if let chatCalls = callHistoryFetchedResultsController?.fetchedObjects {
            chatCalls.forEach { chatCall in
                let chatCallData = ChatCallData(userID: chatCall.peerUserID, timestamp: chatCall.timestamp, duration: chatCall.durationMs / 1000, wasSuccessful: chatCall.answered, wasIncoming: chatCall.direction == .incoming, type: chatCall.type, isMissedCall: chatCall.isMissedCall)
                messageRows.append(MessageRow.chatCall(chatCallData))
            }
        }
        // Add events eg user security key changed
        if let chatEvents = chatEventFetchedResultsController?.fetchedObjects {
            chatEvents.forEach { chatEvent in
                if let indexPath = chatEventFetchedResultsController?.indexPath(forObject: chatEvent) {
                    let chatEventData = ChatEventData(timestamp: chatEvent.timestamp, indexPath: indexPath)
                    messageRows.append(MessageRow.chatEvent(chatEventData))
                }
            }
        }
        // Add event - tap to add to contact book
        if shouldShowAddToContactBookCell() {
            messageRows.append(MessageRow.addToContactBook)
        }
        // Sort all messages by timestamp
        messageRows = messageRows.sorted {
            ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture)
        }

        // Insert all messages into snapshot sorted by timestamp and grouped into sections by headerTime
        snapshot.appendSections([ .chats ])
        var tempMessageRows: [MessageRow] = []
        var previousChatMessageData: ChatMessageData? = nil
        for messageRow in messageRows {
            let currentTime = messageRow.headerTime
            if lastMessageHeaderTime != currentTime {
                lastMessageHeaderTime = currentTime
                tempMessageRows.append(MessageRow.timeHeader(currentTime))
            }
            tempMessageRows.append(messageRow)

            // populate dictionary with previous chat info. We need to know if previous message was from same sender, to be able to group consecutive messages from same sender closer together.
            previousChatMessageData = computePreviousChatSenderInfo(previousChatMessageData: previousChatMessageData, messageRow: messageRow)
        }
        // batch add of message Rows
        snapshot.appendItems(tempMessageRows, toSection: .chats)

        if let fromUserId = fromUserId {
            let chatThread = MainAppContext.shared.chatData.chatThread(type: ChatType.oneToOne, id: fromUserId, in: MainAppContext.shared.chatData.viewContext)
            unreadCount = chatThread?.unreadCount ?? 0
            // Only add the unread banner on first launch OR
            // on subsequent launches, if the unread banner is already present, add it with an updated unreadCount
            let shouldAddUnreadCountHeader = (isFirstLaunch || (!isFirstLaunch && unreadMessagesHeaderVisible))
            unreadMessagesHeaderVisible = false
            // Add in the unread count
            if unreadCount > 0, shouldAddUnreadCountHeader {
                var unreadCounter = unreadCount
                var firstUnreadItem: MessageRow?
                let unreadHeaderIndex = snapshot.numberOfItems - Int(unreadCount)
                if unreadHeaderIndex > 0, unreadHeaderIndex < (snapshot.numberOfItems) {
                    unreadMessagesHeaderVisible = true
                    // look for the right place to insert the unread counter header
                    // only count chatMessages and chatCalls for now since only chatMessages and chatCalls
                    // are counted towards unread counts
                    for item in snapshot.itemIdentifiers.reversed() {
                        if item.isCountedInUnreadCounts {
                            unreadCounter -= 1
                        }
                        if unreadCounter == 0 {
                            firstUnreadItem = item
                            break
                        }
                    }
                    if let firstUnreadItem = firstUnreadItem {
                        snapshot.insertItems([MessageRow.unreadCountHeader(Int32(unreadCount))], beforeItem: firstUnreadItem)
                    }
                }
            }
        }
        // Apply the new snapshot
        dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            self.updateScrollingWhenDataChanges()
        }
    }

    // We should not update audio cells while it is playing.
    // This is a bad hack: Ideally we should remove the audio player from the message cell.
    private func shouldUpdateAudioCell(chatMessage: ChatMessage) -> Bool {
        if chatMessage.media?.count == 1, chatMessage.media?.first?.type == .audio, (chatMessage.incomingStatus == .played || chatMessage.incomingStatus == .sentPlayedReceipt) {
            return false
        }
        return true
    }

    private func shouldShowAddToContactBookCell() -> Bool {
        guard let userID = fromUserId else { return false }
        // if contact is already in address book
        if MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: MainAppContext.shared.contactStore.viewContext) { return false }
        // if contact is blocked
         if MainAppContext.shared.privacySettings.blocked.userIds.contains(userID) { return false }
        // If we do not have contacts's push number
        if MainAppContext.shared.contactStore.pushNumber(userID) == nil { return false }

        DDLogInfo("ChatViewControllerNew/shouldShowAddToContactBookCell/will show AddToContactBookCell for user: \(userID) ")
        return true

    }

    private func computePreviousChatSenderInfo(previousChatMessageData: ChatMessageData?, messageRow: MessageRow) -> ChatMessageData? {
        switch messageRow {
        case .chatMessage(let currentChatMessage):
            if let previousChatMessageData = previousChatMessageData {
                previousChatSenderInfo[currentChatMessage.id] = previousChatMessageData.fromUserId == currentChatMessage.fromUserId  ? true : false
            } else {
                previousChatSenderInfo[currentChatMessage.id] = false
            }
            return currentChatMessage
        default:
            return nil
        }
    }

    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        DDLogDebug("ChatViewControllerNew/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId, in: contactsViewContext))]/feedpostId: \(feedPostId ?? "")/feedPostMediaIndex: \(feedPostMediaIndex)")
        self.fromUserId = fromUserId
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex

        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("ChatViewControllerNew/viewDidLoad currentUser: \(MainAppContext.shared.userData.userId) fromUser: \(String(describing: fromUserId))")
        super.viewDidLoad()
        guard let fromUserId = fromUserId else { return }

        // Setup audio and video call buttons
        var rightBarButtons: [UIBarButtonItem] = []

        let phoneImage = UIImage(named: "VoiceCall", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        let phoneButton = UIBarButtonItem(image: phoneImage, style: .plain, target: self, action: #selector(audioCallButtonTapped))
        phoneButton.tintColor = .primaryBlue
        rightBarButtons.append(phoneButton)

        let videoImage = UIImage(named: "VideoCall", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        let videoButton = UIBarButtonItem(image: videoImage, style: .plain, target: self, action: #selector(videoCallButtonTapped))
        rightBarButtons.append(videoButton)

        navigationItem.rightBarButtonItems = rightBarButtons
        // Setup title view
        navigationItem.titleView = titleView
        if let presenceInfo = MainAppContext.shared.chatData.presenceInfoOfUser(fromUserId) {
            titleView.update(with: fromUserId, status: presenceInfo.0, lastSeen: presenceInfo.1)
        } else {
            titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
        }
        titleView.checkIfUnknownContactWithPushNumber(userID: fromUserId)
        
        view.addSubview(collectionView)
        collectionView.constrain(to: view)
        setupUI()
        
        if let feedPostId = feedPostId {
            DDLogInfo("ChatViewControllerNew/loading feed post context")
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
                let contactsViewContext = MainAppContext.shared.contactStore.viewContext
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.rawText, mentions: feedPost.orderedMentions, in: contactsViewContext)
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }), let mediaType = CommonMediaType(rawValue: mediaItem.type.rawValue) {
                    
                    let mediaUrl = mediaItem.mediaURL ?? MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
                    let info = QuotedItemPanel.PostInfo(userID: feedPost.userId,
                                                          text: mentionText?.string ?? "",
                                                     mediaType: mediaType,
                                                     mediaLink: mediaUrl,
                                                     mediaName: mediaItem.name)
                    let panel = QuotedItemPanel()
                    panel.postInfo = info
                    contentInputView.display(context: panel)
                } else {
                    let info = QuotedItemPanel.PostInfo(userID: feedPost.userId,
                                                          text: mentionText?.string ?? "",
                                                     mediaType: nil,
                                                     mediaLink: nil,
                                                     mediaName: nil)
                    let panel = QuotedItemPanel()
                    panel.postInfo = info
                    contentInputView.display(context: panel)
                }
            }
        }

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] fromUserId, status, ts in
                DDLogInfo("ChatViewControllerNew/didGetCurrentChatPresence")
                guard let self = self else { return }
                guard let userId = self.fromUserId, userId == fromUserId else { return }
                DispatchQueue.main.async {
                    self.titleView.update(with: userId, status: status, lastSeen: ts)
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] chatStateInfo in
                guard let self = self else { return }
                DDLogInfo("ChatViewControllerNew/didGetChatStateInfo \(String(describing: chatStateInfo))")
                DispatchQueue.main.async {
                    self.configureTitleViewWithTypingIndicator()
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.didPrivacySettingChange.sink { [weak self] (userID) in
                DDLogInfo("ChatViewControllerNew/didPrivacySettingChange/update header")
                guard let self = self else { return }
                guard userID == self.fromUserId else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.setupOrRefreshHeaderAndFooter()
                }
            }
        )

        // Update name in title view if we just discovered this new user.
        cancellableSet.insert(
            MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] (newUserIDs) in
                DDLogInfo("ChatViewControllerNew/didDiscoverNewUsers/update name if necessary")
                guard let self = self else { return }
                guard let userID = self.fromUserId else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if newUserIDs.contains(userID) {
                        self.titleView.refreshName(for: userID)
                        self.updateCollectionViewData()
                    }
                }
            }
        )
        
        configureTitleViewWithTypingIndicator()
        loadChatDraft(id: fromUserId)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        if let inputAccessoryView = inputAccessoryView {
            let height = inputAccessoryView.systemLayoutSizeFitting(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
            collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: height, right: 0)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Analytics.openScreen(.userChat)

        if let chatWithUserId = self.fromUserId {
            // This marks the initial set of unread messages on first launch as seen.  Any future incoming messages are marked read as they come in.
            MainAppContext.shared.chatData.markSeenMessages(type: .oneToOne, for: chatWithUserId)
            MainAppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)

            UNUserNotificationCenter.current().removeDeliveredChatNotifications(fromUserId: chatWithUserId)
            setupOrRefreshHeaderAndFooter()
        }
        // Add jump to last message button
        view.addSubview(jumpButton)
        jumpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        jumpButtonConstraint = jumpButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(collectionView.contentInset.bottom + 50))
        jumpButtonConstraint?.isActive = true
        
        updateJumpButtonVisibility()
        isFirstLaunch = false

        // Show keyboard if we start the controller as a reply to a feedpost.
        if self.feedPostId != nil {
            self.showKeyboard()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)

       removeTransitionSnapshot()
       // while forwarding messages, we redirect the user to the recipients chat thread.
       // the input text field disappears in this scenario. reloading input views fixes this.
       reloadInputViews()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let id = fromUserId {
            saveChatDraft(id: id)
        }

        pauseVoiceNotes()
        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)

        navigationController?.navigationBar.backItem?.backBarButtonItem = UIBarButtonItem()
        jumpButton.removeFromSuperview()
        applyTransitionSnapshot()
        if let chatWithUserId = fromUserId {
            // TODO only if jump button is not visible.. call below line
            MainAppContext.shared.chatData.markThreadAsRead(type: .oneToOne, for: chatWithUserId)
            // updates the number of chat threads with unread messages
            MainAppContext.shared.chatData.updateUnreadChatsThreadCount()
            // Remove chat notifications from this user when chatViewController for this user is active.
            UNUserNotificationCenter.current().removeDeliveredChatNotifications(fromUserId: chatWithUserId)
        }
    }

    override func viewDidLayoutSubviews() {
        DDLogError("ChatViewControllerNew/viewDidLayoutSubviews scrollToLastMessageOnNextUpdate: \(scrollToLastMessageOnNextUpdate)")
        super.viewDidLayoutSubviews()
        if scrollToUnreadBanner {
            scrollToUnreadBanner = false
            scrollToUnreadBannerCell()
        } else if scrollToLastMessageOnNextUpdate  {
            scrollToLastMessageOnNextUpdate = false
            DDLogDebug("ChatViewControllerNew/updateScrollingWhenDataChanges/scrollToLastMessage/ on send message isFirstLaunch: \(isFirstLaunch)")
            scrollToLastMessage(animated: isFirstLaunch ? false : true)
            return
        } else if didReceiveIncoming, jumpButton.alpha == 0 {
            didReceiveIncoming = false
            DDLogDebug("ChatViewControllerNew/updateScrollingWhenDataChanges/scrollToLastMessage/ on receive message")
            scrollToLastMessage(animated: isFirstLaunch ? false : true)
            return
        }
        didReceiveIncoming = false
    }

    private func removeTransitionSnapshot() {
        transitionSnapshot?.removeFromSuperview()
        contentInputView.isHidden = false
    }

    private func applyTransitionSnapshot() {
        // do this to maintain the blur effect of `contentInputView` during dismissal
        guard let container = transitionCoordinator?.view(forKey: .from) else {
           return
        }

        let snapshot = UIScreen.main.snapshotView(afterScreenUpdates: false)
        container.addSubview(snapshot)

        contentInputView.isHidden = true
        self.transitionSnapshot = snapshot
    }

    private func setupUI() {
        collectionView.dataSource = dataSource
        setupChatMessageFetchedResultsController()
        setupChatEventFetchedResultsController()
        setupCallHistoryFetchedResultsController()
        updateCollectionViewData()
        if unreadCount > 0 {
            scrollToUnreadBanner = true
        } else {
            scrollToLastMessageOnNextUpdate = true
        }
    }

    // MARK: Chat Message FetchedResults
    private func setupChatMessageFetchedResultsController() {
        let fetchChatMessageRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchChatMessageRequest.relationshipKeyPathsForPrefetching = [
            "media",
            "linkPreviews",
            "reactions",
        ]
        guard let fromUserId = fromUserId else {
            return
        }
        let currentUserID = MainAppContext.shared.userData.userId
        fetchChatMessageRequest.predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ && fromUserID = %@)", fromUserId, currentUserID, fromUserId, currentUserID)
        fetchChatMessageRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true)
        ]
        
        chatMessageFetchedResultsController = NSFetchedResultsController<ChatMessage>(fetchRequest: fetchChatMessageRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        chatMessageFetchedResultsController?.delegate = self
        do {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/fetching chat messages for user: \(currentUserID)")
            try chatMessageFetchedResultsController?.performFetch()
        } catch {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/failed to fetch  chat messages for user:\(currentUserID)")
        }
    }

    // MARK: Chat Event FetchedResults
    private func setupChatEventFetchedResultsController() {
        guard let userID = fromUserId else { return }
        let fetchRequest: NSFetchRequest<ChatEvent> = ChatEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userID = %@", userID)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatEvent.timestamp, ascending: true)
        ]

        chatEventFetchedResultsController = NSFetchedResultsController<ChatEvent>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        chatEventFetchedResultsController?.delegate = self
        do {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/fetching chat events from user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
            try chatEventFetchedResultsController!.performFetch()
        } catch {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/failed to fetch  chat events from user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
            return
        }
    }

    private func setupCallHistoryFetchedResultsController() {
        guard let userID = fromUserId else { return }
        let fetchRequest: NSFetchRequest<Core.Call> = Core.Call.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "peerUserID == %@ && endReasonValue !=  %d", userID, EndCallReason.unknown.rawValue)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Core.Call.timestamp, ascending: true)
        ]

        callHistoryFetchedResultsController = NSFetchedResultsController<Core.Call>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        callHistoryFetchedResultsController?.delegate = self
        do {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/fetching chat call info from user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
            try callHistoryFetchedResultsController!.performFetch()
        } catch {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/failed to fetch  chat call info from user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
            return
        }
    }

    private func configureCell(itemCell: MessageCellViewBase, for chatMessage: ChatMessage) {
        let isPreviousMessageFromSameSender = previousChatSenderInfo[chatMessage.id]
        itemCell.configureWith(message: chatMessage, userColorAssignment: .secondaryLabel, parentUserColorAssignment: .secondaryLabel, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender ?? false)
        itemCell.textLabel.delegate = self
        itemCell.chatDelegate = self
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(300))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(300))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)

        // Setup the chat view header as the global header of the collection view.
        let layoutHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(55))
        let layoutHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: layoutHeaderSize, elementKind: MessageChatHeaderView.elementKind, alignment: .top)
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.boundarySupplementaryItems = [layoutHeader]

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration = layoutConfig
        return layout
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    private func configureTitleViewWithTypingIndicator() {
        guard let userID = self.fromUserId else { return }
        let typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .oneToOne, id: userID, fromUserID: userID)

        if typingIndicatorStr == nil && !titleView.isShowingTypingIndicator {
            return
        }

        titleView.showChatState(with: typingIndicatorStr)
    }

    @objc private func audioCallButtonTapped() {
        callButtonTapped(type: .audio)
    }

    @objc private func videoCallButtonTapped() {
        callButtonTapped(type: .video)
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        contentInputView.textView.resignFirstResponder()
    }

    private func callButtonTapped(type: CallType) {
        guard let peerUserID = fromUserId else {
            DDLogInfo("ChatViewControllerNew/callButtonTapped/peerUserID is empty")
            return
        }
        DDLogInfo("ChatViewControllerNew/callButtonTapped/type: \(type)/peerUserID: \(peerUserID)")
        startCallIfPossible(with: peerUserID, type: type)

    }

    private func startCallIfPossible(with peerUserID: UserID, type: CallType) {
        if peerUserID == MainAppContext.shared.userData.userId {
            DDLogInfo("ChatViewControllerNew/startCallIfPossible/cannot call oneself")
            return
        }
        guard MainAppContext.shared.service.isConnected else {
            DDLogInfo("ChatViewControllerNew/startCallIfPossible/service not connected")
            let alert = self.getFailedCallAlert()
            self.present(alert, animated: true)
            return
        }
        MainAppContext.shared.callManager.startCall(to: peerUserID, type: type) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    DDLogInfo("ChatViewControllerNew/startCall/success")
                case .failure:
                    DDLogInfo("ChatViewControllerNew/startCall/failure")
                    let alert = self.getFailedCallAlert()
                    self.present(alert, animated: true)
                }
            }
        }

    }
    
    // MARK: Input view
    public func showKeyboard() {
        contentInputView.textView.becomeFirstResponder()
    }

    lazy var contentInputView: ContentInputView = {
        let inputView = ContentInputView(options: .chat)
        inputView.autoresizingMask = [.flexibleHeight]
        inputView.delegate = self
        if let fromUserId = fromUserId {
            if let url = AudioRecorder.voiceNote(from: MainAppContext.shared.userData.userId, to: fromUserId) {
                inputView.show(voiceNote: url)
            }
        }
        return inputView
    }()

    override var inputAccessoryView: UIView? {
        // Check presentedViewController state to fix the issue that the input accessory view is not dismissed
        // when presenting a view controller modally while the keyboard is onscreen.
        return (presentedViewController?.isBeingDismissed ?? true) ? contentInputView : nil
    }

    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }

    func sendMessage(text: String, media: [PendingMedia], files: [FileSharingData], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, location: ChatLocationProtocol? = nil) {
        guard let sendToUserId = self.fromUserId else { return }

        var chatProperties = Analytics.EventProperties()
        chatProperties[.chatType] = "oneToOne"
        if !text.isEmpty {
            chatProperties[.hasText] = true
        }
        media.forEach { media in
            switch media.type {
            case .audio:
                chatProperties[.attachedAudioCount] = (chatProperties[.attachedAudioCount] as? Int ?? 0) + 1
            case .image:
                chatProperties[.attachedImageCount] = (chatProperties[.attachedImageCount] as? Int ?? 0) + 1
            case .video:
                chatProperties[.attachedVideoCount] = (chatProperties[.attachedVideoCount] as? Int ?? 0) + 1
            case .document:
                chatProperties[.attachedDocumentCount] = (chatProperties[.attachedDocumentCount] as? Int ?? 0) + 1
            }
        }
        chatProperties[.attachedDocumentCount] = (chatProperties[.attachedDocumentCount] as? Int ?? 0) + files.count
        if linkPreviewData != nil {
            chatProperties[.attachedLinkPreviewCount] = 1
        }
        if location != nil {
            chatProperties[.attachedLocationCount] = 1
        }
        if chatReplyMessageID != nil {
            chatProperties[.replyType] = "chatMessage"
        } else if feedPostId != nil {
            chatProperties[.replyType] = "post"
        }
        Analytics.log(event: .sendChatMessage, properties: chatProperties)

        MainAppContext.shared.chatData.sendMessage(chatMessageRecipient: .oneToOneChat(toUserId: sendToUserId, fromUserId: MainAppContext.shared.userData.userId),
                                                   mentionText: MentionText(collapsedText: text, mentionArray: []),
                                                      media: media,
                                                      files: files,
                                            linkPreviewData: linkPreviewData,
                                           linkPreviewMedia: linkPreviewMedia,
                                                   location: location,
                                                 feedPostId: feedPostId,
                                         feedPostMediaIndex: feedPostMediaIndex,
                                         chatReplyMessageID: chatReplyMessageID,
                                   chatReplyMessageSenderID: chatReplyMessageSenderID,
                                 chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)

        feedPostId = nil
        feedPostMediaIndex = 0

        chatReplyMessageID = nil
        chatReplyMessageSenderID = nil
        chatReplyMessageMediaIndex = 0

        contentInputView.reset()
        removeChatDraft()
        if !firstActionHappened {
            didAction()
        }
    }

    private func presentMediaPicker() {
        guard let fromUserDestination = fromUserDestination else { return }

        let vc = MediaPickerViewController(config: .config(with: fromUserDestination)) { [weak self] controller, _, media, cancel in
            guard let self = self else { return }
            if cancel {
                self.dismiss(animated: true)
            } else {
                self.presentComposerViewController(media: media)
            }
        }

        present(UINavigationController(rootViewController: vc), animated: true)

        if !firstActionHappened {
            didAction()
        }
    }

    private func didAction() {
        chatViewControllerDelegate?.chatViewController(self, userActioned: true)
        firstActionHappened = true
    }
    
    @MainActor
    func saveAllMedia(in chatMessage: ChatMessage) async {
        await saveMedia(source: .chat) {
            chatMessage.media?
                .compactMap { (media: CommonMedia) -> (type: CommonMediaType, url: URL)? in
                    if let url = media.mediaURL ?? media.relativeFilePath.map({ MainAppContext.chatMediaDirectoryURL.appendingPathComponent($0, isDirectory: false) }) {
                        return (media.type, url)
                    } else {
                        return nil
                    }
                }
                .filter { (type: CommonMediaType, _: URL) -> Bool in
                    type == .image || type == .video
                } ?? []
        }
    }

    private func setupOrRefreshHeaderAndFooter() {
        guard let userID = fromUserId else { return }
        let isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        if isUserBlocked {
            present(blockedContactSheet, animated: true)
            return
        }
        let isUserInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: MainAppContext.shared.contactStore.viewContext)
        let isPushNumberMessagingAccepted = MainAppContext.shared.contactStore.isPushNumberMessagingAccepted(userID: userID)
        let haveMessagedBefore = MainAppContext.shared.chatData.haveMessagedBefore(userID: userID, in: MainAppContext.shared.chatData.viewContext)
        let haveReceivedMessagesBefore = MainAppContext.shared.chatData.haveReceivedMessagesBefore(userID: userID, in: MainAppContext.shared.chatData.viewContext)

        let pushNumberExist = MainAppContext.shared.contactStore.pushNumber(userID) != nil
        let showUnknownContactActionBanner = !isUserBlocked &&
                                             !isUserInAddressBook &&
                                             !isPushNumberMessagingAccepted &&
                                             !haveMessagedBefore &&
                                             pushNumberExist &&
                                             haveReceivedMessagesBefore

        if showUnknownContactActionBanner {
            DDLogInfo("ChatViewControllerNew/setupOrRefreshHeaderAndFooter/will show Unknown Contact Action Banner")
            present(unknownContactSheet, animated: true)
        } else {
            DDLogInfo("ChatViewControllerNew/setupOrRefreshHeaderAndFooter/ user: \(userID) isUserBlocked: \(isUserBlocked) isUserInAddressBook: \(isUserInAddressBook) isPushNumberMessagingAccepted: \(isPushNumberMessagingAccepted) haveMessagedBefore: \(haveMessagedBefore) pushNumberExist:\(pushNumberExist) haveReceivedMessagesBefore: \(haveReceivedMessagesBefore)")
        }
    }

    private lazy var blockedContactSheet: BlockedContactSheetViewController = {
        let sheet = BlockedContactSheetViewController()

        sheet.unblockAction = { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            guard let userID = self.fromUserId else { return }
            let privacySettings = MainAppContext.shared.privacySettings
            privacySettings.unblock(userID: userID)
        }

        sheet.cancelAction = { [weak self] in
            self?.dismiss(animated: true)
            self?.navigationController?.popViewController(animated: true)
        }

        return sheet
    }()

    private lazy var unknownContactSheet: UnknownContactSheetViewController = {
        let sheet = UnknownContactSheetViewController()

        sheet.acceptAction = { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            guard let userID = self.fromUserId else { return }
            MainAppContext.shared.contactStore.setIsMessagingAccepted(userID: userID, isMessagingAccepted: true)
        }

        sheet.addContactAction = { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            guard let userID = self.fromUserId else { return }
            MainAppContext.shared.contactStore.addUserToAddressBook(userID: userID, presentingVC: self)
        }

        sheet.blockAction = { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            guard let userID = self.fromUserId else { return }
            let viewContext = MainAppContext.shared.contactStore.viewContext
            let blockMessage = Localizations.blockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID, in: viewContext))

            let alert = UIAlertController(title: nil, message: blockMessage, preferredStyle: .actionSheet)
            let button = UIAlertAction(title: Localizations.blockButton, style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                let privacySettings = MainAppContext.shared.privacySettings
                guard let blockedList = privacySettings.blocked else { return }
                privacySettings.block(userID: userID)
            }
            alert.addAction(button)

            let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
            alert.addAction(cancel)

            self.present(alert, animated: true)
        }
        
        sheet.cancelAction = { [weak self] in
            self?.dismiss(animated: true)
            self?.navigationController?.popViewController(animated: true)
        }

        return sheet
    }()

    private func pauseVoiceNotes() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? MessageCellViewAudio {
                cell.pauseVoiceNote()
            }
            if let cell = cell as? MessageCellViewQuoted {
                cell.pauseVoiceNote()
            }
        }
    }

    // MARK : Drafts
    /// Saves the text currently in the `ContentInputView` into `UserDefaults` to be restored on the next time the user opens the view.
    /// - Parameter id: The UserID of the other user in the chat.
    private func saveChatDraft(id: UserID) {
        guard !contentInputView.textView.text.isEmpty else {
            removeChatDraft()
            return
        }

        let draft = ChatDraft(chatID: id, text: contentInputView.textView.text, replyContext: encodeReplyData())
        var draftsArray = [ChatDraft]()

        if let draftsDecoded: [ChatDraft] = try? AppContext.shared.userDefaults.codable(forKey: "chats.drafts") {
            draftsArray = draftsDecoded
        }

        draftsArray.removeAll { existingDraft in
            existingDraft.chatID == draft.chatID
        }

        draftsArray.append(draft)
        try? AppContext.shared.userDefaults.setCodable(draftsArray, forKey: "chats.drafts")
    }
    
    private func encodeReplyData() -> ReplyContext? {
        if let replyMessageID = chatReplyMessageID,
           let replySenderID = chatReplyMessageSenderID,
           let replyMessage = MainAppContext.shared.chatData.chatMessage(with: replyMessageID, in: MainAppContext.shared.chatData.viewContext) {

            let replyMedia: ChatReplyMedia? = {
                let media = replyMessage.orderedMedia
                guard media.count > chatReplyMessageMediaIndex && chatReplyMessageMediaIndex >= 0 else {
                    return nil
                }
                let mediaObject = media[Int(chatReplyMessageMediaIndex)]
                guard let url = mediaObject.mediaURL?.absoluteString else {
                    return nil
                }
                return ChatReplyMedia(type: mediaObject.type, mediaURL: url, name: mediaObject.name)
            }()

            let reply = ReplyContext(replyMessageID: replyMessageID,
                  replySenderID: replySenderID,
                  mediaIndex: chatReplyMessageMediaIndex,
                  text: replyMessage.rawText ?? "",
                  media: replyMedia)

            return reply
        } else if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
                let contactsViewContext = MainAppContext.shared.contactStore.viewContext
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.rawText, mentions: feedPost.orderedMentions, in: contactsViewContext)
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    let mediaType = mediaItem.type
                    let mediaUrl = mediaItem.mediaURL ?? MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)

                    let reply = ReplyContext(feedPostID: feedPostId,
                                             replySenderID: feedPost.userId,
                                             mediaIndex: feedPostMediaIndex,
                                             text: mentionText?.string ?? "",
                                             media: ChatReplyMedia(type: mediaType, mediaURL: mediaUrl.absoluteString))
                    return reply
                } else {
                    let reply = ReplyContext(feedPostID: feedPostId,
                                             replySenderID: feedPost.userId,
                                             mediaIndex: nil,
                                             text: mentionText?.string ?? "",
                                             media: nil)
                    return reply
                }
            }
        }

        return nil
    }

    /// Restores the text from `UserDefaults` into the `ContentInputView` so the user can continue what they last wrote.
    /// - Parameter id: The UserID of the other user in the chat.
    private func loadChatDraft(id: UserID) {
        guard let draftsArray: [ChatDraft] = try? AppContext.shared.userDefaults.codable(forKey: "chats.drafts") else { return }
        guard let draft = draftsArray.first(where: { existingDraft in
            existingDraft.chatID == fromUserId
        }) else { return }

        let mentionText = MentionText(collapsedText: draft.text, mentions: [:])
        contentInputView.set(draft: mentionText)

        if let reply = draft.replyContext {
            handleDraftQuotedReply(reply: reply)
            if let feedPostId = reply.feedPostID {
                self.feedPostId = feedPostId
                feedPostMediaIndex = reply.mediaIndex ?? 0
            } else if let chatReplyMessageID = chatReplyMessageID {
                self.chatReplyMessageID = chatReplyMessageID
                chatReplyMessageSenderID = reply.replySenderID
                chatReplyMessageMediaIndex = reply.mediaIndex ?? 0
            } else {
                DDLogWarn("ChatViewControllerNew/No feedPostId or chatReplyMessageId when restoring draft reply")
            }
        }
    }

    /// Removes any existing drafts for this chat if there are any.
    private func removeChatDraft() {
        var draftsArray: [ChatDraft] = []

        if let draftsDecoded: [ChatDraft] = try? AppContext.shared.userDefaults.codable(forKey: "chats.drafts") {
            draftsArray = draftsDecoded
        }

        draftsArray.removeAll { existingDraft in
            existingDraft.chatID == fromUserId
        }

        try? AppContext.shared.userDefaults.setCodable(draftsArray, forKey: "chats.drafts")
    }
}

// MARK: ChatTitle Delegates
extension ChatViewControllerNew: ChatTitleViewDelegate {
    func chatTitleView(_ chatTitleView: ChatTitleView) {
        guard let userId = fromUserId else { return }
        let userViewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(userViewController, animated: true)
    }
}

// MARK: ChatCallView Delegates
extension ChatViewControllerNew: ChatCallViewDelegate {
    func chatCallView(_ callView: ChatCallView, didTapCallButtonWithData callData: ChatCallData) {
        startCallIfPossible(with: callData.userID, type: callData.type)
    }
}

// MARK: - content input view delegate methods
extension ChatViewControllerNew: ContentInputDelegate {
    func inputView(_ inputView: ContentInputView, possibleMentionsFor input: String) -> [MentionableUser] {
        return []
    }

    func inputView(_ inputView: ContentInputView, isTyping: Bool) {
        guard let userID = fromUserId else { return }
        let state: ChatState = isTyping ? .typing : .available

        MainAppContext.shared.chatData.sendChatState(type: .oneToOne,
                                                       id: userID,
                                                    state: state)
    }

    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        sendMessage(text: content.mentionText.trimmed().collapsedText,
                    media: content.media,
                    files: content.files,
                    linkPreviewData: content.linkPreview?.data,
                    linkPreviewMedia: content.linkPreview?.media)
    }

    func inputView(_ inputView: ContentInputView, didChangeHeightTo height: CGFloat) {
        if let coordinator = transitionCoordinator, coordinator.isInteractive {
            return
        }

        let newInsets = UIEdgeInsets(top: collectionView.contentInset.top,
                                    left: 0,
                                  bottom: (height - view.safeAreaInsets.bottom) + 10,
                                   right: 0)

        var newOffset = collectionView.contentOffset
        newOffset.y += newInsets.bottom - collectionView.contentInset.bottom

        if collectionView.contentInset.bottom != 0, collectionView.contentInset != newInsets {
            // not having the second condition causes inertial scrolling to break
            collectionView.setContentOffset(newOffset, animated: false)
        }

        collectionView.contentInset = newInsets
        collectionView.scrollIndicatorInsets = newInsets

        updateJumpButtonVisibility()
    }

    func inputView(_ inputView: ContentInputView, didClose panel: InputContextPanel) {
        if panel.isKind(of: QuotedItemPanel.self) {
            feedPostId = nil
            feedPostMediaIndex = 0

            chatReplyMessageID = nil
            chatReplyMessageSenderID = nil
            chatReplyMessageMediaIndex = 0
        }
    }

    func inputViewDidSelectCamera(_ inputView: ContentInputView) {
        presentCameraViewController()
    }

    func inputViewContentOptionsMenu(_ inputView: ContentInputView) -> HAMenu.Content {
        HAMenuButton(title: Localizations.photoAndVideoLibrary, image: UIImage(systemName: "photo.fill.on.rectangle.fill")) { [weak self] in
            self?.presentMediaPicker()
        }
        HAMenuButton(title: Localizations.fabAccessibilityCamera, image: UIImage(systemName: "camera.fill")) { [weak self] in
            self?.presentCameraViewController()
        }
        if ServerProperties.enableChatLocationSharing {
            HAMenuButton(title: Localizations.locationSharingNavTitle, image: UIImage(systemName: "location.fill")) { [weak self] in
                self?.presentLocationSharingViewController()
            }
        }

        if ServerProperties.isFileSharingEnabled {
            HAMenuButton(title: Localizations.addMediaOptionDocument, image: UIImage(systemName: "doc.fill")) { [weak self] in
                self?.presentFilePicker()
            }
        }
    }
    
    private func presentLocationSharingViewController() {
        let locationSharingViewController = LocationSharingViewController()
        
        locationSharingViewController.viewModel.sharePlacemark
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] placemark in
                self?.dismiss(animated: true)
                self?.sendMessage(text: "", media: [], files: [], linkPreviewData: nil, linkPreviewMedia: nil, location: ChatLocation(placemark: placemark))
            }
            .store(in: &cancellableSet)

        let navigationController = UINavigationController(rootViewController: locationSharingViewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }

        present(navigationController, animated: true)
    }
    
    private func presentCameraViewController() {
        let vc = NewCameraViewController(presets: [.photo], initialPresetIndex: 0)
        vc.delegate = self
        let nc = UINavigationController(rootViewController: vc)
        nc.modalPresentationStyle = .fullScreen
        nc.overrideUserInterfaceStyle = .dark

        present(nc, animated: true)
    }

    private func presentComposerViewController(media: [PendingMedia]) {
        guard let fromUserDestination = fromUserDestination else { return }

        let input = MentionInput(text: contentInputView.textView.text, mentions: MentionRangeMap(), selectedRange: NSRange())
        let composerController = ComposerViewController(config: .config(with: fromUserDestination),
                                                        type: .library,
                                                        showDestinationPicker: false,
                                                        input: input,
                                                        media: media,
                                                        voiceNote: nil) { [weak self] controller, result, success in
            guard let self = self else { return }

            let text = result.text?.trimmed().collapsedText ?? ""

            if success {
                self.sendMessage(text: text,
                                 media: media,
                                 files: [],
                                 linkPreviewData: result.linkPreviewData,
                                 linkPreviewMedia: result.linkPreviewMedia)
                self.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
            } else {
                controller.dismiss(animated: false)

                if let viewControllers = (self.presentedViewController as? UINavigationController)?.viewControllers {
                    if let mediaPickerController = viewControllers.last as? MediaPickerViewController {
                        mediaPickerController.reset(destination: nil, selected: media)
                    }
                }
            }
        }

        let presenter = presentedViewController ?? self
        presenter.present(UINavigationController(rootViewController: composerController), animated: false)
    }

    private func presentFilePicker() {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        vc.delegate = self
        present(vc, animated: true)

        if !firstActionHappened {
            didAction()
        }
    }

    func inputView(_ inputView: ContentInputView, didInterrupt recorder: AudioRecorder) {
        guard
            let fromID = fromUserId,
            let url = recorder.saveVoiceNote(from: MainAppContext.shared.userData.userId, to: fromID)
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.contentInputView.show(voiceNote: url)
        }
    }

    func inputViewMicrophoneAccessDenied(_ inputView: ContentInputView) {
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle,
                                    message: Localizations.micAccessDeniedMessage,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        present(alert, animated: true)
    }

    func inputViewMicrophoneAccessDeniedDuringCall(_ inputView: ContentInputView) {
        let alert = UIAlertController(title: Localizations.failedActionDuringCallTitle,
                                    message: Localizations.failedActionDuringCallNoticeText,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { _ in }))
        present(alert, animated: true)
    }

    func inputView(_ inputView: ContentInputView, didPaste image: PendingMedia) {
        presentComposerViewController(media: [image])
    }
}

// MARK: - CameraViewControllerDelegate methods

extension ChatViewControllerNew: CameraViewControllerDelegate {

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: [PendingMedia]) {
        viewController.dismiss(animated: true) { [weak self] in
            self?.presentComposerViewController(media: media)
        }
    }

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {

    }

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], with preset: CameraPreset) {
        guard let image = results.first?.image else {
            return
        }

        let media = PendingMedia(type: .image)
        media.image = image

        viewController.dismiss(animated: true) { [weak self] in
            self?.presentComposerViewController(media: [media])
        }
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {
        let media = PendingMedia(type: .video)
        media.originalVideoURL = url
        media.fileURL = url

        viewController.dismiss(animated: true) { [weak self] in
            self?.presentComposerViewController(media: [media])
        }
    }
}

// MARK: PostComposerView Delegates
extension ChatViewControllerNew: PostComposerViewDelegate {
    func composerDidTapLinkPreview(controller: PostComposerViewController, url: URL) {
        URLRouter.shared.handleOrOpen(url: url)
    }

    func composerDidTapShare(controller: PostComposerViewController,
                            destination: ShareDestination,
                            mentionText: MentionText,
                                  media: [PendingMedia],
                        linkPreviewData: LinkPreviewData? = nil,
                       linkPreviewMedia: PendingMedia? = nil) {

        sendMessage(text: mentionText.trimmed().collapsedText, media: media, files: [], linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
        view.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }

    func composerDidTapBack(controller: PostComposerViewController, destination: ShareDestination, media: [PendingMedia], voiceNote: PendingMedia?) {
        controller.dismiss(animated: false)

        let presentedVC = self.presentedViewController

        if let viewControllers = (presentedVC as? UINavigationController)?.viewControllers {
            if let mediaPickerController = viewControllers.last as? MediaPickerViewController {
                mediaPickerController.reset(destination: nil, selected: media)
            }
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {

    }
}

extension ChatViewControllerNew: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        documentInteractionController = nil

        // Workaround for bug when interactively dismissing document (content input view animates into view extremely slowly)
        contentInputView.superview?.layer.removeAllAnimations()
    }
}

extension ChatViewControllerNew: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        DDLogInfo("ChatViewControllerNew/documentPickerWasCancelled")
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        DDLogInfo("ChatViewControllerNew/didPickDocuments")
        // TODO: handle multiple files
        guard let documentURL = urls.first else { return }
        guard let threadID = fromUserId else { return }
        guard documentURL.startAccessingSecurityScopedResource() else {
            DDLogError("Unable to access security scoped resource [\(documentURL)]")
            return
        }
        defer {
            documentURL.stopAccessingSecurityScopedResource()
        }
        let filename = documentURL.lastPathComponent

        let localURL = MainAppContext.commonMediaStoreURL
            .appendingPathComponent(threadID, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)

        // create intermediate directories
        if !FileManager.default.fileExists(atPath: localURL.path) {
            do {
                try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            } catch {
                DDLogError(error.localizedDescription)
            }
        }

        try? FileManager.default.copyItem(at: documentURL, to: localURL)
        let fileData = FileSharingData(
            name: filename,
            size: (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
            localURL: localURL)

        sendMessage(text: "", media: [], files: [fileData], linkPreviewData: nil, linkPreviewMedia: nil)
    }
}

extension ChatViewControllerNew: MessageViewChatDelegate, ReactionViewControllerChatDelegate, ReactionListViewControllerDelegate {
    func showMessageInfo(for chatMessage: Core.ChatMessage) {
        // no op
    }

    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID) {

    }

    func messageView(_ messageViewCell: MessageCellViewBase, for chatMessageID: ChatMessageID, didTapMediaAtIndex index: Int) {
        let viewContext = MainAppContext.shared.chatData.viewContext
        guard let message = MainAppContext.shared.chatData.chatMessage(with: chatMessageID, in: viewContext) else { return }

        contentInputView.textView.resignFirstResponder()

        if message.orderedMedia.count == 1 {
            let controller = MediaExplorerController(media: message.orderedMedia, index: index, canSaveMedia: true, source: .chat)
            controller.animatorDelegate = self

            present(controller, animated: true)
        } else if message.orderedMedia.count > 1 {
            guard let userID = fromUserId else { return }
            let contactsViewContext = MainAppContext.shared.contactStore.viewContext
            let controller = ChatMediaListViewController(name: MainAppContext.shared.contactStore.fullName(for: userID, in: contactsViewContext), message: message, index: index)
            controller.animatorDelegate = self

            present(controller.withNavigationController(), animated: true)
        }
    }

    func messageView(_ messageViewCell: MessageCellViewBase, didLongPressOn chatMessage: ChatMessage) {
        contentInputView.textView.resignFirstResponder()
        guard let messageViewCellSuperview = messageViewCell.messageRow.superview else {
            return
        }
        guard let snapshotView = messageViewCell.messageRow.snapshotView(afterScreenUpdates: true) else {
            return
        }
        let convertedFrame = view.convert(messageViewCell.messageRow.frame, from: messageViewCellSuperview)
        snapshotView.frame = convertedFrame
        let reactionView = ReactionViewController(messageViewCell: snapshotView, chatMessage: chatMessage, userBelongsToGroup: true)
        reactionView.chatDelegate = self
        reactionView.modalPresentationStyle = .overFullScreen
        reactionView.modalTransitionStyle = .crossDissolve
        self.present(reactionView, animated: false)
    }
    
    func messageView(_ messageViewCell: MessageCellViewBase, showReactionsFor chatMessage: ChatMessage) {
        if ServerProperties.chatReactions {
            let reactionList = ReactionListViewController(chatMessage: chatMessage)
            reactionList.delegate = self
            let navigationController = UINavigationController(rootViewController: reactionList)
            if let sheet = navigationController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
            }
            self.present(navigationController, animated: true)
        }
    }

    func messageView(_ messageViewCell: MessageCellViewBase, forwardingMessage chatMessage: ChatMessage) {
        handleForwarding(msg: chatMessage)
    }
    
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo chatMessageID: ChatMessageID) {
        scrollToMessage(id: chatMessageID, animated: true, highlightAfterScroll: true)
    }

    func messageView(_ messageViewCell: MessageCellViewBase, openPost feedPostId: String) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext, archived: true) else {
            DDLogWarn("ChatViewControllerNew/Quoted feed post \(feedPostId) not found")
            return
        }

        if feedPost.status == .retracted || feedPost.status == .expired {
            return
        }
        
        let vc = feedPost.isMoment ? MomentViewController(post: feedPost, shouldFetchOtherMoments: false) : PostViewController.viewController(for: feedPost)
        present(vc, animated: true)
    }

    func messageView(_ messageViewCell: MessageCellViewBase, openDocument documentURL: URL) {
        documentInteractionController = UIDocumentInteractionController(url: documentURL)
        documentInteractionController?.delegate = self
        documentInteractionController?.presentPreview(animated: true)
    }

    func messageView(_ messageViewCell: MessageCellViewBase, replyToChat chatMessage: ChatMessage) {
        guard chatMessage.incomingStatus != .retracted else { return }
        guard ![.retracting, .retracted].contains(chatMessage.outgoingStatus) else { return }
        handleQuotedReply(msg: chatMessage)
    }
   
    func handleMessageSave(_ reactionViewController: ReactionViewController, chatMessage: ChatMessage) {
        Task{
            await self.saveAllMedia(in: chatMessage)
        }
    }


    func messageView(_ messageViewCell: MessageCellViewBase, didCompleteVoiceNote userId: UserID) {
        guard let chatMessage = messageViewCell.chatMessage else { return }
        playVoiceNote(after: chatMessage)
    }

    private func playVoiceNote(after chatMessage: ChatMessage) {
        guard var nextIndexPath = dataSource?.indexPath(for: MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, timestamp: chatMessage.timestamp))) else { return }
        nextIndexPath.row += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + waitForCellDelay) {
            guard let cell = self.collectionView.cellForItem(at: nextIndexPath) else { return }
            let audioCell = (cell as? MessageCellViewAudio != nil) ? (cell as? MessageCellViewAudio) : (cell as? MessageCellViewQuoted)
            if let audioCell = audioCell {
                // Only auto play the next voice note if is from the same sender as the audio note that was just played.
                guard audioCell.chatMessage?.fromUserId == chatMessage.fromUserId else { return }
                self.collectionView.scrollToItem(at: nextIndexPath, at: .centeredVertically, animated: true)
                audioCell.playVoiceNote()
            }
        }
    }

    func handleQuotedReply(msg chatMessage: ChatMessage) {
        chatReplyMessageID = chatMessage.id
        chatReplyMessageSenderID = chatMessage.fromUserId

        guard let userID = chatReplyMessageSenderID else { return }

        if let mediaItem = chatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
            let mediaUrl = mediaItem.mediaURL ?? MainAppContext.chatMediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
            let info = QuotedItemPanel.PostInfo(userID: userID,
                                                 text: chatMessage.rawText ?? "",
                                            mediaType: mediaItem.type,
                                            mediaLink: mediaUrl,
                                            mediaName: mediaItem.name)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        } else {
            let info = QuotedItemPanel.PostInfo(userID: userID,
                                                 text: chatMessage.rawText ?? "",
                                            mediaType: nil,
                                            mediaLink: nil,
                                            mediaName: nil)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        }
        contentInputView.textView.becomeFirstResponder()
    }

    func handleForwarding(msg chatMessage: ChatMessage) {
        let vc = DestinationPickerViewController(config: .forwarding, destinations: []) { controller, destinations in
            controller.dismiss(animated: true)

            guard destinations.count > 0 else { return }
            // TODO: forward msg to feed, groups or other contacts
            var toUserIds: [String] = []
            var toChatGroupIDs: [String] = []
            for selectedDestination in destinations {
                switch selectedDestination {
                case .contact(id: let id, name: _, phone: _):
                    toUserIds.append(id)
                case .group(id: let id, _, _):
                    toChatGroupIDs.append(id)
                default:
                    break
                }
            }
            MainAppContext.shared.chatData.forwardChatMessages(toUserIds: toUserIds, toChatGroupIDs: toChatGroupIDs, chatMessage: chatMessage)
            if toUserIds.count == 1, toChatGroupIDs.count == 0, let toUserId = toUserIds.first {
                let chatVC = ChatViewControllerNew(for: toUserId)
                self.navigationController?.pushViewController(chatVC, animated: true)
            } else if toUserIds.count == 0, toChatGroupIDs.count == 1, let toChatGroupID = toChatGroupIDs.first {
                if let group = MainAppContext.shared.chatData.chatGroup(groupId: toChatGroupID, in: MainAppContext.shared.chatData.viewContext) {
                    let groupChatVC = GroupChatViewController(for: group)
                    self.navigationController?.pushViewController(groupChatVC, animated: true)
                }
            }
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func handleDraftQuotedReply(reply: ReplyContext) {
        if let mediaURLString = reply.media?.mediaURL, let mediaURL = URL(string: mediaURLString) {
            let info = QuotedItemPanel.PostInfo(userID: reply.replySenderID,
                                                  text: reply.text,
                                             mediaType: reply.media?.type,
                                             mediaLink: mediaURL,
                                             mediaName: reply.media?.name)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        } else {
            let info = QuotedItemPanel.PostInfo(userID: reply.replySenderID,
                                                  text: reply.text,
                                             mediaType: nil,
                                             mediaLink: nil,
                                             mediaName: nil)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        }
    }

    func showDeletionConfirmationMenu(for chatMessage: ChatMessage) {
        let chatMessageId = chatMessage.id
        let alertController = UIAlertController(title: Localizations.chatDeleteTitle, message: nil, preferredStyle: .actionSheet)

        if chatMessage.fromUserId == AppContext.shared.userData.userId, [.sentOut, .delivered, .seen, .played].contains(chatMessage.outgoingStatus) {
            alertController.addAction(UIAlertAction(title: Localizations.chatDeleteForEveryone, style: .destructive) { _ in
                MainAppContext.shared.chatData.retractChatMessage(chatMessage: chatMessage, messageToRetractID: chatMessageId)
                
            })
            
        }
        
        alertController.addAction(UIAlertAction(title: Localizations.chatDeleteForMe, style: .destructive) { _ in
            MainAppContext.shared.chatData.deleteChatMessage(with: chatMessageId)
        })

        alertController.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(alertController, animated: true)
    }
    
    func sendReaction(chatMessage: ChatMessage, reaction: String) {
        guard let sendToUserId = self.fromUserId else { return }
        Analytics.log(event: .sendChatMessageReaction, properties: [.chatType: "oneToOne"])
        let reactionMessageRecipient: ChatMessageRecipient = .oneToOneChat(toUserId: sendToUserId, fromUserId: AppContext.shared.userData.userId)
        MainAppContext.shared.chatData.sendReaction(chatMessageRecipient: reactionMessageRecipient,
                                                    reaction: reaction,
                                                    chatMessageID: chatMessage.id)
    }

    func removeReaction(reaction: CommonReaction) {
        // Users can only remove reactions they have authored
        if reaction.fromUserID == AppContext.shared.userData.userId {
            MainAppContext.shared.chatData.retractReaction(commonReaction: reaction, reactionToRetractID: reaction.id)
        }
    }

    // MARK : Scrolling
    private func scrollToMessage(id: ChatMessageID, animated: Bool = false, highlightAfterScroll: Bool = false) {
        guard let indexPath = indexPath(for: id) else {
            DDLogDebug("ChatViewControllerNew/scrollToMessage failed for ChatMessageID: \(id)")
            return
        }
        DDLogDebug("ChatViewControllerNew/scrollToMessage ChatMessageID:\(id) animated:\(animated)")
        scrollToItemAtIndexPath(indexPath: indexPath, animated: animated)

        if highlightAfterScroll {
            highlightMessage(id: id)
        }
    }

    private func scrollToItemAtIndexPath(indexPath: IndexPath, animated: Bool) {
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        if !animated {
            // Attempt to get a more exact position than provided from estimated sizes.
            // Not compatible with animation, but useful for finding initial scroll positions
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
    }

    private func highlightMessage(id: ChatMessageID) {
        guard let indexPath = indexPath(for: id),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCellViewBase else {
            DDLogDebug("ChatViewControllerNew/highlightMessage failed for \(id)")
            return
        }

        DDLogDebug("ChatViewControllerNew/highlightMessage: \(id)")
        cell.runHighlightAnimation()
    }

    private func indexPath(for id: ChatMessageID) -> IndexPath? {
        guard let chatMessage = chatMessageFetchedResultsController?.fetchedObjects?.first(where: { $0.id == id }) else {
            return nil
        }
        return dataSource?.indexPath(for: MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, timestamp: chatMessage.timestamp)))
    }

    private func updateScrollingWhenDataChanges() {
        jumpButtonUnreadCount = unreadCount
        updateJumpButtonText()
        view.setNeedsLayout()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButtonVisibility()
    }

    func updateJumpButtonVisibility() {
        let hideJumpButton: Bool
        if let lastMessageIndexPath = lastMessageIndexPath(), let lastCommentLayoutAttributes = collectionView.layoutAttributesForItem(at: lastMessageIndexPath) {
            // Display jump button when the last message is no longer visible
            let insetBounds = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            hideJumpButton = insetBounds.intersects(lastCommentLayoutAttributes.frame)
        } else {
            hideJumpButton = true
        }

        let jumpButtonAlpha: CGFloat = hideJumpButton ? 0.0 : 1.0
        if jumpButton.alpha != jumpButtonAlpha {
            UIView.animate(withDuration: 0.25, delay: 0.0, options: .curveEaseInOut) {
                self.jumpButton.alpha = jumpButtonAlpha
            }
        }

        // Mark all messages as read on scrolling to bottom
        if hideJumpButton {
            jumpButtonUnreadCount = 0
            updateJumpButtonText()
        }

        jumpButtonConstraint?.constant = -(collectionView.contentInset.bottom + 50)
    }

    private func updateJumpButtonText() {
        jumpButtonUnreadCountLabel.text = jumpButtonUnreadCount > 0 ? String(jumpButtonUnreadCount) : nil
    }

    @objc private func scrollToLastMessage(animated: Bool) {
        guard let lastMessageIndexPath = lastMessageIndexPath() else {
            return
        }
        scrollToItemAtIndexPath(indexPath: lastMessageIndexPath, animated: animated)
        updateJumpButtonText()
    }

    private func lastMessageIndexPath() -> IndexPath? {
        let lastSectionIndex = collectionView.numberOfSections - 1
        guard lastSectionIndex >= 0 else { return nil }
        let lastRowIndex = collectionView.numberOfItems(inSection: lastSectionIndex) - 1
        guard lastRowIndex >= 0 else {  return nil }
        return IndexPath(row: lastRowIndex, section: lastSectionIndex)
    }

    private func scrollToUnreadBannerCell() {
        DDLogDebug("ChatViewControllerNew/scrollToUnreadBannerCell")
        guard let indexPath = dataSource?.indexPath(for: MessageRow.unreadCountHeader(Int32(unreadCount))) else { return }
        scrollToItemAtIndexPath(indexPath: indexPath, animated: false)
        updateJumpButtonText()
    }
}

// MARK: MediaListAnimatorDelegate
extension ChatViewControllerNew: MediaListAnimatorDelegate {
    var transitionViewRadius: CGFloat {
        10
    }

    func scrollToTransitionView(at index: MediaIndex) {
        guard let chatMessageID = index.chatMessageID else { return }
        scrollToMessage(id: chatMessageID)
    }

    func getTransitionView(at index: MediaIndex) -> UIView? {
        guard let chatMessageID = index.chatMessageID else { return nil }
        guard let indexPath = indexPath(for: chatMessageID) else { return nil }

        if let cell = collectionView.cellForItem(at: indexPath) as? MessageCellViewQuoted {
            return cell.mediaView.imageView(at: index.index) ?? cell.mediaView
        } else if let cell = collectionView.cellForItem(at: indexPath) as? MessageCellViewMedia {
            return cell.mediaView.imageView(at: index.index) ?? cell.mediaView
        }

        return nil
    }
}

// MARK: - quoted item panel implementation
fileprivate class QuotedItemPanel: UIView, InputContextPanel {
    struct PostInfo {
        let userID: String
        let text: String
        let mediaType: CommonMediaType?
        let mediaLink: URL?
        let mediaName: String?
    }

    var postInfo: PostInfo? {
        didSet { configure() }
    }

    override init(frame: CGRect) {
        super.init(frame: .zero)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            stackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8)
        ])
    }

    required init(coder: NSCoder) {
        fatalError("Feed post panel coder init not implemented...")
    }

    private func configure() {
        guard let postInfo = postInfo else {
            return
        }

        quoteFeedPanelNameLabel.text = MainAppContext.shared.contactStore.fullName(for: postInfo.userID, in: MainAppContext.shared.contactStore.viewContext)
        let ham = HAMarkdown(font: UIFont.preferredFont(forTextStyle: .subheadline), color: UIColor.secondaryLabel)
        quoteFeedPanelTextLabel.attributedText = ham.parse(postInfo.text)

        if postInfo.userID == MainAppContext.shared.userData.userId {
            subviews.first?.backgroundColor = .quotedMessageOwnBackground
        } else {
            subviews.first?.backgroundColor = .quotedMessageNotOwnReplyBackground
        }

        if let mediaType = postInfo.mediaType, let mediaLink = postInfo.mediaLink {
            configureMedia(mediaType, url: mediaLink, name: postInfo.mediaName)
        }
    }

    private func configureMedia(_ mediaType: CommonMediaType, url: URL, name: String? = nil) {
        quoteFeedPanelImage.isHidden = false
        switch mediaType {
        case .image:
            if let image = UIImage(contentsOfFile: url.path) {
                quoteFeedPanelImage.contentMode = .scaleAspectFill
                quoteFeedPanelImage.image = image
            }
        case .video:
            if let image = VideoUtils.videoPreviewImage(url: url) {
                quoteFeedPanelImage.contentMode = .scaleAspectFill
                quoteFeedPanelImage.image = image
            }
        case .audio:
            quoteFeedPanelImage.isHidden = true
            let text = NSMutableAttributedString()
            if let icon = UIImage(named: "Microphone")?.withTintColor(.systemGray) {
                let attachment = NSTextAttachment(image: icon)
                attachment.bounds = CGRect(x: 0, y: -3, width: 16, height: 16)
                text.append(NSAttributedString(attachment: attachment))
            }

            text.append(NSAttributedString(string: Localizations.chatMessageAudio))

            if FileManager.default.fileExists(atPath: url.path) {
                let seconds = AVURLAsset(url: url).duration.seconds
                let duration = ContentInputView.durationFormatter.string(from: seconds) ?? ""
                text.append(NSAttributedString(string: " (" + duration + ")"))
            }

            quoteFeedPanelTextLabel.attributedText = text.with(font: UIFont.preferredFont(forTextStyle: .subheadline),
                                                              color: UIColor.secondaryLabel)
        case .document:
            quoteFeedPanelImage.isHidden = true
            let displayText: String = {
                guard let name = name, !name.isEmpty else {
                    return Localizations.chatMessageDocument
                }
                return name
            }()
            let attrString: NSMutableAttributedString = {
                guard let icon = UIImage(systemName: "doc") else {
                    return NSMutableAttributedString(string: "📄")
                }
                return NSMutableAttributedString(attachment: NSTextAttachment(image: icon))
            }()
            attrString.append(NSAttributedString(string: " \(displayText)"))

            quoteFeedPanelTextLabel.attributedText = attrString
        }
    }

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(quoteFeedPanelTextMediaContent)
        stack.addArrangedSubview(closeButton)
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 8

        stack.layer.cornerRadius = 8
        stack.clipsToBounds = true

        return stack
    }()

    private lazy var quoteFeedPanelTextMediaContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelImage, quoteFeedPanelTextContent ])
        view.axis = .horizontal
        view.alignment = .top
        view.spacing = 3

        view.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        quoteFeedPanelImage.widthAnchor.constraint(equalToConstant: 60).isActive = true
        quoteFeedPanelImage.heightAnchor.constraint(equalToConstant: 60).isActive = true

        return view
    }()

    private lazy var quoteFeedPanelTextContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelNameLabel, quoteFeedPanelTextLabel ])
        view.axis = .vertical
        view.spacing = 3
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var quoteFeedPanelNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor.label

        return label
    }()

    private lazy var quoteFeedPanelTextLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = UIColor.secondaryLabel

        return label
    }()

    private lazy var quoteFeedPanelImage: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        imageView.layer.cornerRadius = 2
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        imageView.isHidden = true

        return imageView
    }()

    private(set) lazy var closeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 10)
        button.tintColor = UIColor.systemGray
        button.setContentHuggingPriority(.required, for: .horizontal)

        return button
    }()
}

// MARK: ChatHeader Delegates
extension ChatViewControllerNew: MessageChatHeaderViewDelegate {
    func messageChatHeaderViewOpenEncryptionBlog(_ messageChatHeaderView: MessageChatHeaderView) {
        let viewController = SFSafariViewController(url: URL(string: "https://halloapp.com/blog/encrypted-chat")!)
        present(viewController, animated: true)
    }
}

extension ChatViewControllerNew: MessageChatEventViewDelegate, UserActionHandler {
    func messageChatHeaderViewAddToContacts(_ messageCellViewEvent: MessageCellViewEvent) {
        guard let fromUserId = fromUserId else { return }
        handle(action: .addContact(fromUserId))
    }
}

// MARK: CNContact Delegates
extension ChatViewControllerNew: CNContactViewControllerDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: ChatCallView Delegates
extension ChatViewControllerNew: MessageCellViewCallDelegate {
    func chatCallView(_ callView: MessageCellViewCall, didTapCallButtonWithData callData: ChatCallData) {
        startCallIfPossible(with: callData.userID, type: callData.type)
    }
}

fileprivate extension NSFetchedResultsController {
    @objc func optionalObjectfor(at indexPath: IndexPath) -> AnyObject? {
        guard let sections = sections, sections.count > indexPath.section else { return nil }
        let sectionInfo = sections[indexPath.section]
        guard sectionInfo.numberOfObjects > indexPath.row else { return nil }
        return object(at: indexPath)
    }
}

extension ChatViewControllerNew: TextLabelDelegate {
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
}

extension Localizations {

    static var chatDeleteTitle: String {
        NSLocalizedString("chat.delete.title", value: "Delete selected message?", comment: "Title of deletion menu")
    }

    static var chatDeleteForMe: String {
        NSLocalizedString("chat.delete.me", value: "Delete for me", comment: "Button to locally delete a chat message")
    }

    static var chatDeleteForEveryone: String {
        NSLocalizedString("chat.delete.everyone", value: "Delete for everyone", comment: "Button to retract a chat message for everyone")
    }

    static var addMediaOptionDocument: String {
        NSLocalizedString("add.media.option.document", value: "Document", comment: "Menu option for adding generic file")
    }
}
