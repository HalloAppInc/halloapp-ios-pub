//
//  GroupChatViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 9/23/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import CoreData
import CocoaLumberjackSwift
import Photos
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
        case .groupChatEvent(let data):
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

class GroupChatViewController: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, UIViewControllerMediaSaving {

    // Wait for ios to create a cell if it does not exist
    let waitForCellDelay: TimeInterval = 0.25

    private let groupId: GroupID
    private var group: Group?
    private var chatReplyMessageID: String?
    private var chatReplyMessageSenderID: String?
    private var chatReplyMessageMediaIndex: Int32 = 0
    weak var chatViewControllerDelegate: ChatViewControllerDelegate?
    private var firstActionHappened = false

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

    private lazy var groupDestination: ShareDestination? = {
        guard let group = group else {
            return nil
        }
        return ShareDestination.destination(from: group)
    }()

    private var cancellableSet: Set<AnyCancellable> = []
    fileprivate var documentInteractionController: UIDocumentInteractionController?

    fileprivate typealias ChatDataSource = UICollectionViewDiffableDataSource<Section, MessageRow>
    fileprivate typealias ChatMessageSnapshot = NSDiffableDataSourceSnapshot<Section, MessageRow>

    private lazy var titleView: ChatTitleView = {
        let titleView = ChatTitleView()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        titleView.delegate = self
        return titleView
    }()

    private var chatParticipants: [String: Int] = [:]
    // List of colors to cycle through while setting user names
    private var colors: [UIColor] = [
        UIColor.userColor1,
        UIColor.userColor2,
        UIColor.userColor3,
        UIColor.userColor4,
        UIColor.userColor5,
        UIColor.userColor6,
        UIColor.userColor7,
        UIColor.userColor8,
        UIColor.userColor9,
        UIColor.userColor10,
        UIColor.userColor11,
        UIColor.userColor12
    ]

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
        collectionView.register(MessageCellViewDocument.self, forCellWithReuseIdentifier: GroupChatViewController.messageCellViewDocumentReuseIdentifier)
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
                case .groupChatEvent(let groupEvent):
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
        let userColorAssignment = getUserColorAssignment(userId: chatMessage.fromUserId)
        var parentUserColorAssignment = UIColor.secondaryLabel
        if let parentMessageUserId = chatMessage.chatReplyMessageSenderID {
            parentUserColorAssignment = getUserColorAssignment(userId: parentMessageUserId)
        }
        // TODO isPreviousMessageFromSameSender calculation
        let isPreviousMessageFromSameSender = false
        itemCell.configureWith(message: chatMessage, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        itemCell.textLabel.delegate = self
        itemCell.chatDelegate = self
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
        super.init(nibName: nil, bundle: nil)
        guard let group else {
            DDLogError("GroupChatViewController/init/ group does not exisit goupId: \(groupId)")
            return
        }
        DDLogDebug("GroupChatViewController/init/\(group.id) [\(group.name))]")
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
        titleView.clearGroupTitleViewTyping(groupId: groupId)
        
        titleView.delegate = self
        loadChatDraft(id: groupId)
        scrollToLastMessage(animated: false)

        if let group = group {
            cancellableSet.insert(
                group.publisher(for: \.name).sink {
                    [weak self] _ in
                    self?.titleView.refreshName(groupId: group.id)
                }
            )
        }

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] fromUserId, status, ts in
                guard let self = self else { return }
                guard MainAppContext.shared.chatData.chatGroupMember(groupId: self.groupId, memberUserId: fromUserId, in: MainAppContext.shared.chatData.viewContext) != nil else { return }
                DDLogInfo("GroupChatViewController/received chat presence for user \(fromUserId)")
                DispatchQueue.main.async {
                    self.titleView.updateGroupTitleView(groupId: self.groupId, fromUserId: fromUserId, status: status)
                }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] chatStateInfo in
                guard let self = self else { return }
                guard let chatStateInfo = chatStateInfo else {
                    // if no chat state info received, clear typing indicator
                    self.titleView.clearGroupTitleViewTyping(groupId: self.groupId)
                    return
                }
                guard chatStateInfo.threadID == self.groupId else { return }
                DDLogInfo("GroupChatViewController/didGetChatStateInfo \(String(describing: chatStateInfo))")
                DispatchQueue.main.async {
                    self.titleView.configureGroupTitleViewWithTypingIndicator(chatStateInfo: chatStateInfo)
                }
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupChatViewController/viewWillAppear")
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = UIColor.groupFeedTopNav
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveChatDraft(id: groupId)
        pauseVoiceNotes()

        MainAppContext.shared.chatData.markThreadAsRead(type: .groupChat, for: groupId)
        MainAppContext.shared.chatData.updateUnreadChatsThreadCount()
        MainAppContext.shared.chatData.setCurrentlyChattingInGroup(in: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        MainAppContext.shared.chatData.markSeenMessages(type: .groupChat, for: groupId)
        MainAppContext.shared.chatData.setCurrentlyChattingInGroup(in: groupId)
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

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            DDLogInfo("GroupChatViewController/didChange type insert")
            updateCollectionViewData()
        case .delete:
            updateCollectionViewData()
        case .update:
            DDLogInfo("GroupChatViewController/didChange type update")
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
                            DispatchQueue.main.async {
                                self.dataSource?.apply(snapshot, animatingDifferences: false)
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

    // We should not update audio cells while it is playing.
    // This is a bad hack: Ideally we should remove the audio player from the message cell.
    private func shouldUpdateAudioCell(chatMessage: ChatMessage) -> Bool {
        if chatMessage.media?.count == 1, chatMessage.media?.first?.type == .audio, (chatMessage.incomingStatus == .played || chatMessage.incomingStatus == .sentPlayedReceipt) {
            return false
        }
        return true
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
                messageRows.append(MessageRow.groupChatEvent(chatEvent))
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

    // MARK: Input view
    lazy var contentInputView: ContentInputView = {
        let inputView = ContentInputView(options: .chat)
        inputView.autoresizingMask = [.flexibleHeight]
        inputView.delegate = self
        if let url = AudioRecorder.voiceNote(from: MainAppContext.shared.userData.userId, to: groupId) {
            inputView.show(voiceNote: url)
        }
        return inputView
    }()

    public func showKeyboard() {
        contentInputView.textView.becomeFirstResponder()
    }

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

        MainAppContext.shared.chatData.sendMessage(chatMessageRecipient: .groupChat(toGroupId: groupId, fromUserId: MainAppContext.shared.userData.userId),
                                                       text: text,
                                                      media: media,
                                                      files: files,
                                            linkPreviewData: linkPreviewData,
                                           linkPreviewMedia: linkPreviewMedia,
                                                   location: location,
                                                   feedPostId: nil,
                                           feedPostMediaIndex: 0,
                                         chatReplyMessageID: chatReplyMessageID,
                                   chatReplyMessageSenderID: chatReplyMessageSenderID,
                                 chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)

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
        guard let groupDestination = groupDestination else { return }

        let vc = MediaPickerViewController(config: .config(with: groupDestination)) { [weak self] controller, _, media, cancel in
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
        }

        return nil
    }

    /// Restores the text from `UserDefaults` into the `ContentInputView` so the user can continue what they last wrote.
    /// - Parameter id: The UserID of the other user in the chat.
    private func loadChatDraft(id: UserID) {
        guard let draftsArray: [ChatDraft] = try? AppContext.shared.userDefaults.codable(forKey: "chats.drafts") else { return }
        guard let draft = draftsArray.first(where: { existingDraft in
            existingDraft.chatID == groupId
        }) else { return }

        let mentionText = MentionText(collapsedText: draft.text, mentions: [:])
        contentInputView.set(draft: mentionText)

        if let reply = draft.replyContext {
            handleDraftQuotedReply(reply: reply)
            if let chatReplyMessageID = chatReplyMessageID {
                self.chatReplyMessageID = chatReplyMessageID
                chatReplyMessageSenderID = reply.replySenderID
                chatReplyMessageMediaIndex = reply.mediaIndex ?? 0
            } else {
                DDLogWarn("GroupChatViewController/No chatReplyMessageId when restoring draft reply")
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
            existingDraft.chatID == groupId
        }

        try? AppContext.shared.userDefaults.setCodable(draftsArray, forKey: "chats.drafts")
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

    private func indexPath(for id: ChatMessageID) -> IndexPath? {
        guard let chatMessage = chatMessageFetchedResultsController?.fetchedObjects?.first(where: { $0.id == id }) else {
            return nil
        }
        return dataSource?.indexPath(for: MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, groupId: groupId, timestamp: chatMessage.timestamp)))
    }

    private func getUserColorAssignment(userId: UserID) -> UIColor {
        guard let userColorIndex = chatParticipants[userId] else {
            let chatParticipantsCount = chatParticipants.count
            chatParticipants[userId] = chatParticipantsCount
            return colors[(chatParticipantsCount) % colors.count]
        }
        return colors[userColorIndex % colors.count]
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

// MARK: - content input view delegate methods
extension GroupChatViewController: ContentInputDelegate {
    func inputView(_ inputView: ContentInputView, possibleMentionsFor input: String) -> [MentionableUser] {
        return []
    }

    func inputView(_ inputView: ContentInputView, isTyping: Bool) {
        let state: ChatState = isTyping ? .typing : .available

        MainAppContext.shared.chatData.sendChatState(type: .groupChat,
                                                       id: groupId,
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
    }

    func inputView(_ inputView: ContentInputView, didClose panel: InputContextPanel) {
        if panel.isKind(of: QuotedItemPanel.self) {

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
        if #available(iOS 15.0, *), let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }

        present(navigationController, animated: true)
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
        guard let groupDestination = groupDestination else { return }

        let input = MentionInput(text: contentInputView.textView.text, mentions: MentionRangeMap(), selectedRange: NSRange())
        let composerController = ComposerViewController(config: .config(with: groupDestination), type: .library, input: input, media: media, voiceNote: nil) { [weak self] controller, result, success in
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
        let vc: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            vc = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        } else {
            vc = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .open)
        }
        vc.delegate = self
        present(vc, animated: true)

        if !firstActionHappened {
            didAction()
        }
    }

    func inputView(_ inputView: ContentInputView, didInterrupt recorder: AudioRecorder) {
        guard
            let url = recorder.saveVoiceNote(from: MainAppContext.shared.userData.userId, to: groupId)
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

extension GroupChatViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        DDLogInfo("GroupChatViewController/documentPickerWasCancelled")
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        DDLogInfo("GroupChatViewController/didPickDocuments")
        // TODO: handle multiple files
        guard let documentURL = urls.first else { return }
        let threadID = groupId
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

extension GroupChatViewController: MessageViewChatDelegate, ReactionViewControllerChatDelegate, ReactionListViewControllerDelegate {

    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID) {
        // TODO @Nandini implement this for group chat
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

            let controller = ChatMediaListViewController(name: group?.name ?? "", message: message, index: index)
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
        let reactionView = ReactionViewController(messageViewCell: snapshotView, chatMessage: chatMessage)
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
            if #available(iOS 15.0, *), let sheet = navigationController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
            }
            self.present(navigationController, animated: true)
        }
    }

    func messageView(_ messageViewCell: MessageCellViewBase, forwardingMessage chatMessage: ChatMessage) {
        handleForwarding(msg: chatMessage)
    }
    
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo chatMessageID: ChatMessageID) {
        // TODO scrollToMessage(id: chatMessageID, animated: true, highlightAfterScroll: true)
    }

    func messageView(_ messageViewCell: MessageCellViewBase, openPost feedPostId: String) {
        // no op
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
        guard var nextIndexPath = dataSource?.indexPath(for: MessageRow.chatMessage(ChatMessageData(id: chatMessage.id, fromUserId: chatMessage.fromUserId, groupId: groupId, timestamp: chatMessage.timestamp))) else { return }
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
            for selectedDestination in destinations {
                switch selectedDestination {
                case .contact(id: let id, name: _, phone: _):
                    toUserIds.append(id)
                default:
                    break
                }
            }
            MainAppContext.shared.chatData.forwardChatMessages(toUserIds: toUserIds, chatMessage: chatMessage)
            if toUserIds.count == 1, let toUserId = toUserIds.first {
                let chatVC = ChatViewControllerNew(for: toUserId)
                self.navigationController?.pushViewController(chatVC, animated: true)
            }
        }
        present(UINavigationController(rootViewController: vc), animated: true)
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
        MainAppContext.shared.chatData.sendReaction(chatMessageRecipient: chatMessage.chatMessageRecipient,
                                                    reaction: reaction,
                                                    chatMessageID: chatMessage.id)
    }

    func removeReaction(reaction: CommonReaction) {
        // Users can only remove reactions they have authored
        if reaction.fromUserID == AppContext.shared.userData.userId {
            MainAppContext.shared.chatData.retractReaction(commonReaction: reaction, reactionToRetractID: reaction.id)
        }
    }

    private func lastMessageIndexPath() -> IndexPath? {
        let lastSectionIndex = collectionView.numberOfSections - 1
        guard lastSectionIndex >= 0 else { return nil }
        let lastRowIndex = collectionView.numberOfItems(inSection: lastSectionIndex) - 1
        guard lastRowIndex >= 0 else {  return nil }
        return IndexPath(row: lastRowIndex, section: lastSectionIndex)
    }

    @objc private func scrollToLastMessage(animated: Bool) {
        guard let lastMessageIndexPath = lastMessageIndexPath() else {
            return
        }
        scrollToItemAtIndexPath(indexPath: lastMessageIndexPath, animated: animated)
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
}

// MARK: MediaListAnimatorDelegate
extension GroupChatViewController: MediaListAnimatorDelegate {
    var transitionViewRadius: CGFloat {
        10
    }

    func scrollToTransitionView(at index: MediaIndex) {
        guard let chatMessageID = index.chatMessageID else { return }
        // TODO scrollToMessage(id: chatMessageID)
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

extension GroupChatViewController: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        documentInteractionController = nil
    }
}

// MARK: ChatTitle Delegates
extension GroupChatViewController: ChatTitleViewDelegate {
    func chatTitleView(_ chatTitleView: ChatTitleView) {
        let vc = GroupInfoViewController(for: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }
}
