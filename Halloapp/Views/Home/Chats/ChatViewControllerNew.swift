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

fileprivate struct ChatMsgData {
    let id: String
    let cellHeight: Int16
    let outgoingStatus: ChatMessage.OutgoingStatus
    let incomingStatus: ChatMessage.IncomingStatus
    let timestamp: Date?
    let indexPath: IndexPath
}

fileprivate enum MessageRow: Hashable, Equatable {
    case chatMessage(ChatMessage)
    case retracted(ChatMessage)
    case media(ChatMessage)
    case audio(ChatMessage)
    case text(ChatMessage)
    case linkPreview(ChatMessage)
    case quoted(ChatMessage)
    case unreadCountHeader(Int32)
    case chatCall(ChatCallData)
    case chatEvent(ChatEvent)
    case addToContactBook

    var timestamp: Date? {
        switch self {
        case .chatEvent(let data):
            return data.timestamp
        case .chatMessage(let data), .retracted(let data), .media(let data), .audio(let data), .text(let data), .linkPreview(let data), .quoted(let data):
            return data.timestamp
        case .chatCall(let data):
            return data.timestamp
        case .addToContactBook:
            return Calendar.current.startOfDay(for: Date())
        case .unreadCountHeader(_):
            return nil
        }
    }
    
    var headerTime: String {
        switch self {
        case .chatEvent(let data):
            return data.timestamp.chatMsgGroupingTimestamp(Date())
        case .chatMessage(let data), .retracted(let data), .media(let data), .audio(let data), .text(let data), .linkPreview(let data), .quoted(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .chatCall(let data):
            return data.timestamp?.chatMsgGroupingTimestamp(Date()) ?? ""
        case .addToContactBook:
            let time = timestamp ?? Calendar.current.startOfDay(for: Date())
            return  time.chatMsgGroupingTimestamp(Date())
        case .unreadCountHeader(_):
            return ""
        }
    }

    // not all chat messages are counted when displaying unread counts.
    // in order to insert the unread bannber at the right location, we need this property
    var isCountedInUnreadCounts: Bool {
        switch self {
        case .chatMessage(_), .retracted(_), .media(_), .audio(_), .text(_), .linkPreview(_), .quoted(_), .unreadCountHeader(_), .chatCall(_):
            return true
        case .chatEvent(_), .addToContactBook:
            return false
        }
    }
}


class ChatViewControllerNew: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate {

    weak var chatViewControllerDelegate: ChatViewControllerDelegate?

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

    fileprivate typealias ChatDataSource = UICollectionViewDiffableDataSource<String, MessageRow>
    fileprivate typealias ChatMessageSnapshot = NSDiffableDataSourceSnapshot<String, MessageRow>

    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let messageCellViewTextReuseIdentifier = "MessageCellViewText"
    static private let messageCellViewMediaReuseIdentifier = "MessageCellViewMedia"
    static private let messageCellViewAudioReuseIdentifier = "MessageCellViewAudio"
    static private let messageCellViewLinkPreviewReuseIdentifier = "MessageCellViewLinkPreview"
    static private let messageCellViewQuotedReuseIdentifier = "MessageCellViewQuoted"
    static private let messageCellViewEventReuseIdentifier = "MessageCellViewEvent"
    static private let messageCellViewCallReuseIdentifier = "MessageCellViewCall"

    private var chatMessageFetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var chatEventFetchedResultsController: NSFetchedResultsController<ChatEvent>?
    private var callHistoryFetchedResultsController: NSFetchedResultsController<Core.Call>?

    private var transitionSnapshot: UIView?

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
        collectionView.register(MessageCellViewLinkPreview.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewLinkPreviewReuseIdentifier)
        collectionView.register(MessageCellViewQuoted.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewQuotedReuseIdentifier)
        collectionView.register(MessageUnreadHeaderView.self, forCellWithReuseIdentifier: MessageUnreadHeaderView.elementKind)
        collectionView.register(MessageCellViewEvent.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewEventReuseIdentifier)
        collectionView.register(MessageCellViewCall.self, forCellWithReuseIdentifier: ChatViewControllerNew.messageCellViewCallReuseIdentifier)
        collectionView.register(MessageChatHeaderView.self, forSupplementaryViewOfKind: MessageChatHeaderView.elementKind, withReuseIdentifier: MessageChatHeaderView.elementKind)
        collectionView.register(MessageTimeHeaderView.self, forSupplementaryViewOfKind: MessageTimeHeaderView.elementKind, withReuseIdentifier: MessageTimeHeaderView.elementKind)
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var dataSource: ChatDataSource = {
        let dataSource = ChatDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, messageRow) -> UICollectionViewCell? in
                switch messageRow {
                case .chatMessage(let chatMessage), .retracted(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageViewCellReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageViewCell, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .media(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageCellViewMediaReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewMedia, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .audio(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageCellViewAudioReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewAudio, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .linkPreview(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageCellViewLinkPreviewReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewLinkPreview, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .quoted(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageCellViewQuotedReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewQuoted, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .text(let chatMessage):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatViewControllerNew.messageCellViewTextReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewText, let self = self {
                        self.configureCell(itemCell: itemCell, for: chatMessage)
                    }
                    return cell
                case .chatEvent(let chatEvent):
                    // Check why this is needed
//                    guard let chatEvent = chatEventFetchedResultsController?.optionalObject(at: chatEvent.indexPath) as? ChatEvent else { break }

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
                }
                return UICollectionViewCell()
            })
        dataSource.supplementaryViewProvider = { [weak self] ( view, kind, index) in
            if kind == MessageTimeHeaderView.elementKind {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageTimeHeaderView.elementKind, for: index)
                if let messageTimeHeaderView = headerView as? MessageTimeHeaderView, let self = self {
                    let sections = self.dataSource.snapshot().sectionIdentifiers
                    if index.section < sections.count {
                        let section = sections[index.section ]
                        messageTimeHeaderView.configure(headerText: section)
                        return messageTimeHeaderView
                    } else {
                        DDLogInfo("ChatViewControllerNew/configureHeader/time header info not available")
                        return headerView
                    }
                    
                } else {
                    DDLogInfo("ChatViewControllerNew/configureHeader/time header info not available")
                    return headerView
                }
            } else if kind == MessageChatHeaderView.elementKind {
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
        default:
            break
        }
        updateCollectionViewData()
    }

    func updateCollectionViewData() {
        var messageRows: [MessageRow] = []
        var snapshot = ChatMessageSnapshot()

        // Add messages
        if let chatMessages = chatMessageFetchedResultsController?.fetchedObjects {
            chatMessages.forEach { chatMessage in
                messageRows.append(messagerow(for: chatMessage))
            }
        }
        // Add call events
        if let chatCalls = callHistoryFetchedResultsController?.fetchedObjects {
            chatCalls.forEach { chatCall in
                let chatCallData = ChatCallData(userID: chatCall.peerUserID, timestamp: chatCall.timestamp, duration: chatCall.durationMs / 1000, wasSuccessful: chatCall.answered, wasIncoming: chatCall.direction == .incoming, type: chatCall.type)
                messageRows.append(MessageRow.chatCall(chatCallData))
            }
        }
        // Add events eg user security key changed
        if let chatEvents = chatEventFetchedResultsController?.fetchedObjects {
            chatEvents.forEach { chatEvent in
                messageRows.append(MessageRow.chatEvent(chatEvent))
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
        for messageRow in messageRows {
            if !snapshot.sectionIdentifiers.contains(messageRow.headerTime) {
                snapshot.appendSections([messageRow.headerTime])
            }
            snapshot.appendItems([messageRow], toSection: messageRow.headerTime)
        }

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
                    // only count chatMessages and chatEvents for now since only chatMessages and chatEvents
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
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            guard let self = self else { return }
            self.updateScrollingWhenDataChanges()
        }
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

    private func messagerow(for chatMessage: ChatMessage) -> MessageRow {
        if [.retracted, .retracting].contains(chatMessage.outgoingStatus) || [.retracted, .rerequesting, .unsupported].contains(chatMessage.incomingStatus) {
            return MessageRow.chatMessage(chatMessage)
       }
        // Quoted Message
        if chatMessage.chatReplyMessageID != nil || chatMessage.feedPostId != nil {
            return MessageRow.quoted(chatMessage)
        }
        // Media
        if chatMessage.media?.first?.type == .audio {
            return MessageRow.audio(chatMessage)
        } else if chatMessage.media?.first?.type == .video || chatMessage.media?.first?.type == .image {
            return MessageRow.media(chatMessage)
        }
        // Link Preview
        if let feedLinkPreviews = chatMessage.linkPreviews, feedLinkPreviews.first != nil {
            return MessageRow.linkPreview(chatMessage)
        }
        return MessageRow.text(chatMessage)
    }

    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        DDLogDebug("ChatViewControllerNew/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId, in: contactsViewContext))]")
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

        let titleWidthConstraint = titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.8))
        titleWidthConstraint.priority = .defaultHigh // Lower priority to allow space for trailing button if necessary
        titleWidthConstraint.isActive = true
        // Setup title view
        navigationItem.titleView = titleView
        titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
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
                                                     mediaLink: mediaUrl)
                    let panel = QuotedItemPanel()
                    panel.postInfo = info
                    contentInputView.display(context: panel)
                } else {
                    let info = QuotedItemPanel.PostInfo(userID: feedPost.userId,
                                                          text: mentionText?.string ?? "",
                                                     mediaType: nil,
                                                     mediaLink: nil)
                    let panel = QuotedItemPanel()
                    panel.postInfo = info
                    contentInputView.display(context: panel)
                }
            }
        }

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] status, ts in
                DDLogInfo("ChatViewControllerNew/didGetCurrentChatPresence")
                guard let self = self else { return }
                guard let userId = self.fromUserId else { return }
                DispatchQueue.main.async {
                    self.titleView.update(with: userId, status: status, lastSeen: ts)
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] chatStateInfo in
                guard let self = self else { return }
                DDLogInfo("ChatViewControllerNew/didGetChatStateInfo \(chatStateInfo)")
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
        view.addGestureRecognizer(tapGesture)

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
    }

    override func viewWillAppear(_ animated: Bool) {
       super.viewWillAppear(animated)

       removeTransitionSnapshot()
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
           DDLogDebug("ChatViewControllerNew/updateScrollingWhenDataChanges/scrollToLastMessage/ on send message")
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
        itemCell.configureWith(message: chatMessage)
        itemCell.textLabel.delegate = self
        itemCell.chatDelegate = self
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])


        let sectionHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionHeaderSize, elementKind: MessageTimeHeaderView.elementKind, alignment: .top)
        sectionHeader.pinToVisibleBounds = true
        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [sectionHeader]

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
        let typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .oneToOne, id: userID)

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
        return contentInputView
    }

    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }

    func sendMessage(text: String, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?) {
        guard let sendToUserId = self.fromUserId else { return }

        MainAppContext.shared.chatData.sendMessage(toUserId: sendToUserId,
                                                       text: text,
                                                      media: media,
                                            linkPreviewData: linkPreviewData,
                                           linkPreviewMedia: linkPreviewMedia,
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

        contentInputView.resetAfterPosting()
        removeChatDraft()
        if !firstActionHappened {
            didAction()
        }
    }

    private func presentMediaPicker() {
        let vc = MediaPickerViewController(config: .chat(id: fromUserId)) { [weak self] controller, _, _, media, cancel in
            guard let self = self else { return }
            if cancel {
                self.dismiss(animated: true)
            } else {
                self.presentMediaComposer(media: media)
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

    private func presentMediaComposer(media: [PendingMedia]) {
        let composerController = PostComposerViewController(
            mediaToPost: media,
            initialInput: MentionInput(text: contentInputView.textView.text, mentions: MentionRangeMap(), selectedRange: NSRange()),
            configuration: .message(id: fromUserId),
            initialPostType: .library,
            voiceNote: nil,
            delegate: self)

        let presenter = presentedViewController ?? self
        presenter.present(UINavigationController(rootViewController: composerController), animated: false)
    }
    
    @MainActor
    private func saveAllMedia(in chatMessage: ChatMessage) async {
        do {
            let isAuthorizedToSave: Bool = await {
                if #available(iOS 14, *) {
                    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    return status == .authorized || status == .limited
                } else {
                    let status = await withCheckedContinuation { continuation in
                        PHPhotoLibrary.requestAuthorization { continuation.resume(returning: $0) }
                    }
                    return status == .authorized
                }
            }()
            
            guard isAuthorizedToSave else {
                DDLogInfo("ChatViewControllerNew/saveAllMediaInMessage: User denied photos permissions")
                
                let alert = UIAlertController(title: Localizations.mediaPermissionsError, message: Localizations.mediaPermissionsErrorDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                present(alert, animated: true)
                return
            }
            
            var mediaInfo: [(type: CommonMediaType, url: URL)]? = nil
            MainAppContext.shared.chatData.viewContext.performAndWait {
                mediaInfo = chatMessage.media?
                    .compactMap { (media: CommonMedia) -> (type: CommonMediaType, url: URL)? in
                        if let url = media.mediaURL ?? media.relativeFilePath.map({ MainAppContext.chatMediaDirectoryURL.appendingPathComponent($0, isDirectory: false) }) {
                            return (media.type, url)
                        } else {
                            return nil
                        }
                    }
                    .filter { (type: CommonMediaType, _: URL) -> Bool in
                        type == .image || type == .video
                    }
            }
            
            try await PHPhotoLibrary.shared().performChanges {
                mediaInfo?
                    .forEach { (type: CommonMediaType, url: URL) in
                        if type == .image {
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                            AppContext.shared.eventMonitor.count(.mediaSaved(type: .image, source: .chat))
                        } else {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            AppContext.shared.eventMonitor.count(.mediaSaved(type: .video, source: .chat))
                        }
                    }
            }
            
            let alert = UIAlertController(title: nil, message: Localizations.saveSuccessfulLabel, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
            present(alert, animated: true)
        } catch {
            DDLogError("ChatViewControllerNew/saveAllMediaInMessage/error: \(error)")
            
            Task { @MainActor in
                let alert = UIAlertController(title: nil, message: Localizations.mediaSaveError, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                present(alert, animated: true)
            }
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
}

// MARK: ChatTitle Delegates
extension ChatViewControllerNew: ChatTitleViewDelegate {
    func chatTitleView(_ chatTitleView: ChatTitleView) {
        guard let userId = fromUserId else { return }
        let userViewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(userViewController, animated: true)
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
    
    private func pauseVoiceNotes() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? MessageCellViewAudio {
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

            if let replyMedia = replyMessage.media, !replyMedia.isEmpty {
                let replyIndex = replyMedia.index(replyMedia.startIndex, offsetBy: Int(chatReplyMessageMediaIndex))
                let mediaObject = replyMedia[replyIndex]
                if let mediaURL = mediaObject.url?.absoluteString {
                    let media = ChatReplyMedia(type: mediaObject.type, mediaURL: mediaURL)

                    let reply = ReplyContext(replyMessageID: replyMessageID,
                          replySenderID: replySenderID,
                          mediaIndex: chatReplyMessageMediaIndex,
                          text: replyMessage.rawText ?? "",
                          media: media)

                    return reply
                }
            }

            let reply = ReplyContext(replyMessageID: replyMessageID,
                  replySenderID: replySenderID,
                  mediaIndex: chatReplyMessageMediaIndex,
                  text: replyMessage.rawText ?? "",
                  media: nil)

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
        let cameraImage = UIImage(systemName: "camera.fill")?.withRenderingMode(.alwaysOriginal)
                                                             .withTintColor(.primaryBlue)
        let pickerImage = UIImage(systemName: "photo.fill.on.rectangle.fill")?.withRenderingMode(.alwaysOriginal)
                                                                              .withTintColor(.primaryBlue)
        
        HAMenuButton(title: Localizations.fabAccessibilityCamera, image: cameraImage) { [weak self] in
            self?.presentCameraViewController()
        }
        
        HAMenuButton(title: Localizations.photoAndVideoLibrary, image: pickerImage) { [weak self] in
            self?.presentMediaPicker()
        }
    }
    
    private func presentCameraViewController() {
        let vc = CameraViewController(configuration: .init(showCancelButton: true, format: .normal),
                                          didFinish: { [weak self] in self?.dismiss(animated: true)},
                                       didPickImage: { [weak self] image in self?.didTake(photo: image)},
                                       didPickVideo: { [weak self] videoURL in self?.didTake(video: videoURL)})

        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func didTake(photo: UIImage) {
        let media = PendingMedia(type: .image)
        media.image = photo

        presentComposerViewController(media: [media])
    }

    private func didTake(video url: URL) {
        let media = PendingMedia(type: .video)
        media.originalVideoURL = url
        media.fileURL = url

        presentComposerViewController(media: [media])
    }

    private func presentComposerViewController(media: [PendingMedia]) {
        let composerController = PostComposerViewController(
            mediaToPost: media,
           initialInput: MentionInput(text: contentInputView.textView.text, mentions: MentionRangeMap(), selectedRange: NSRange()),
          configuration: .message(id: fromUserId),
        initialPostType: .library,
              voiceNote: nil,
               delegate: self)

        let presenter = presentedViewController ?? self
        presenter.present(UINavigationController(rootViewController: composerController), animated: false)
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

// MARK: PostComposerView Delegates
extension ChatViewControllerNew: PostComposerViewDelegate {
    func composerDidTapLinkPreview(controller: PostComposerViewController, url: URL) {
        URLRouter.shared.handleOrOpen(url: url)
    }

    func composerDidTapShare(controller: PostComposerViewController,
                            destination: PostComposerDestination,
                             feedAudience: FeedAudience,
                               isMoment: Bool,
                            mentionText: MentionText,
                                  media: [PendingMedia],
                        linkPreviewData: LinkPreviewData? = nil,
                       linkPreviewMedia: PendingMedia? = nil) {

        sendMessage(text: mentionText.trimmed().collapsedText, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
        view.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }

    func composerDidTapBack(controller: PostComposerViewController, destination: PostComposerDestination, privacyListType: PrivacyListType, media: [PendingMedia], voiceNote: PendingMedia?) {
        controller.dismiss(animated: false)

        let presentedVC = self.presentedViewController

        if let viewControllers = (presentedVC as? UINavigationController)?.viewControllers {
            if let mediaPickerController = viewControllers.last as? MediaPickerViewController {
                mediaPickerController.reset(destination: nil, privacyListType: nil, selected: media)
            }
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {

    }
}

extension ChatViewControllerNew: MessageViewChatDelegate {

    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID) {

    }

    func messageView(_ messageViewCell: MessageCellViewBase, for chatMessageID: ChatMessageID, didTapMediaAtIndex index: Int) {
        let viewContext = MainAppContext.shared.chatData.viewContext
        guard let message = MainAppContext.shared.chatData.chatMessage(with: chatMessageID, in: viewContext) else { return }

        if message.orderedMedia.count == 1 {
            let controller = MediaExplorerController(media: message.orderedMedia, index: index)
            controller.animatorDelegate = self

            present(controller, animated: true)
        } else if message.orderedMedia.count > 1 {
            guard let userID = fromUserId else { return }

            let controller = ChatMediaListViewController(userID: userID, message: message, index: index)
            controller.animatorDelegate = self

            present(controller.withNavigationController(), animated: true)
        }
    }

    func messageView(_ messageViewCell: MessageCellViewBase, didLongPressOn chatMessage: ChatMessage) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if chatMessage.incomingStatus != .retracted {
            if let media = chatMessage.media, !media.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.saveAllButton, style: .default) { _ in
                    Task { [weak self] in
                        await self?.saveAllMedia(in: chatMessage)
                    }
                })
            }
            
            actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.handleQuotedReply(msg: chatMessage)
             })

            if let messageText = chatMessage.rawText, !messageText.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = messageText
                })
            }

            actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
                self?.showDeletionConfirmationMenu(for: chatMessage)
            })

            if ServerProperties.isInternalUser {
                actionSheet.message = MainAppContext.shared.cryptoData.details(
                                        for: chatMessage.id,
                                        dateFormatter: DateFormatter.dateTimeFormatterMonthDayTime,
                                        in: MainAppContext.shared.cryptoData.viewContext)
            }
        }
        guard actionSheet.actions.count > 0 else { return }

       actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))

       self.present(actionSheet, animated: true)
   }

   func messageView(_ messageViewCell: MessageCellViewBase, jumpTo chatMessageID: ChatMessageID) {
       scrollToMessage(id: chatMessageID, animated: true, highlightAfterScroll: true)
   }

   func messageView(_ messageViewCell: MessageCellViewBase, openPost feedPostId: String) {
       guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) else {
           DDLogWarn("ChatViewControllerNew/Quoted feed post \(feedPostId) not found")
           return
       }

       let vc = feedPost.isMoment ? MomentViewController(post: feedPost) : PostViewController.viewController(for: feedPost)
       present(vc, animated: true)
   }

   func messageView(_ messageViewCell: MessageCellViewBase, replyToChat chatMessage: ChatMessage) {
       guard chatMessage.incomingStatus != .retracted else { return }
       guard ![.retracting, .retracted].contains(chatMessage.outgoingStatus) else { return }
       handleQuotedReply(msg: chatMessage)
   }

   private func handleQuotedReply(msg chatMessage: ChatMessage) {
       chatReplyMessageID = chatMessage.id
       chatReplyMessageSenderID = chatMessage.fromUserId

       guard let userID = chatReplyMessageSenderID else { return }

       if let mediaItem = chatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
          let mediaUrl = mediaItem.mediaURL ?? MainAppContext.chatMediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
           let info = QuotedItemPanel.PostInfo(userID: userID,
                                                 text: chatMessage.rawText ?? "",
                                            mediaType: mediaItem.type,
                                            mediaLink: mediaUrl)
           let panel = QuotedItemPanel()
           panel.postInfo = info
           contentInputView.display(context: panel)
       } else {
           let info = QuotedItemPanel.PostInfo(userID: userID,
                                                 text: chatMessage.rawText ?? "",
                                            mediaType: nil,
                                            mediaLink: nil)
           let panel = QuotedItemPanel()
           panel.postInfo = info
           contentInputView.display(context: panel)
       }
       contentInputView.textView.becomeFirstResponder()
   }

   private func handleDraftQuotedReply(reply: ReplyContext) {
        if let mediaURLString = reply.media?.mediaURL, let mediaURL = URL(string: mediaURLString) {
            let info = QuotedItemPanel.PostInfo(userID: reply.replySenderID,
                                                  text: reply.text,
                                             mediaType: reply.media?.type,
                                             mediaLink: mediaURL)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        } else {
            let info = QuotedItemPanel.PostInfo(userID: reply.replySenderID,
                                                  text: reply.text,
                                             mediaType: nil,
                                             mediaLink: nil)
            let panel = QuotedItemPanel()
            panel.postInfo = info
            contentInputView.display(context: panel)
        }
   }

   func showDeletionConfirmationMenu(for chatMessage: ChatMessage) {
       let chatMessageId = chatMessage.id
       let alertController = UIAlertController(title: Localizations.chatDeleteTitle, message: nil, preferredStyle: .actionSheet)

       if chatMessage.fromUserId == AppContext.shared.userData.userId,
          [.sentOut, .delivered, .seen, .played].contains(chatMessage.outgoingStatus),
          let toUserID = fromUserId {
           alertController.addAction(UIAlertAction(title: Localizations.chatDeleteForEveryone, style: .destructive) { _ in
               MainAppContext.shared.chatData.retractChatMessage(toUserID: toUserID, messageToRetractID: chatMessageId)
           })
       }

       alertController.addAction(UIAlertAction(title: Localizations.chatDeleteForMe, style: .destructive) { _ in
           MainAppContext.shared.chatData.deleteChatMessage(with: chatMessageId)
       })

       alertController.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
       present(alertController, animated: true)
   }

    // MARK : Scrolling
    private func scrollToMessage(id: ChatMessageID, animated: Bool = false, highlightAfterScroll: Bool = false) {
        guard let indexPath = indexPath(for: id) else {
            DDLogDebug("ChatViewControllerNew/scrollToMessage failed for ChatMessageID: \(id)")
            return
        }
        DDLogDebug("ChatViewControllerNew/scrollToMessage ChatMessageID:\(id) animated:\(animated)")
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        if !animated {
            // Attempt to get a more exact position than provided from estimated sizes.
            // Not compatible with animation, but useful for finding initial scroll positions
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }

        if highlightAfterScroll {
            highlightMessage(id: id)
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
        return dataSource.indexPath(for: messagerow(for: chatMessage))
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
        guard let lastMessageIndexPath = lastMessageIndexPath() else {
            return
        }
        if let lastCommentLayoutAttributes = collectionView.layoutAttributesForItem(at: lastMessageIndexPath) {
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
        DDLogDebug("ChatViewControllerNew/scrollToLastMessage")
        self.collectionView.scrollToItem(at: lastMessageIndexPath, at: .centeredVertically, animated: animated)
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
        guard let indexPath = dataSource.indexPath(for: MessageRow.unreadCountHeader(Int32(unreadCount))) else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        updateJumpButtonText()
    }
}

// MARK: MediaListAnimatorDelegate
extension ChatViewControllerNew: MediaListAnimatorDelegate {
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
            configureMedia(mediaType, mediaLink)
        }
    }

    private func configureMedia(_ mediaType: CommonMediaType, _ url: URL) {
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

extension ChatViewControllerNew: MessageChatEventViewDelegate, UserMenuHandler {
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
