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
    case chatCall
    case chatEvent(ChatEvent)

    var timestamp: Date? {
        switch self {
        case .chatEvent(let data):
            return data.timestamp
        case .chatMessage(let data), .retracted(let data), .media(let data), .audio(let data), .text(let data), .linkPreview(let data), .quoted(let data):
            return data.timestamp
        case .unreadCountHeader(_), .chatCall:
            return nil
        }
    }
}


class ChatViewControllerNew: UIViewController, NSFetchedResultsControllerDelegate, UICollectionViewDelegate {

    weak var delegate: ChatViewControllerDelegate?

    /// The `userID` of the user the client is receiving messages from
    private var fromUserId: String?
    private var feedPostId: FeedPostID?

    fileprivate typealias ChatDataSource = UICollectionViewDiffableDataSource<String, MessageRow>
    fileprivate typealias ChatMessageSnapshot = NSDiffableDataSourceSnapshot<String, MessageRow>

    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let messageCellViewTextReuseIdentifier = "MessageCellViewText"
    static private let messageCellViewMediaReuseIdentifier = "MessageCellViewMedia"
    static private let messageCellViewAudioReuseIdentifier = "MessageCellViewAudio"
    static private let messageCellViewLinkPreviewReuseIdentifier = "MessageCellViewLinkPreview"
    static private let messageCellViewQuotedReuseIdentifier = "MessageCellViewQuoted"
    static private let messageCellViewEventReuseIdentifier = "MessageCellViewEvent"

    private var chatMessageFetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var chatEventFetchedResultsController: NSFetchedResultsController<ChatEvent>?

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
                case .unreadCountHeader(_), .chatCall:
                    return UICollectionViewCell()
                }
                return UICollectionViewCell()
            })
        dataSource.supplementaryViewProvider = { [weak self] ( view, kind, index) in
            if kind == MessageTimeHeaderView.elementKind {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageTimeHeaderView.elementKind, for: index)
                if let messageTimeHeaderView = headerView as? MessageTimeHeaderView, let self = self, let sections = self.chatMessageFetchedResultsController?.sections{
                    let section = sections[index.section ]
                    messageTimeHeaderView.configure(headerText: section.name)
                    return messageTimeHeaderView
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
        var snapshot = ChatMessageSnapshot()
        if let sections = chatMessageFetchedResultsController?.sections {
            snapshot.appendSections(sections.map { $0.name } )
            for section in sections {
                if let chatMessages = section.objects as? [ChatMessage] {
                    chatMessages.forEach { chatMessage in
                        let messageRow = messagerow(for: chatMessage)
                        snapshot.appendItems([messageRow], toSection: section.name)
                    }
                }
            }
        }
        if let sections = chatEventFetchedResultsController?.sections {
            for section in sections {
                if !snapshot.sectionIdentifiers.contains(section.name) {
                    snapshot.appendSections([section.name])
                }
                if let chatEvents = section.objects as? [ChatEvent] {
                    chatEvents.forEach { chatEvent in
                        let eventMessageRow = MessageRow.chatEvent(chatEvent)
                        // Add the new event
                        snapshot.appendItems([eventMessageRow], toSection: section.name)
                        // Sort items based on timestamp
                        let sortedRows = snapshot.itemIdentifiers(inSection: section.name).sorted {
                            ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture)
                        }
                        // Update snapshot with sorted items
                        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: section.name))
                        snapshot.appendItems(sortedRows, toSection: section.name)
                    }
                }
            }
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

        // Setup title view
        navigationItem.titleView = titleView
        titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
        titleView.checkIfUnknownContactWithPushNumber(userID: fromUserId)
        
        view.addSubview(collectionView)
        collectionView.constrain(to: view)
        setupUI()
        
    }

    private func setupUI() {
        collectionView.dataSource = dataSource
        setupChatMessageFetchedResultsController()
        setupChatEventFetchedResultsController()
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
        
        chatMessageFetchedResultsController = NSFetchedResultsController<ChatMessage>(fetchRequest: fetchChatMessageRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: "headerTime", cacheName: nil)
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

        chatEventFetchedResultsController = NSFetchedResultsController<ChatEvent>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext, sectionNameKeyPath: "headerTime", cacheName: nil)
        chatEventFetchedResultsController?.delegate = self
        do {
            DDLogError("ChatViewControllerNew/initFetchedResultsController/fetching chat events from user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
            try chatEventFetchedResultsController!.performFetch()
        } catch {DDLogError("ChatViewControllerNew/initFetchedResultsController/failed to fetch  chat eventsfrom user: \(userID) to user: \(MainAppContext.shared.userData.userId)")
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
}

// MARK: ChatTitle Delegates
extension ChatViewControllerNew: ChatTitleViewDelegate {
    func chatTitleView(_ chatTitleView: ChatTitleView) {
        guard let userId = fromUserId else { return }
        let userViewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(userViewController, animated: true)
    }
}

extension ChatMessage {
  @objc var headerTime: String? {
      get {
          return timestamp?.chatMsgGroupingTimestamp(Date())
      }
  }
}

extension ChatEvent {
    @objc var headerTime: String? {
        get {
            return timestamp.chatMsgGroupingTimestamp(Date())
        }
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
