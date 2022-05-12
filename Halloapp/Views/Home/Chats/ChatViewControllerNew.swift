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
    case chatEvent
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

    private var chatMessageFetchedResultsController: NSFetchedResultsController<ChatMessage>?

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
                case .unreadCountHeader(_), .chatCall, .chatEvent:
                    return UICollectionViewCell()
                }
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

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        switch controller {
        case chatMessageFetchedResultsController:
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
            dataSource.apply(snapshot, animatingDifferences: true) { // [weak self] in
                // guard let self = self else { return }
                // DispatchQueue.main.async {
                    //self.updateScrollingWhenDataChanges()
                    //self.scrollToTarget(withAnimation: true)
                    //self.isFirstLaunch = false
                // }
            }
        default:
            break
        }
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
        
    }

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
