//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import ContactsUI
import Core
import CoreData
import Photos
import SafariServices
import UIKit

fileprivate struct Constants {
    static let WidthOfMsgBubble:CGFloat = 0.8
}

fileprivate class ChatDataSource: UITableViewDiffableDataSource<Int, ChatMessage> {
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ chatViewController: ChatViewController, userActioned: Bool)
}

class ChatViewController: UIViewController, NSFetchedResultsControllerDelegate {

    weak var delegate: ChatViewControllerDelegate?
    
    /// The `userID` of the user the client is receiving messages from
    private var fromUserId: String?
    private var feedPostId: FeedPostID?
    private var feedPostMediaIndex: Int32 = 0

    private var chatReplyMessageID: String?
    private var chatReplyMessageSenderID: String?
    private var chatReplyMessageMediaIndex: Int32 = 0

    private var fetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var dataSource: ChatDataSource?

    private var trackedChatMessages: [String: TrackedChatMessage] = [:]

    static private let sectionMain = 0
    static private let inboundMsgViewCellReuseIdentifier = "InboundMsgViewCell"
    static private let outboundMsgViewCellReuseIdentifier = "OutboundMsgViewCell"

    private let waitForCellTimeout: TimeInterval = 0.25

    private var currentUnseenChatThreadsList: [UserID: Int] = [:]
    private var currentUnseenGroupChatThreadsList: [GroupID: Int] = [:]

    private var cancellableSet: Set<AnyCancellable> = []

    private var firstActionHappened: Bool = false

    // MARK: Lifecycle

    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        DDLogDebug("ChatViewController/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId))]")
        self.fromUserId = fromUserId
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        guard let fromUserId = fromUserId else { return }

        super.viewDidLoad()

        preventNavLoop()

        let navAppearance = UINavigationBarAppearance()
        navAppearance.backgroundColor = UIColor.primaryBg
        navAppearance.shadowColor = nil
        navAppearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance

        let titleWidthConstraint = titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.8))
        titleWidthConstraint.priority = .defaultHigh // Lower priority to allow space for trailing button if necessary
        titleWidthConstraint.isActive = true

        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
        
        view.addSubview(tableView)
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        tableView.backgroundColor = UIColor.primaryBg

        tableView.rowHeight = UITableView.automaticDimension

        DispatchQueue.main.async { [weak self] in
            self?.setupOrRefreshHeaderAndFooter()
        }

        dataSource = ChatDataSource(tableView: tableView) { [weak self] tableView, indexPath, chatMessage in
            guard let self = self else { return nil }

            self.trackedChatMessages[chatMessage.id] = TrackedChatMessage(with: chatMessage)
            
            var isPreviousMsgSameSender = false
            var isNextMsgSameSender = false
            var isNextMsgSameTime = false
            
            var isNextMsgDifferentDay = false
            
            let previousRow = indexPath.row - 1
            let nextRow = indexPath.row + 1

            if previousRow >= 0 {
                let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)
                if let previousChatMessage = self.fetchedResultsController?.object(at: previousIndexPath) {
                    if previousChatMessage.fromUserId == chatMessage.fromUserId {
                        isPreviousMsgSameSender = true
                    }
                    
                    if let previousMsgTime = previousChatMessage.timestamp, let currentMsgTime = chatMessage.timestamp  {
                        if !Calendar.current.isDate(previousMsgTime, inSameDayAs: currentMsgTime) {
                            isNextMsgDifferentDay = true
                        }
                    }
                }
            } else {
                isNextMsgDifferentDay = true
            }

            if nextRow < tableView.numberOfRows(inSection: 0) {
                let nextIndexPath = IndexPath(row: nextRow, section: indexPath.section)
                if let nextChatMessage = self.fetchedResultsController?.object(at: nextIndexPath) {
                    if nextChatMessage.fromUserId == chatMessage.fromUserId {
                        isNextMsgSameSender = true
                        if nextChatMessage.timestamp?.chatTimestamp() == chatMessage.timestamp?.chatTimestamp() {
                            isNextMsgSameTime = true
                        }
                    }
                }
            }
            
           //TODO: refactor out/inbound cells and update params after ui stabilize
            
            if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.outboundMsgViewCellReuseIdentifier, for: indexPath) as? OutboundMsgViewCell {
                    cell.indexPath = indexPath
                    cell.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)

                    if isNextMsgDifferentDay {
                        cell.addDateRow(timestamp: chatMessage.timestamp)
                    }

                    cell.msgViewCellDelegate = self
                    cell.delegate = self
                    return cell
                }
            } else {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.inboundMsgViewCellReuseIdentifier, for: indexPath) as? InboundMsgViewCell {
                    cell.indexPath = indexPath
                    cell.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)

                    if isNextMsgDifferentDay {
                        cell.addDateRow(timestamp: chatMessage.timestamp)
                    }

                    cell.msgViewCellDelegate = self
                    cell.delegate = self
                    return cell
                }
            }
            return UITableViewCell()
        }

        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(fromUserId = %@ AND toUserId = %@) || (toUserId = %@ && fromUserId = %@)", self.fromUserId!, MainAppContext.shared.userData.userId, self.fromUserId!, AppContext.shared.userData.userId)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.id, ascending: true) // if timestamps are the same, break tie
        ]
        
        fetchedResultsController =
            NSFetchedResultsController<ChatMessage>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController?.delegate = self
        do {
            try fetchedResultsController!.performFetch()
            updateDataInMainQueue(animatingDifferences: false)

        } catch {
            return
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        view.addGestureRecognizer(tapGesture)
        
        if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.text, mentions: feedPost.orderedMentions)
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    let mediaType: ChatMessageMediaType = mediaItem.type == .video ? .video : .image
                    let mediaUrl = MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)

                    chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: mentionText?.string ?? "", mediaType: mediaType, mediaUrl: mediaUrl, from: self)
                } else {
                    chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: mentionText?.string ?? "", mediaType: nil, mediaUrl: nil, from: self)
                }
            }
        }
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] status, ts in
                DDLogInfo("ChatViewController/didGetCurrentChatPresence")
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
                DDLogInfo("ChatViewController/didGetChatStateInfo \(chatStateInfo)")
                DispatchQueue.main.async {
                    self.configureTitleViewWithTypingIndicator()
                }
            }
        )
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAChatMsg.sink { [weak self] (userID) in
                guard let self = self else { return }
                guard userID != self.fromUserId else { return }
                
                if self.currentUnseenChatThreadsList[userID] == nil {
                    self.currentUnseenChatThreadsList[userID] = 1
                } else {
                    self.currentUnseenChatThreadsList[userID]? += 1
                }
                
                DispatchQueue.main.async {
                    let total = self.currentUnseenChatThreadsList.count + self.currentUnseenGroupChatThreadsList.count
                    self.updateBackButtonUnreadCount(num: total)
                }
            }
        )

        // Update name in title view if we just discovered this new user.
        cancellableSet.insert(
            MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] (newUserIDs) in
                DDLogInfo("ChatViewController/didDiscoverNewUsers/update name if necessary")
                guard let self = self else { return }
                guard let userID = self.fromUserId else { return }
                if newUserIDs.contains(userID) {
                    self.titleView.refreshName(for: userID)
                }
                if let headerView = self.tableView.tableHeaderView as? ChatHeaderView {
                    headerView.configureOrRefresh(with: userID)
                }
                self.chatInputView.isHidden = false
                self.unknownContactActionBanner.isHidden = true
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.didPrivacySettingChange.sink { [weak self] (userID) in
                DDLogInfo("ChatViewController/didPrivacySettingChange/update header")
                guard let self = self else { return }
                guard userID == self.fromUserId else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.setupOrRefreshHeaderAndFooter()
                }
            }
        )

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.pauseVoiceNotes()
        })

        configureTitleViewWithTypingIndicator()
        
        loadChatDraft(id: fromUserId)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        chatInputView.willAppear(in: self)
        tabBarController?.hideTabBar(vc: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.tableFooterView = nil
        let scrollPoint = CGPoint(x: 0, y: tableView.contentSize.height)
        tableView.setContentOffset(scrollPoint, animated: false)

        // scroll again after setting contentOffset cause for some reason it would
        // not scroll to the very bottom sometimes (by a few points) in iOS 14 and 15
        // dispatch is needed for iOS 14
        DispatchQueue.main.async {
            self.scrollToBottom(false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let chatWithUserId = self.fromUserId {
            MainAppContext.shared.chatData.markThreadAsRead(type: .oneToOne, for: chatWithUserId)
            MainAppContext.shared.chatData.updateUnreadChatsThreadCount()
            MainAppContext.shared.chatData.updateUnreadMessageCount()
            MainAppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)

            UNUserNotificationCenter.current().removeDeliveredChatNotifications(fromUserId: chatWithUserId)
        }
        chatInputView.didAppear(in: self)
        
        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        keyWindow.addSubview(jumpButton)
        jumpButton.trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor).isActive = true
        jumpButtonConstraint = jumpButton.bottomAnchor.constraint(equalTo: keyWindow.bottomAnchor, constant: -100)
        jumpButtonConstraint?.isActive = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let id = fromUserId {
            saveChatDraft(id: id)
        }
        pauseVoiceNotes()
        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        chatInputView.willDisappear(in: self)
        
        jumpButton.removeFromSuperview()
        
        navigationController?.navigationBar.backItem?.backBarButtonItem = UIBarButtonItem()
    }
    
    deinit {
        DDLogDebug("ChatViewController/deinit/\(fromUserId ?? "")")
    }

    private func pauseVoiceNotes() {
        for cell in tableView.visibleCells {
            if let cell = cell as? OutboundMsgViewCell {
                cell.pauseVoiceNote()
            } else if let cell = cell as? InboundMsgViewCell {
                cell.pauseVoiceNote()
            }
        }
    }

    private func playVoiceNote(after indexPath: IndexPath) {
        var nextIndexPath = indexPath
        nextIndexPath.row += 1

        guard let numberOfObjects = fetchedResultsController?.sections?[nextIndexPath.section].numberOfObjects else { return }
        guard nextIndexPath.row < numberOfObjects else { return }
        guard let nextChatMessage = fetchedResultsController?.object(at: nextIndexPath) else { return }
        guard nextChatMessage.media?.first?.type == .audio else { return }

        tableView.scrollToRow(at: nextIndexPath, at: .middle, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + waitForCellTimeout) {
            guard let cell = self.tableView.cellForRow(at: nextIndexPath) else { return }

            if let cell = cell as? OutboundMsgViewCell {
                cell.playVoiceNote()
            } else if let cell = cell as? InboundMsgViewCell {
                cell.playVoiceNote()
            }
        }
    }
    
    private func updateBackButtonUnreadCount(num: Int) {
        let backButton = UIBarButtonItem()
        backButton.title = num > 0 ? String(num) : " \u{00a0}"

        navigationController?.navigationBar.backItem?.backBarButtonItem = backButton
    }
    
    /// Saves the text currently in the `ChatInputView` into `UserDefaults` to be restored on the next time the user opens the view.
    /// - Parameter id: The UserID of the other user in the chat.
    private func saveChatDraft(id: UserID) {
        guard !chatInputView.text.isEmpty else {
            removeChatDraft()
            return
        }
        
        let draft = ChatDraft(chatID: id, text: chatInputView.text, replyContext: encodeReplyData())
        
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
                          replyMediaIndex: chatReplyMessageMediaIndex,
                          text: replyMessage.text ?? "",
                          media: media)
                    
                    return reply
                }
            }
            
            let reply = ReplyContext(replyMessageID: replyMessageID,
                  replySenderID: replySenderID,
                  replyMediaIndex: chatReplyMessageMediaIndex,
                  text: replyMessage.text ?? "",
                  media: nil)
            
            return reply
        } else if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.text, mentions: feedPost.orderedMentions)
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    let mediaType: ChatMessageMediaType = mediaItem.type == .video ? .video : .image
                    let mediaUrl = MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
                    
                    let reply = ReplyContext(replyMessageID: feedPostId,
                                             replySenderID: feedPost.userId,
                                             replyMediaIndex: nil,
                                             text: mentionText?.string ?? "",
                                             media: ChatReplyMedia(type: mediaType, mediaURL: mediaUrl.absoluteString))
                    return reply
                } else {
                    let reply = ReplyContext(replyMessageID: feedPostId,
                                             replySenderID: feedPost.userId,
                                             replyMediaIndex: nil,
                                             text: mentionText?.string ?? "",
                                             media: nil)
                    return reply
                }
            }
        }
        
        return nil
    }
    
    /// Restores the text from `UserDefaults` into the `ChatInputView` so the user can continue what they last wrote.
    /// - Parameter id: The UserID of the other user in the chat.
    private func loadChatDraft(id: UserID) {
        guard let draftsArray: [ChatDraft] = try? AppContext.shared.userDefaults.codable(forKey: "chats.drafts") else { return }
        guard let draft = draftsArray.first(where: { existingDraft in
            existingDraft.chatID == fromUserId
        }) else { return }
        
        chatInputView.setDraftText(text: draft.text)
        
        if let reply = draft.replyContext {
            handleDraftQuotedReply(reply: reply)
            
            chatReplyMessageID = reply.replyMessageID
            chatReplyMessageSenderID = reply.replySenderID
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
    
    // MARK:

    private func shouldShowVerifyOption() -> Bool {
        guard let otherUserID = fromUserId,
              let otherKeyBundle = MainAppContext.shared.keyStore.messageKeyBundle(for: otherUserID)?.keyBundle,
              SafetyNumberData(keyBundle: otherKeyBundle) != nil
        else {
            // TODO: Allow user to verify without existing key bundle
            return false
        }

        return true
    }

    private func presentMediaExplorer(media: [ChatMedia], At index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        let controller = MediaExplorerController(media: media, index: index)
        controller.delegate = delegate

        present(controller.withNavigationController(), animated: true)
    }

    private func presentMediaExplorer(media: [ChatQuotedMedia], At index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        let controller = MediaExplorerController(media: media, index: index)
        controller.delegate = delegate

        present(controller.withNavigationController(), animated: true)
    }

    private func setupOrRefreshHeaderAndFooter() {
        guard let userID = fromUserId else { return }
        let isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        let isUserInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID)
        let isPushNumberMessagingAccepted = MainAppContext.shared.contactStore.isPushNumberMessagingAccepted(userID: userID)
        let haveMessagedBefore = MainAppContext.shared.chatData.haveMessagedBefore(userID: userID, in: MainAppContext.shared.chatData.viewContext)

        let showUnknownContactActionBanner = !isUserBlocked &&
                                             !isUserInAddressBook &&
                                             !isPushNumberMessagingAccepted &&
                                             !haveMessagedBefore

        if showUnknownContactActionBanner {
            if view.subviews.contains(unknownContactActionBanner) {
                unknownContactActionBanner.removeFromSuperview()
            }
            view.addSubview(unknownContactActionBanner)
            unknownContactActionBanner.constrain([.leading, .trailing, .bottom], to: view.safeAreaLayoutGuide)
        }
        
        unknownContactActionBanner.isHidden = !showUnknownContactActionBanner
        chatInputView.isHidden = showUnknownContactActionBanner

        var headerHeight: CGFloat = 90
        if isUserBlocked {
            headerHeight = 130
        } else if !isUserInAddressBook {
            headerHeight = 150
        }
        let chatHeaderView = ChatHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: headerHeight))
        chatHeaderView.configureOrRefresh(with: userID)
        chatHeaderView.delegate = self
        tableView.tableHeaderView = chatHeaderView

        tableView.tableFooterView = nil
    }

    private lazy var titleView: TitleView = {
        let titleView = TitleView()
        titleView.delegate = self
        titleView.translatesAutoresizingMaskIntoConstraints = false
        return titleView
    }()
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.keyboardDismissMode = .interactive
        tableView.preservesSuperviewLayoutMargins = true
        tableView.register(InboundMsgViewCell.self, forCellReuseIdentifier: ChatViewController.inboundMsgViewCellReuseIdentifier)
        tableView.register(OutboundMsgViewCell.self, forCellReuseIdentifier: ChatViewController.outboundMsgViewCellReuseIdentifier)
        tableView.delegate = self
        return tableView
    }()

    private var jumpButtonUnreadCount: Int = 0
    private var jumpButtonConstraint: NSLayoutConstraint?

    private lazy var jumpButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ jumpButtonUnreadCountLabel, jumpButtonImageView ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 5
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        jumpButtonImageView.widthAnchor.constraint(equalToConstant: 30).isActive = true
        jumpButtonImageView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        
        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.9)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(jumpDown(_:)))
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
    
    private lazy var unknownContactActionBanner: UnknownContactActionBanner = {
        let view = UnknownContactActionBanner()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.acceptAction = { [weak self] in
            guard let self = self else { return }
            guard let userID = self.fromUserId else { return }
            MainAppContext.shared.contactStore.setIsMessagingAccepted(userID: userID, isMessagingAccepted: true)
            self.unknownContactActionBanner.isHidden = true
            self.chatInputView.isHidden = false
        }

        view.blockAction = { [weak self] in
            guard let self = self else { return }
            guard let userID = self.fromUserId else { return }
            let blockMessage = Localizations.blockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID))

            let alert = UIAlertController(title: nil, message: blockMessage, preferredStyle: .actionSheet)
            let button = UIAlertAction(title: Localizations.blockButton, style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                let privacySettings = MainAppContext.shared.privacySettings
                guard let blockedList = privacySettings.blocked else { return }

                privacySettings.replaceUserIDs(in: blockedList, with: blockedList.userIds + [userID])
                MainAppContext.shared.didPrivacySettingChange.send(userID)
            }
            alert.addAction(button)

            let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
            alert.addAction(cancel)

            self.present(alert, animated: true)
        }

        return view
    }()

    // MARK: Data

    private var shouldScrollToBottom = false
    private var shouldUpdate = false
    
    private func isCellHeightUpdate(for chatMessage: ChatMessage) -> Bool {
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return false }
        if trackedChatMessage.cellHeight != chatMessage.cellHeight {
            return true
        }
        return false
    }
    
    private func isRetractStatusUpdate(for chatMessage: ChatMessage) -> Bool {
        guard chatMessage.toUserId == MainAppContext.shared.userData.userId else { return false }
        if chatMessage.incomingStatus == .retracted {
            return true
        }
        if [.retracting, .retracted].contains(chatMessage.outgoingStatus) {
            return true
        }
        return false
    }
    
    private func isOutgoingMessageStatusUpdate(for chatMessage: ChatMessage) -> Bool {
        guard chatMessage.fromUserId == MainAppContext.shared.userData.userId else { return false }
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return false }
        if trackedChatMessage.outgoingStatus != chatMessage.outgoingStatus {
            return true
        }
        return false
    }

    private func isRerequestStatusUpdate(for chatMessage: ChatMessage) -> Bool {
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return false }
        if trackedChatMessage.incomingStatus == .rerequesting &&
            chatMessage.incomingStatus != .rerequesting
        {
            return true
        }
        return false
    }
    
    private func findUpdatedMedia(for chatMessage: ChatMessage) -> ChatMedia? {
        guard chatMessage.fromUserId != MainAppContext.shared.userData.userId else { return nil }
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return nil }
        guard let media = chatMessage.media else { return nil }
        for med in media {
            guard med.relativeFilePath != nil else { continue }
            if trackedChatMessage.media[Int(med.order)].relativeFilePath == nil {
                self.trackedChatMessages[chatMessage.id]?.media[Int(med.order)].relativeFilePath = med.relativeFilePath
                return med
            }
        }
        return nil
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
                    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
        case .update:
            DDLogDebug("ChatViewController/frc/update")
            shouldUpdate = false
            guard let chatMessage = anObject as? ChatMessage else { break }
            guard let indexPath = indexPath else { break }

            if isRetractStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/inboundMessageStatusChange")
                shouldUpdate = true
            } else if isOutgoingMessageStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/outgoingMessageStatusChange")
                shouldUpdate = true
            } else if isRerequestStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/rerequestStatusUpdate")
                shouldUpdate = true
            }

            // inbound message media changes, update directly
            if let updatedChatMedia = findUpdatedMedia(for: chatMessage) {
                guard let cell = self.tableView.cellForRow(at: indexPath) as? InboundMsgViewCell else { break }
                DDLogDebug("ChatViewController/frc/update-cell-directly/updatedMedia")
                cell.updateMedia(updatedChatMedia)
            }

            // iOS 15.0 datasource.apply either can't detect changes like status or will not apply changes
            // so we do a manual reconfigure of those cells
            // future task could be to revisit and refactor using a diffable struct instead of managed objects
            if #available(iOS 15.0, *) {
                guard shouldUpdate else {
                    DDLogDebug("ChatViewController/frc/update/iOS15.0/reconfigureItems/skipping")
                    break
                }
                guard let item = dataSource?.itemIdentifier(for: indexPath) else { break }
                guard var newSnapshot = dataSource?.snapshot() else { break }
                newSnapshot.reconfigureItems([item])
                dataSource?.apply(newSnapshot, animatingDifferences: false)
            }
        case .insert:
            DDLogDebug("ChatViewController/frc/insert")
            guard let chatMsg = anObject as? ChatMessage else { break }
            shouldUpdate = true
            shouldScrollToBottom = checkIfShouldScrollToBottom(chatMsg)
        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard shouldUpdate else {
            DDLogDebug("ChatViewController/frc/update/skipping")
            return
        }

        updateData(animatingDifferences: false)
    }

    private func updateData(animatingDifferences: Bool) {
        DispatchQueue.main.async {
            self.updateDataInMainQueue(animatingDifferences: animatingDifferences)
        }
    }

    private func updateDataInMainQueue(animatingDifferences: Bool = true) {
        guard let chatMessages = self.fetchedResultsController?.fetchedObjects else { return}

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, ChatMessage>()
        diffableDataSourceSnapshot.appendSections([ ChatViewController.sectionMain ])
        diffableDataSourceSnapshot.appendItems(chatMessages)

        dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences) { [weak self] in
            guard let self = self else { return }
            guard self.shouldScrollToBottom else { return }
            self.scrollToBottom(true)
            self.shouldScrollToBottom = false
        }
    }

    // MARK: Helpers

    // special case to prevent user from chaining a loop-like navigation stack
    private func preventNavLoop() {
        guard let nc = navigationController else { return }
        var viewControllers = nc.viewControllers
        guard viewControllers.count >= 3 else { return }
        let secondLast = viewControllers.count - 2
        let thirdLast = viewControllers.count - 3
        guard viewControllers[secondLast].isKind(of: UserFeedViewController.self),
              viewControllers[thirdLast].isKind(of: ChatViewController.self) else { return }
        DDLogInfo("ChatViewController/preventNavLoop")
        viewControllers.remove(at: secondLast)
        viewControllers.remove(at: thirdLast)
        navigationController?.viewControllers = viewControllers
    }

    private func checkIfShouldScrollToBottom(_ chatMsg: ChatMessage) -> Bool {
        var result = true
        guard chatMsg.fromUserId != MainAppContext.shared.userData.userId else { return result }
        
        if jumpButton.isHidden == false {
            result = false
            jumpButtonUnreadCount += 1
            jumpButtonUnreadCountLabel.text = String(jumpButtonUnreadCount)
        }
        
        return result
    }

    private func scrollToBottom(_ animated: Bool = true) {
        guard let dataSnapshot = self.dataSource?.snapshot() else { return }
        let numberOfRows = dataSnapshot.numberOfItems(inSection: ChatViewController.sectionMain)
        guard numberOfRows > 0 else { return }
        let indexPath = IndexPath(row: numberOfRows - 1, section: ChatViewController.sectionMain)

        if animated {
            let scrollPoint = CGPoint(x: 0, y: self.tableView.contentSize.height)
            self.tableView.setContentOffset(scrollPoint, animated: true)
            DispatchQueue.main.async {
                // use our own animation because for some reason tableView's animation gets interrupted intermittently
                UIView.animate(withDuration: 0.3, animations: {
                    self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
                })
            }
        } else {
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        }
    }

    private func configureTitleViewWithTypingIndicator() {
        guard let userID = self.fromUserId else { return }
        let typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .oneToOne, id: userID)

        if typingIndicatorStr == nil && !titleView.isShowingTypingIndicator {
            return
        }

        titleView.showChatState(with: typingIndicatorStr)
    }

    private func updateJumpButtonVisibility() {
        let fromTheBottom = UIScreen.main.bounds.height*1.5 - chatInputView.bottomInset

        if tableView.contentSize.height - tableView.contentOffset.y > fromTheBottom {
            // using chatInput instead of tableView.contentInset.bottom since for some reason that changes when entering app from a notification
            let aboveChatInput = chatInputView.bottomInset + 50
            jumpButtonConstraint?.constant = -aboveChatInput
            jumpButton.isHidden = false
        } else {
            jumpButton.isHidden = true
            jumpButtonUnreadCount = 0
            jumpButtonUnreadCountLabel.text = nil
        }
    }

    private func jumpToMsg(_ indexPath: IndexPath) {
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }

        guard let chatReplyMessageID = message.chatReplyMessageID else { return }

        guard let allMessages = fetchedResultsController?.fetchedObjects else { return }
        guard let replyMessage = allMessages.first(where: {$0.id == chatReplyMessageID}) else { return }

        guard let index = allMessages.firstIndex(of: replyMessage) else { return }

        let toIndexPath = IndexPath(row: index, section: ChatViewController.sectionMain)

        tableView.scrollToRow(at: toIndexPath, at: .middle, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + waitForCellTimeout) {
            if replyMessage.fromUserId == MainAppContext.shared.userData.userId {
                guard let cell = self.tableView.cellForRow(at: toIndexPath) as? OutboundMsgViewCell else { return }
                cell.highlight()
            } else {
                guard let cell = self.tableView.cellForRow(at: toIndexPath) as? InboundMsgViewCell else { return }
                cell.highlight()
            }
        }
    }

    // MARK: Actions

    @IBAction func jumpDown(_ sender: Any?) {
        scrollToBottom()
    }
    
    // MARK: Input view

    public func showKeyboard() {
        chatInputView.showKeyboard(from: self)
    }

    lazy var chatInputView: ChatInputView = {
        let inputView = ChatInputView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 90))
        inputView.delegate = self

        if let fromUserId = fromUserId {
            if let url = AudioRecorder.voiceNote(from: MainAppContext.shared.userData.userId, to: fromUserId) {
                inputView.show(voiceNote: url)
            }
        }

        return inputView
    }()

    override var inputAccessoryView: UIView? {
        chatInputView.setInputViewWidth(view.bounds.size.width)
        return chatInputView
    }

    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }

    func updateTableViewContentInsets(with keyboardHeight: CGFloat, adjustContentOffset: Bool) {
        let topInset = tableView.contentInset.top
        let extraBottomInset: CGFloat = 10 // extra margin for the bottom of the table
        let bottomInset = keyboardHeight - tableView.safeAreaInsets.bottom + extraBottomInset
        let currentInset = tableView.contentInset
        var contentOffset = tableView.contentOffset
        var adjustContentOffset = adjustContentOffset
        if bottomInset > currentInset.bottom && currentInset.bottom == 0 {
            // Because of the SwiftUI the accessory view appears with a slight delay
            // and bottom inset increased from 0 to some value. Do not scroll when that happens.
            adjustContentOffset = false
        }
        
        if adjustContentOffset {
            contentOffset.y += bottomInset - currentInset.bottom
        }
        if (adjustContentOffset) {
            tableView.contentOffset = contentOffset
        }
        // Setting contentInset below will also adjust contentOffset as needed if it is outside of the
        // UITableView's scrollable range.
        tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        let scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        tableView.scrollIndicatorInsets = scrollIndicatorInsets
    }

    func sendMessage(text: String, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?) {
        guard let sendToUserId = self.fromUserId else { return }

        MainAppContext.shared.chatData.sendMessage(toUserId: sendToUserId,
                                                   text: text,
                                                   media: media,
                                                   linkPreviewData: linkPreviewData,
                                                   linkPreviewMedia : linkPreviewMedia,
                                                   feedPostId: feedPostId,
                                                   feedPostMediaIndex: feedPostMediaIndex,
                                                   chatReplyMessageID: chatReplyMessageID,
                                                   chatReplyMessageSenderID: chatReplyMessageSenderID,
                                                   chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)

        chatInputView.closeQuoteFeedPanel()

        feedPostId = nil
        feedPostMediaIndex = 0

        chatReplyMessageID = nil
        chatReplyMessageSenderID = nil
        chatReplyMessageMediaIndex = 0

        chatInputView.text = ""
        
        removeChatDraft()

        if !firstActionHappened {
            delegate?.chatViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func presentMediaPicker() {
        let vc = MediaPickerViewController(camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }
            if cancel {
                self.dismiss(animated: true)
            } else {
                self.presentMediaComposer(pickerController: controller, media: media)
            }
        }

        present(UINavigationController(rootViewController: vc), animated: true)

        if !firstActionHappened {
            delegate?.chatViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func presentMediaComposer(pickerController: MediaPickerViewController, media: [PendingMedia]) {
        let composerController = PostComposerViewController(
            mediaToPost: media,
            initialInput: MentionInput(text: chatInputView.text, mentions: MentionRangeMap(), selectedRange: NSRange()),
            recipientName: fromUserId != nil ? MainAppContext.shared.contactStore.fullName(for: fromUserId!) : nil,
            configuration: .message,
            delegate: self)
        pickerController.present(UINavigationController(rootViewController: composerController), animated: false)
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        chatInputView.hideKeyboard()
    }
}

// MARK: ChatHeaderViewDelegates
extension ChatViewController: ChatHeaderViewDelegate {

    func chatHeaderViewOpenEncryptionBlog(_ chatHeaderView: ChatHeaderView) {
        let viewController = SFSafariViewController(url: URL(string: "https://halloapp.com/blog/encrypted-chat")!)
        present(viewController, animated: true)
    }

    func chatHeaderViewUnblockContact(_ chatHeaderView: ChatHeaderView) {
        guard let userID = fromUserId else { return }

        let unBlockMessage = Localizations.unBlockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID))

        let alert = UIAlertController(title: nil, message: unBlockMessage, preferredStyle: .actionSheet)
        let button = UIAlertAction(title: Localizations.unBlockButton, style: .destructive) { _ in
            let privacySettings = MainAppContext.shared.privacySettings
            guard let blockedList = privacySettings.blocked else { return }

            var newBlockList = blockedList.userIds
            newBlockList.removeAll { value in return value == userID}
            privacySettings.replaceUserIDs(in: blockedList, with: newBlockList)

            MainAppContext.shared.didPrivacySettingChange.send(userID)
        }
        alert.addAction(button)

        let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
        alert.addAction(cancel)

        present(alert, animated: true)
    }

    func chatHeaderViewAddToContactsBook(_ chatHeaderView: ChatHeaderView) {
        guard let userID = fromUserId else { return }
        MainAppContext.shared.contactStore.addUserToAddressBook(userID: userID, presentingVC: self)
    }
}

extension ChatViewController: CNContactViewControllerDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: PostComposerView Delegates
extension ChatViewController: PostComposerViewDelegate {

    func composerDidTapShare(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData? = nil, linkPreviewMedia: PendingMedia? = nil) {
        sendMessage(text: mentionText.trimmed().collapsedText, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
        view.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }

    func composerDidTapBack(controller: PostComposerViewController, media: [PendingMedia]) {
        controller.dismiss(animated: false)

        let presentedVC = self.presentedViewController

        if let viewControllers = (presentedVC as? UINavigationController)?.viewControllers {
            if let mediaPickerController = viewControllers.last as? MediaPickerViewController {
                mediaPickerController.reset(selected: media)
            }
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        
    }
}

// MARK: UITableview Delegates
extension ChatViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let chatMessage = self.fetchedResultsController?.object(at: indexPath) else { return }
        let height = Int(cell.bounds.height)
       
        if chatMessage.cellHeight != height {
            DDLogDebug("ChatViewController/updateCellHeight/\(chatMessage.id) from \(chatMessage.cellHeight) to \(height)")
            MainAppContext.shared.chatData.updateChatMessageCellHeight(for: chatMessage.id, with: height)
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let chatMessage = self.fetchedResultsController?.object(at: indexPath) else { return 50 }

        if chatMessage.cellHeight != 0 {
            return CGFloat(chatMessage.cellHeight)
        }
        
        let result:CGFloat = 50
//        if chatMessage.quoted != nil {
//            result += 100
//        }
//
//        if chatMessage.media != nil {
//            if !chatMessage.media!.isEmpty {
//                result += 30
//            }
//        }

//        DDLogDebug("ChatViewController/estimateCellHeight/\(chatMessage.id)")
        return result
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? OutboundMsgViewCell {
            cell.pauseVoiceNote()
        } else if let cell = cell as? InboundMsgViewCell {
            cell.pauseVoiceNote()
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButtonVisibility()
    }
}

// MARK: UITableView Datasource Delegates
extension ChatViewController {
    // disable default swipe to delete
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return UITableViewCell.EditingStyle.none
    }
    
    private func handleQuotedReply(msg chatMessage: ChatMessage, mediaIndex: Int) {
        chatReplyMessageID = chatMessage.id
        chatReplyMessageSenderID = chatMessage.fromUserId
        chatReplyMessageMediaIndex = Int32(mediaIndex)
        
        guard let userID = chatReplyMessageSenderID else { return }
        
        if let mediaItem = chatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
            let mediaUrl = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
            
            chatInputView.showQuoteFeedPanel(with: userID, text: chatMessage.text ?? "", mediaType: mediaItem.type, mediaUrl: mediaUrl, from: self)
        } else {
            chatInputView.showQuoteFeedPanel(with: userID, text: chatMessage.text ?? "", mediaType: nil, mediaUrl: nil, from: self)
        }
    }

    private func handleDraftQuotedReply(reply: ReplyContext) {
        if let mediaURLString = reply.media?.mediaURL, let mediaURL = URL(string: mediaURLString) {
            chatInputView.showQuoteFeedPanel(with: reply.replySenderID, text: reply.text, mediaType: reply.media?.type, mediaUrl: mediaURL, from: self)
        } else {
            chatInputView.showQuoteFeedPanel(with: reply.replySenderID, text: reply.text, mediaType: nil, mediaUrl: nil, from: self)
        }
    }
}

extension ChatViewController: TitleViewDelegate {
    fileprivate func titleView(_ titleView: TitleView) {
        guard let userId = fromUserId else { return }
        let userViewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(userViewController, animated: true)
    }
}

// MARK: InboundMsgViewCell Delegates
extension ChatViewController: InboundMsgViewCellDelegate {

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        jumpToMsg(indexPath)
    }
    
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewMediaAt index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }
        guard message.media != nil else { return }

        presentMediaExplorer(media: message.orderedMedia, At: index, withDelegate: delegate)
    }

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewQuotedMediaAt index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }
        guard let quoted = message.quoted else { return }
        guard quoted.media != nil else { return }

        presentMediaExplorer(media: quoted.orderedMedia, At: index, withDelegate: delegate)
    }
    
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didLongPressOn msgId: String) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.object(at: indexPath) else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if chatMessage.incomingStatus != .retracted {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.handleQuotedReply(msg: chatMessage, mediaIndex: inboundMsgViewCell.mediaIndex)
             })
        
            if let messageText = chatMessage.text, !messageText.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = messageText
                })
            }

            if ServerProperties.isInternalUser {
                actionSheet.message = MainAppContext.shared.cryptoData.details(for: chatMessage.id, dateFormatter: DateFormatter.dateTimeFormatterMonthDayTime)
            }
        }
        
        guard actionSheet.actions.count > 0 else { return }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        
        self.present(actionSheet, animated: true)
    }

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didCompleteVoiceNote msgId: String) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        playVoiceNote(after: indexPath)
    }
    
}

// MARK: OutboundMsgViewCell Delegates
extension ChatViewController: OutboundMsgViewCellDelegate {
    
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        jumpToMsg(indexPath)
    }
    
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewMediaAt index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }
        guard message.media != nil else { return }

        presentMediaExplorer(media: message.orderedMedia, At: index, withDelegate: delegate)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewQuotedMediaAt index: Int, withDelegate delegate: MediaExplorerTransitionDelegate) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }
        guard let quoted = message.quoted else { return }
        guard quoted.media != nil else { return }

        presentMediaExplorer(media: quoted.orderedMedia, At: index, withDelegate: delegate)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didLongPressOn msgId: String) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.object(at: indexPath) else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if ![.retracting, .retracted].contains(chatMessage.outgoingStatus) {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.handleQuotedReply(msg: chatMessage, mediaIndex: outboundMsgViewCell.mediaIndex)
             })
            
            if let messageText = chatMessage.text, !messageText.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = messageText
                 })
            }
        }
        
        if [.sentOut, .delivered, .seen, .played].contains(chatMessage.outgoingStatus) {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                guard let toUserID = self.fromUserId else { return }
                MainAppContext.shared.chatData.retractChatMessage(toUserID: toUserID, messageToRetractID: chatMessage.id)
            })
        }
        
        guard actionSheet.actions.count > 0 else { return }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        
        self.present(actionSheet, animated: true)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didCompleteVoiceNote msgId: String) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        playVoiceNote(after: indexPath)
    }
    
}

extension ChatViewController: MsgViewCellDelegate {

    func msgViewCell(_ msgViewCell: MsgViewCell, replyTo msgId: String) {
        guard let indexPath = msgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.object(at: indexPath) else { return }

        guard chatMessage.incomingStatus != .retracted else { return }
        guard ![.retracting, .retracted].contains(chatMessage.outgoingStatus) else { return }

        if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
            guard let cell = tableView.cellForRow(at: indexPath) as? OutboundMsgViewCell else { return }
            handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
        } else {
            guard let cell = tableView.cellForRow(at: indexPath) as? InboundMsgViewCell else { return }
            handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
        }
    }

}

// MARK: ChatInputView Delegates
extension ChatViewController: ChatInputViewDelegate {
    func chatInputView(_ inputView: ChatInputView, didInterruptRecorder recorder: AudioRecorder) {
        guard let to = fromUserId else { return }
        guard let url = recorder.saveVoiceNote(from: MainAppContext.shared.userData.userId, to: to) else { return }

        DispatchQueue.main.async {
            self.chatInputView.show(voiceNote: url)
        }
    }
    
    func chatInputView(_ inputView: ChatInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        var animationDuration = animationDuration
        if transitionCoordinator != nil {
            animationDuration = 0
        }
        var adjustContentOffset = true
        // Prevent the content offset from changing when the user drags the keyboard down.
        if tableView.panGestureRecognizer.state == .ended || self.tableView.panGestureRecognizer.state == .changed {
            adjustContentOffset = false
        }
        
        let updateBlock = {
            self.updateTableViewContentInsets(with: inputView.bottomInset, adjustContentOffset: adjustContentOffset)
            self.updateJumpButtonVisibility()
        }
        if animationDuration > 0 {
            updateBlock()
        } else {
            UIView.performWithoutAnimation(updateBlock)
        }
    }
    
    func chatInputView(_ inputView: ChatInputView, isTyping: Bool) {
        guard let userID = fromUserId else { return }
        if isTyping {
            MainAppContext.shared.chatData.sendChatState(type: .oneToOne, id: userID, state: .typing)
        } else {
            MainAppContext.shared.chatData.sendChatState(type: .oneToOne, id: userID, state: .available)
        }
    }
    
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView) {
        feedPostId = nil
        feedPostMediaIndex = 0
        
        chatReplyMessageID = nil
        chatReplyMessageSenderID = nil
        chatReplyMessageMediaIndex = 0
    }
    
    func chatInputViewDidSelectMediaPicker(_ inputView: ChatInputView) {
        presentMediaPicker()
    }
    
    func chatInputViewDidPasteImage(_ inputView: ChatInputView, media: PendingMedia) {
        let composerController = PostComposerViewController(
            mediaToPost: [media],
            initialInput: MentionInput(text: chatInputView.text, mentions: MentionRangeMap(), selectedRange: NSRange()),
            recipientName: fromUserId != nil ? MainAppContext.shared.contactStore.fullName(for: fromUserId!) : nil,
            configuration: .message,
            delegate: self)
        present(UINavigationController(rootViewController: composerController), animated: false)
    }

    func chatInputViewMicrophoneAccessDenied(_ inputView: ChatInputView) {
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle, message: Localizations.micAccessDeniedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default, handler: { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsUrl)
        }))

        present(alert, animated: true)
    }
    
    func chatInputView(_ inputView: ChatInputView, mentionText: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?) {
        let text = mentionText.trimmed().collapsedText
        sendMessage(text: text, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
    }
}

fileprivate struct TrackedChatMedia {
    var relativeFilePath: String?
    let order: Int

    init(with chatMedia: ChatMedia) {
        self.order = Int(chatMedia.order)
        self.relativeFilePath = chatMedia.relativeFilePath
    }
}

fileprivate struct TrackedChatMessage {
    let id: String
    let cellHeight: Int
    let outgoingStatus: ChatMessage.OutgoingStatus
    let incomingStatus: ChatMessage.IncomingStatus
    var media: [TrackedChatMedia] = []

    init(with chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.cellHeight = Int(chatMessage.cellHeight)
        self.outgoingStatus = chatMessage.outgoingStatus
        self.incomingStatus = chatMessage.incomingStatus

        if let media = chatMessage.media {
            for med in media {
                self.media.append(TrackedChatMedia(with: med))
            }
        }
        self.media.sort {
            $0.order < $1.order
        }
    }
}

fileprivate protocol TitleViewDelegate: AnyObject {
    func titleView(_ titleView: TitleView)
}

fileprivate class TitleView: UIView {
    
    weak var delegate: TitleViewDelegate?
    
    public var isShowingTypingIndicator: Bool = false
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    func update(with fromUserId: String, status: UserPresenceType, lastSeen: Date?) {
        setNameLabel(for: fromUserId)
        
        switch status {
        case .away:
            // prefer to show last seen over typing
            if let lastSeen = lastSeen {
                lastSeenLabel.text = lastSeen.lastSeenTimestamp()
                typingLabel.isHidden = true
                lastSeenLabel.isHidden = false
            }
        case .available:
            // prefer to show typing over online
            lastSeenLabel.isHidden = !isShowingTypingIndicator ? false : true
            lastSeenLabel.text = Localizations.chatOnlineLabel
        default:
            lastSeenLabel.isHidden = true
            lastSeenLabel.text = ""
        }

        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
    }

    func refreshName(for userID: String) {
        setNameLabel(for: userID)
    }

    func showChatState(with typingIndicatorStr: String?) {
        let showTyping: Bool = typingIndicatorStr != nil
        
        lastSeenLabel.isHidden = showTyping
        typingLabel.isHidden = !showTyping
        isShowingTypingIndicator = showTyping
        
        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
    }
    
    private func setNameLabel(for userID: UserID) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, showPushNumber: true)
    }
    
    private func setup() {
        let imageSize: CGFloat = 32
        contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        contactImageView.heightAnchor.constraint(equalTo: contactImageView.widthAnchor).isActive = true
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let hStack = UIStackView(arrangedSubviews: [ contactImageView, nameColumn ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10
        
        addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoProfile))
        isUserInteractionEnabled = true
        addGestureRecognizer(tapGesture)
    }

    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [nameLabel, lastSeenLabel, typingLabel])
        view.axis = .vertical
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(ofFixedSize: 17, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var lastSeenLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()

    private lazy var typingLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()

    // MARK: actions

    @objc func gotoProfile(_ sender: UIView) {
        delegate?.titleView(self)
    }
}

class UnselectableUITextView: UITextView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let pos = closestPosition(to: point) else { return false }
        guard let range = tokenizer.rangeEnclosingPosition(pos, with: .character, inDirection: .layout(.left)) else {
            return false
        }
        let startIndex = offset(from: beginningOfDocument, to: range.start)
        return attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil
    }
}

protocol ChatHeaderViewDelegate: AnyObject {
    func chatHeaderViewOpenEncryptionBlog(_ chatHeaderView: ChatHeaderView)
    func chatHeaderViewUnblockContact(_ chatHeaderView: ChatHeaderView)
    func chatHeaderViewAddToContactsBook(_ chatHeaderView: ChatHeaderView)
}

class ChatHeaderView: UIView {
    weak var delegate: ChatHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configureOrRefresh(with userID: UserID) {
        let isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        let isContactInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID)
        let pushNumberExist = MainAppContext.shared.contactStore.pushNumber(userID) != nil

        let showAddToContactsBubble = !isUserBlocked && !isContactInAddressBook && pushNumberExist

        if showAddToContactsBubble {
            if let pushNumber = MainAppContext.shared.contactStore.pushNumber(userID) {
                addToContactsLabel.text = Localizations.chatAddToAddressBookLabel(pushNumber.formattedPhoneNumber)
            }
        }

        blockedContactBubbleColumn.isHidden = !isUserBlocked
        addToContactsBubble.isHidden = !showAddToContactsBubble
    }

    private func setup() {
        addSubview(mainColumn)
        mainColumn.constrain(to: self)
    }

    private lazy var mainColumn: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ encryptionBubbleColumn, blockedContactBubbleColumn, addToContactsBubble, spacer] )

        view.axis = .vertical
        view.alignment = .fill
        view.spacing = 20
        view.setCustomSpacing(20, after: encryptionBubble)

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 0, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var encryptionBubbleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ encryptionBubble ])
        view.axis = .vertical
        view.alignment = .fill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var encryptionBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ lockImageView, encryptionLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 5

        view.layoutMargins = UIEdgeInsets(top: 8, left: 15, bottom: 8, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatInfoBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openEncryptionBlog)))

        return view
    }()

    private lazy var lockImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "settingsPrivacy")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = UIColor.chatInfoBubble

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        return imageView
    }()

    private lazy var encryptionLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 4
        label.textAlignment = .center
        label.textColor = .chatInfoBubble
        label.font = UIFont.systemFont(ofSize: 12)
        label.adjustsFontForContentSizeCategory = true
        label.text = Localizations.chatEncryptionLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var blockedContactBubbleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ blockedContactBubble ])
        view.axis = .vertical
        view.alignment = .center
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    lazy var blockedContactBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ blockedContactLabel ])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatInfoBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(unblockContact)))
        return view
    }()

    private lazy var blockedContactLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 4
        label.textAlignment = .center
        label.textColor = .chatInfoBubble
        label.font = UIFont.systemFont(ofSize: 12)
        label.adjustsFontForContentSizeCategory = true
        label.text = Localizations.chatBlockedContactLabel

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var addToContactsBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ addToContactsLabel ])
        view.axis = .horizontal
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 8, left: 15, bottom: 8, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatInfoBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addToContactsBook)))
        view.isHidden = true
        return view
    }()

    private lazy var addToContactsLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 4
        label.textAlignment = .center
        label.textColor = .chatInfoBubble
        label.font = UIFont.systemFont(ofSize: 12)
        label.adjustsFontForContentSizeCategory = true

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    @objc private func openEncryptionBlog() {
        guard let delegate = delegate else { return }
        delegate.chatHeaderViewOpenEncryptionBlog(self)
    }

    @objc private func unblockContact() {
        guard let delegate = delegate else { return }
        delegate.chatHeaderViewUnblockContact(self)
    }

    @objc private func addToContactsBook() {
        guard let delegate = delegate else { return }
        delegate.chatHeaderViewAddToContactsBook(self)
    }

}

private extension Localizations {

    static var chatOnlineLabel: String {
        NSLocalizedString("chat.online.label", value: "online", comment: "Text below the contact's name when the contact is online in the Chat Screen")
    }

    static var chatEncryptionLabel: String {
        NSLocalizedString("chat.encryption.label", value: "Chats are end-to-end encrypted and HalloApp does not have access to them. Tap to learn more.", comment: "Text shown at the top of the chat screen informing the user that the chat is end-to-end encrypted")
    }
    
    static var chatBlockedContactLabel: String {
        NSLocalizedString("chat.blocked.contact.label", value: "Contact is blocked, tap to unblock", comment: "Text shown at the top of the chat screen informing the user that the contact is blocked")
    }

    static func chatAddToAddressBookLabel(_ name: String) -> String {
        let format = NSLocalizedString("chat.add.to.contacts.book.label",
                                       value: "To see posts from %@ add their number to your contact book.  Tap to add",
                                       comment: "Text shown at the top of the chat screen for contacts not in the user's address book that say the contact can be added to the address book")
        return String(format: format, name)
    }

    static var micAccessDeniedTitle: String {
        NSLocalizedString("chat.mic.access.denied.title", value: "Unable to access microphone", comment: "Alert title when missing microphone access")
    }

    static var micAccessDeniedMessage: String {
        NSLocalizedString("chat.mic.access.denied.message", value: "To enable audio recording, please tap on Settings and then turn on Microphone", comment: "Alert message when missing microphone access")
    }
}

