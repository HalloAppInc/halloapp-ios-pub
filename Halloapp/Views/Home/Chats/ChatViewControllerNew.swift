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
import UIKit
import CoreData

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
    case chatCall(Core.Call)
    case chatEvent(ChatEvent)

    var timestamp: Date? {
        switch self {
        case .chatEvent(let data):
            return data.timestamp
        case .chatMessage(let data), .retracted(let data), .media(let data), .audio(let data), .text(let data), .linkPreview(let data), .quoted(let data):
            return data.timestamp
        case .chatCall(let data):
            return data.timestamp
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
            return data.timestamp.chatMsgGroupingTimestamp(Date())
        case .unreadCountHeader(_):
            return ""
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
    private var firstActionHappened: Bool = false

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

                    if chatEvent.type == .whisperKeysChange, let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatViewControllerNew.messageCellViewEventReuseIdentifier, for: indexPath) as? MessageCellViewEvent {
                        let fullname = MainAppContext.shared.contactStore.fullName(for: chatEvent.userID)
                        cell.configure(headerText: Localizations.chatEventSecurityKeysChanged(name: fullname))
                        return cell
                    }
                case .chatCall(let chatCall):
                    if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatViewControllerNew.messageCellViewCallReuseIdentifier, for: indexPath) as? MessageCellViewCall {
                        cell.configure(headerText: "Placeholder Call Text")
                        return cell
                    }
                case .unreadCountHeader(_):
                    return UICollectionViewCell()
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
            }
            return nil
        }
        return dataSource
    }()

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateCollectionViewData()
    }

    func updateCollectionViewData() {
        var messageRows: [MessageRow] = []
        var snapshot = ChatMessageSnapshot()

        if let chatMessages = chatMessageFetchedResultsController?.fetchedObjects {
            chatMessages.forEach { chatMessage in
                messageRows.append(messagerow(for: chatMessage))
            }
        }
        if let chatEvents = chatEventFetchedResultsController?.fetchedObjects {
            chatEvents.forEach { chatEvent in
                messageRows.append(MessageRow.chatEvent(chatEvent))
            }
        }
        if let chatCalls = callHistoryFetchedResultsController?.fetchedObjects {
            chatCalls.forEach { chatCall in
                messageRows.append(MessageRow.chatCall(chatCall))
            }
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
        // Apply the new snapshot
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func messagerow(for chatMessage: ChatMessage) -> MessageRow {
        if [.retracted, .retracting].contains(chatMessage.outgoingStatus) || [.retracted, .rerequesting, .unsupported].contains(chatMessage.incomingStatus) {
            return MessageRow.chatMessage(chatMessage)
       }
        // Quoted Message
        if chatMessage.chatReplyMessageID != nil {
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
        DDLogDebug("ChatViewControllerNew/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId))]")
        self.fromUserId = fromUserId
        self.feedPostId = feedPostId
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let fromUserId = fromUserId else { return }

        // Setup audio and video call buttons
        var rightBarButtons: [UIBarButtonItem] = []
        if ServerProperties.isAudioCallsEnabled {
            let image = UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(.primaryBlue).withTintColor(.primaryBlue)
            let phoneButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(audioCallButtonTapped))
            phoneButton.tintColor = .primaryBlue
            rightBarButtons.append(phoneButton)
        }
        if ServerProperties.isVideoCallsEnabled {
            let image = UIImage(systemName: "video.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(.primaryBlue)
            let videoButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(videoCallButtonTapped))
            videoButton.tintColor = .primaryBlue
            rightBarButtons.append(videoButton)
        }
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
        loadChatDraft(id: fromUserId)
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

       applyTransitionSnapshot()
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

        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration = layoutConfig
        return layout
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    @objc private func audioCallButtonTapped() {
        callButtonTapped(type: .audio)
    }

    @objc private func videoCallButtonTapped() {
        callButtonTapped(type: .video)
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

        removeChatDraft()

        if !firstActionHappened {
            didAction()
        }
    }

    private func presentMediaPicker() {
        let vc = MediaPickerViewController(config: .chat(id: fromUserId)) { [weak self] controller, _, media, cancel in
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
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.rawText, mentions: feedPost.orderedMentions)
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

        contentInputView.set(draft: draft.text)

        if let reply = draft.replyContext {
            // TODO
            //handleDraftQuotedReply(reply: reply)
            if let feedPostId = reply.feedPostID {
                self.feedPostId = feedPostId
                feedPostMediaIndex = reply.mediaIndex ?? 0
            } else if let chatReplyMessageID = chatReplyMessageID {
                self.chatReplyMessageID = chatReplyMessageID
                chatReplyMessageSenderID = reply.replySenderID
                chatReplyMessageMediaIndex = reply.mediaIndex ?? 0
            } else {
                DDLogWarn("ChatViewController/No feedPostId or chatReplyMessageId when restoring draft reply")
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

        // TODO updateJumpButtonVisibility()
    }

    func inputView(_ inputView: ContentInputView, didClose panel: InputContextPanel) {
        // TODO
//        if panel.isKind(of: QuotedItemPanel.self) {
//            feedPostId = nil
//            feedPostMediaIndex = 0
//
//            chatReplyMessageID = nil
//            chatReplyMessageSenderID = nil
//            chatReplyMessageMediaIndex = 0
//        }
    }

    func inputViewDidSelectCamera(_ inputView: ContentInputView) {
        presentCameraViewController()
    }

    func inputViewDidSelectContentOptions(_ inputView: ContentInputView) {
        let action = ActionSheetViewController(title: "", message: "")
        let cameraImage = UIImage(systemName: "camera.fill")?.withRenderingMode(.alwaysOriginal)
                                                             .withTintColor(.primaryBlue)
        let pickerImage = UIImage(systemName: "photo.fill.on.rectangle.fill")?.withRenderingMode(.alwaysOriginal)
                                                                              .withTintColor(.primaryBlue)

        action.addAction(ActionSheetAction(title: Localizations.fabAccessibilityCamera, image: cameraImage, style: .default) { _ in
            self.presentCameraViewController()
        })

        action.addAction(ActionSheetAction(title: Localizations.photoAndVideoLibrary, image: pickerImage, style: .default) { _ in
            self.presentMediaPicker()
        })

        action.addAction(ActionSheetAction(title: Localizations.buttonCancel, style: .cancel))

        navigationController?.present(action, animated: true)
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
                               isMoment: Bool,
                            mentionText: MentionText,
                                  media: [PendingMedia],
                        linkPreviewData: LinkPreviewData? = nil,
                       linkPreviewMedia: PendingMedia? = nil) {

        sendMessage(text: mentionText.trimmed().collapsedText, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
        view.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }

    func composerDidTapBack(controller: PostComposerViewController, destination: PostComposerDestination, media: [PendingMedia], voiceNote: PendingMedia?) {
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
