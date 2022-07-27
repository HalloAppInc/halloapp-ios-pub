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
import CoreCommon
import CoreData
import Photos
import SafariServices
import UIKit

fileprivate struct Constants {
    static let WidthOfMsgBubble:CGFloat = 0.8
}

protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ chatViewController: ChatViewController, userActioned: Bool)
    func chatViewController(_ chatViewController: ChatViewControllerNew, userActioned: Bool)
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
    private var chatEventFetchedResultsController: NSFetchedResultsController<ChatEvent>?
    private var callHistoryFetchedResultsController: NSFetchedResultsController<Core.Call>?
    private var dataSource: ChatDataSource?

    private var trackedChatMessages: [String: TrackedChatMessage] = [:]

    static private let sectionMain = 0
    static private let inboundMsgViewCellReuseIdentifier = "InboundMsgViewCell"
    static private let outboundMsgViewCellReuseIdentifier = "OutboundMsgViewCell"
    static private let chatEventViewCellReuseIdentifier = "ChatEventViewCell"
    static private let chatCallViewCellReuseIdentifier = "ChatCallViewCell"
    static private let chatDateMarkerCellReuseIdentifier = "ChatDateMarkerCell"

    private let waitForCellTimeout: TimeInterval = 0.25

    private var isHeaderSetup: Bool = false
    private var firstActionHappened: Bool = false

    private var currentUnseenChatThreadsList: [UserID: Int] = [:]
    private var currentUnseenGroupChatThreadsList: [GroupID: Int] = [:]

    private var cancellableSet: Set<AnyCancellable> = []
    
    private var transitionSnapshot: UIView?

    // MARK: Lifecycle

    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        DDLogDebug("ChatViewController/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId, in: contactsViewContext))]")
        self.fromUserId = fromUserId
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    // Should always be called on the main queue.
    private func checkAndUpdateCallButtons() {
        if let fromUserId = fromUserId,
           fromUserId != MainAppContext.shared.userData.userId,
           MainAppContext.shared.callManager.activeCallID == nil,
           MainAppContext.shared.contactStore.normalizedPhoneNumber(for: fromUserId, using: MainAppContext.shared.contactStore.viewContext) != nil {
            // Enable calls for contacts in address book
            // or
            // Enable calls for users whose pushNumber is known - meaning you received a message from them.
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
        } else {
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        }
    }

    override func viewDidLoad() {
        guard let fromUserId = fromUserId else { return }

        super.viewDidLoad()

        preventNavLoop()

        var rightBarButtons: [UIBarButtonItem] = []

        let phoneImage = UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        let phoneButton = UIBarButtonItem(image: phoneImage, style: .plain, target: self, action: #selector(audioCallButtonTapped))
        phoneButton.tintColor = .primaryBlue
        rightBarButtons.append(phoneButton)

        let videoImage = UIImage(systemName: "video.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        let videoButton = UIBarButtonItem(image: videoImage, style: .plain, target: self, action: #selector(videoCallButtonTapped))
        videoButton.tintColor = .primaryBlue
        rightBarButtons.append(videoButton)

        navigationItem.rightBarButtonItems = rightBarButtons
        checkAndUpdateCallButtons()

        let titleWidthConstraint = titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.8))
        titleWidthConstraint.priority = .defaultHigh // Lower priority to allow space for trailing button if necessary
        titleWidthConstraint.isActive = true

        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
        titleView.checkIfUnknownContactWithPushNumber(userID: fromUserId)
        
        view.addSubview(tableView)
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView.backgroundColor = .primaryBg
        tableView.rowHeight = UITableView.automaticDimension

        DispatchQueue.main.async { [weak self] in
            self?.setupOrRefreshHeaderAndFooter()
            self?.isHeaderSetup = true
            self?.scrollToBottomIfNecessary()
        }

        dataSource = ChatDataSource(tableView: tableView) { [weak self] (tableView, indexPath, row) in
            guard let self = self else { return UITableViewCell() }
            if indexPath.section == 0 {
                switch row {
                case .chatMsg(let chatMsgData):
                    guard let chatMessage = self.fetchedResultsController?.optionalObject(at: chatMsgData.indexPath) as? ChatMessage else { return UITableViewCell() }

                    self.trackedChatMessages[chatMessage.id] = TrackedChatMessage(with: chatMessage)

                    var isPreviousMsgSameSender = false
                    var isNextMsgSameSender = false
                    var isNextMsgSameTime = false

                    let previousRow = chatMsgData.indexPath.row - 1
                    let nextRow = chatMsgData.indexPath.row + 1

                    if previousRow >= 0 {
                        let previousIndexPath = IndexPath(row: previousRow, section: chatMsgData.indexPath.section)
                        if let previousChatMessage = self.fetchedResultsController?.optionalObject(at: previousIndexPath) as? ChatMessage {
                            if previousChatMessage.fromUserId == chatMessage.fromUserId {
                                isPreviousMsgSameSender = true
                            }
                        }
                    }

                    if nextRow < tableView.numberOfRows(inSection: 0) {
                        let nextIndexPath = IndexPath(row: nextRow, section: chatMsgData.indexPath.section)
     
                        if let nextChatMessage = self.fetchedResultsController?.optionalObject(at: nextIndexPath) as? ChatMessage {
                            if nextChatMessage.fromUserId == chatMessage.fromUserId {
                                isNextMsgSameSender = true
                                if nextChatMessage.timestamp?.chatTimestamp() == chatMessage.timestamp?.chatTimestamp() {
                                    isNextMsgSameTime = true
                                }
                            }
                        }
                    }

                   // TODO: refactor out/inbound cells and update params after ui stabilize

                    if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
                        if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.outboundMsgViewCellReuseIdentifier, for: indexPath) as? OutboundMsgViewCell {
                            cell.tableIndexPath = indexPath
                            cell.indexPath = chatMsgData.indexPath
                            cell.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)
                            cell.msgViewCellDelegate = self
                            cell.delegate = self
                            return cell
                        }
                    } else {
                        if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.inboundMsgViewCellReuseIdentifier, for: indexPath) as? InboundMsgViewCell {
                            cell.tableIndexPath = indexPath
                            cell.indexPath = chatMsgData.indexPath
                            cell.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)
                            cell.msgViewCellDelegate = self
                            cell.delegate = self
                            return cell
                        }
                    }
                case .chatEvent(let chatEventData):
                    guard let chatEvent = self.chatEventFetchedResultsController?.optionalObject(at: chatEventData.indexPath) as? ChatEvent else { break }

                    if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.chatEventViewCellReuseIdentifier, for: indexPath) as? ChatEventViewCell {
                        cell.configure(userID: chatEvent.userID)
                        return cell
                    }
                case .chatCall(let callData):
                    if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.chatCallViewCellReuseIdentifier, for: indexPath) as? ChatCallCell {
                        cell.configure(callData)
                        cell.delegate = self
                        return cell
                    }
                case .dateMarker(let date):
                    if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.chatDateMarkerCellReuseIdentifier, for: indexPath) as? ChatDateMarkerCell {
                        cell.configure(for: date)
                        return cell
                    }
                }
            }
            return UITableViewCell()
        }

        setupChatMessageFetchedResultsController()
        setupChatEventFetchedResultsController()
        setupCallHistoryFetchedResultsController()
        updateDataInMainQueue(animated: false)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        view.addGestureRecognizer(tapGesture)

        if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
                let contactsViewContext = MainAppContext.shared.contactStore.viewContext
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.rawText, mentions: feedPost.orderedMentions, in: contactsViewContext)
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }), let mediaType = CommonMediaType(rawValue: mediaItem.type.rawValue){
                    
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

        cancellableSet.insert(
            MainAppContext.shared.callManager.isAnyCallOngoing.sink { [weak self] call in
                guard let self = self else { return }
                // Disable call buttons when the user is in an active call.
                self.checkAndUpdateCallButtons()
            }
        )

        // Update name in title view if we just discovered this new user.
        cancellableSet.insert(
            MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] (newUserIDs) in
                DDLogInfo("ChatViewController/didDiscoverNewUsers/update name if necessary")
                guard let self = self else { return }
                guard let userID = self.fromUserId else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if newUserIDs.contains(userID) {
                        self.titleView.refreshName(for: userID)
                    }
                    if let headerView = self.tableView.tableHeaderView as? ChatHeaderView {
                        headerView.configureOrRefresh(with: userID)
                    }
                }
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
        
        scrollToBottomIfNecessary()
        removeTransitionSnapshot()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let chatWithUserId = self.fromUserId {
            MainAppContext.shared.chatData.markThreadAsRead(type: .oneToOne, for: chatWithUserId)
            MainAppContext.shared.chatData.updateUnreadChatsThreadCount()
            MainAppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)

            UNUserNotificationCenter.current().removeDeliveredChatNotifications(fromUserId: chatWithUserId)
        }
        
        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        keyWindow.addSubview(jumpButton)
        jumpButton.trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor).isActive = true
        jumpButtonConstraint = jumpButton.bottomAnchor.constraint(equalTo: keyWindow.bottomAnchor, constant: -100)
        jumpButtonConstraint?.isActive = true
        
        updateJumpButtonVisibility()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let id = fromUserId {
            saveChatDraft(id: id)
        }
        pauseVoiceNotes()
        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        
        jumpButton.removeFromSuperview()
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
    
    deinit {
        DDLogDebug("ChatViewController/deinit/\(fromUserId ?? "")")
        updateChatState()
    }

    private func updateChatState() {
        if let fromUserId = fromUserId {
            MainAppContext.shared.chatData.sendChatState(type: .oneToOne,
                                                           id: fromUserId,
                                                        state: .available)
        }
    }

    @objc private func audioCallButtonTapped() {
        callButtonTapped(type: .audio)
    }

    @objc private func videoCallButtonTapped() {
        callButtonTapped(type: .video)
    }

    private func callButtonTapped(type: CallType) {
        guard let peerUserID = fromUserId else {
            DDLogInfo("ChatViewController/callButtonTapped/peerUserID is empty")
            return
        }
        DDLogInfo("ChatViewController/callButtonTapped/type: \(type)/peerUserID: \(peerUserID)")
        startCallIfPossible(with: peerUserID, type: type)

        // Clear search if user called from this screen.
        if !firstActionHappened {
            delegate?.chatViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func startCallIfPossible(with peerUserID: UserID, type: CallType) {
        if peerUserID == MainAppContext.shared.userData.userId {
            DDLogInfo("ChatViewController/startCallIfPossible/cannot call oneself")
            return
        }
        guard MainAppContext.shared.service.isConnected else {
            DDLogInfo("ChatViewController/startCallIfPossible/service not connected")
            let alert = self.getFailedCallAlert()
            self.present(alert, animated: true)
            return
        }
        MainAppContext.shared.callManager.startCall(to: peerUserID, type: type) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    DDLogInfo("ChatViewController/startCall/success")
                case .failure:
                    DDLogInfo("ChatViewController/startCall/failure")
                    let alert = self.getFailedCallAlert()
                    self.present(alert, animated: true)
                }
            }
        }

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
        guard let nextChatMessage = fetchedResultsController?.optionalObject(at: nextIndexPath) as? ChatMessage else { return }
        guard nextChatMessage.media?.first?.type == .audio else { return }

        let chatMsgData = ChatMsgData(id: nextChatMessage.id, cellHeight: nextChatMessage.cellHeight, outgoingStatus: nextChatMessage.outgoingStatus, incomingStatus: nextChatMessage.incomingStatus, timestamp: nextChatMessage.timestamp, indexPath: nextIndexPath)
        guard let nextTableIndexPath = dataSource?.indexPath(for: Row.chatMsg(chatMsgData)) else { return }
        tableView.scrollToRow(at: nextTableIndexPath, at: .middle, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + waitForCellTimeout) {
            guard let cell = self.tableView.cellForRow(at: nextTableIndexPath) else { return }

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
    
    // MARK:

    private func shouldShowVerifyOption() -> Bool {
        guard let otherUserID = fromUserId,
              let otherKeyBundle = MainAppContext.shared.keyStore.messageKeyBundle(for: otherUserID, in: MainAppContext.shared.keyStore.viewContext)?.keyBundle,
              SafetyNumberData(keyBundle: otherKeyBundle) != nil
        else {
            // TODO: Allow user to verify without existing key bundle
            return false
        }

        return true
    }

    private func presentMediaExplorer(media: [CommonMedia], At index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: true, source: .chat)
        controller.animatorDelegate = delegate

        present(controller, animated: true)
    }

    private func presentMediaExplorer(quotedMedia: [CommonMedia], At index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        let controller = MediaExplorerController(media: quotedMedia, index: index, canSaveMedia: false, source: .post)
        controller.animatorDelegate = delegate

        present(controller, animated: true)
    }

    private func setupOrRefreshHeaderAndFooter() {
        guard let userID = fromUserId else { return }
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        let isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        let isUserInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: contactsViewContext)
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
            present(unknownContactSheet, animated: true)
        }

        var headerHeight: CGFloat = 90
        if isUserBlocked {
            headerHeight = 130
        }

        let chatHeaderView = ChatHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: headerHeight))
        chatHeaderView.configureOrRefresh(with: userID)
        chatHeaderView.delegate = self
        tableView.tableHeaderView = chatHeaderView
    }

    private lazy var titleView: ChatTitleView = {
        let titleView = ChatTitleView()
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
        tableView.register(ChatEventViewCell.self, forCellReuseIdentifier: ChatViewController.chatEventViewCellReuseIdentifier)
        tableView.register(ChatCallCell.self, forCellReuseIdentifier: ChatViewController.chatCallViewCellReuseIdentifier)
        tableView.register(ChatDateMarkerCell.self, forCellReuseIdentifier: ChatViewController.chatDateMarkerCellReuseIdentifier)
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
            let contactsViewContext = MainAppContext.shared.contactStore.viewContext
            let blockMessage = Localizations.blockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID, in: contactsViewContext))

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
        
        sheet.cancelAction = { [weak self] in
            self?.dismiss(animated: true)
            self?.navigationController?.popViewController(animated: true)
        }

        return sheet
    }()

    // MARK: Data

    private var shouldScrollToBottom = false
    private var shouldUpdate = false

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

    private func isRerequestStatusUpdate(for chatMessage: ChatMessage) -> Bool {
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return false }
        if trackedChatMessage.incomingStatus == .rerequesting &&
            chatMessage.incomingStatus != .rerequesting
        {
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

    private func findUpdatedMedia(for chatMessage: ChatMessage) -> CommonMedia? {
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

        switch controller {
        case fetchedResultsController:
            switch type {
            case .update:

                /* only update when it's needed (ie. msg retraction, successful rerequest) */
                shouldUpdate = false
                guard let chatMessage = anObject as? ChatMessage else { break }
                DDLogVerbose("ChatViewController/frc/msg/update \(chatMessage.id)")

                if isRetractStatusUpdate(for: chatMessage) {
                    DDLogDebug("ChatViewController/frc/msg/update/isRetractStatusUpdate \(chatMessage.id)")
                    shouldUpdate = true
                    break
                }

                if isRerequestStatusUpdate(for: chatMessage) {
                    DDLogDebug("ChatViewController/frc/msg/update/isRerequestStatusUpdate \(chatMessage.id)")
                    shouldUpdate = true
                    break
                }

                // outbound msg status change, update cell directly
                if isOutgoingMessageStatusUpdate(for: chatMessage) {
                    DDLogVerbose("ChatViewController/frc/msg/update/isOutgoingMessageStatusUpdate \(chatMessage.id)")
                    guard let indexPath = indexPath else { break }
                    
                    // frc chatMessage have already changed, use trackedMsg to find item in the datasource
                    guard let trackedMsg = trackedChatMessages[chatMessage.id] else { break }
                    let chatMsgData = ChatMsgData(id: chatMessage.id, cellHeight: Int16(trackedMsg.cellHeight), outgoingStatus: trackedMsg.outgoingStatus, incomingStatus: trackedMsg.incomingStatus, timestamp: trackedMsg.timestamp, indexPath: indexPath)
                    guard let tableIndexPath = dataSource?.indexPath(for: Row.chatMsg(chatMsgData)) else { break }
                    guard let cell = tableView.cellForRow(at: tableIndexPath) as? OutboundMsgViewCell else { break }
                    cell.updateText(chatMessage: chatMessage)
                    break
                }

                // inbound msg media changes, update cell directly
                if let updatedChatMedia = findUpdatedMedia(for: chatMessage) {
                    DDLogVerbose("ChatViewController/frc/msg/update/updatedChatMedia/\(chatMessage.id) update cell directly")
                    guard let indexPath = indexPath else { break }

                    // frc chatMessage have already changed, use trackedMsg to find item in the datasource
                    guard let trackedMsg = trackedChatMessages[chatMessage.id] else { break }
                    let chatMsgData = ChatMsgData(id: chatMessage.id, cellHeight: Int16(trackedMsg.cellHeight), outgoingStatus: trackedMsg.outgoingStatus, incomingStatus: trackedMsg.incomingStatus, timestamp: trackedMsg.timestamp, indexPath: indexPath)
                    guard let tableIndexPath = dataSource?.indexPath(for: Row.chatMsg(chatMsgData)) else { break }
                    guard let cell = tableView.cellForRow(at: tableIndexPath) as? InboundMsgViewCell else { break }
                    cell.updateMedia(updatedChatMedia)
                    break
                }
            case .insert:
                guard let chatMsg = anObject as? ChatMessage else { break }
                DDLogVerbose("ChatViewController/frc/msg/insert \(chatMsg.id)")
                shouldUpdate = true
                receivedNewItem = true
                if chatMsg.fromUserId != MainAppContext.shared.userData.userId {
                    incrementJumpButtonIfVisible()
                } else {
                    shouldScrollToBottom = true
                }
            case .delete:
                shouldUpdate = true
            default:
                break
            }
        case chatEventFetchedResultsController:
            switch type {
            case .insert:
                DDLogVerbose("ChatViewController/frc/event/insert")
                guard let event = anObject as? ChatEvent else { break }
                shouldUpdate = true
                receivedNewItem = true
                if event.userID != MainAppContext.shared.userData.userId {
                    incrementJumpButtonIfVisible()
                }
            default:
                break
            }
        case callHistoryFetchedResultsController:
            DDLogVerbose("ChatViewController/frc/call/event/\(type)")
            switch type {
            case .insert:
                guard let call = anObject as? Core.Call else { break }
                shouldUpdate = true
                receivedNewItem = true
                if call.direction == .incoming {
                    incrementJumpButtonIfVisible()
                }

            case .move, .update, .delete:
                break
            @unknown default:
                break
            }
        default:
            break
        }

    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard shouldUpdate else {
            DDLogVerbose("ChatViewController/frc/update/skip whole cell update")
            return
        }

        updateData(animatingDifferences: false)
    }

    private func updateData(animatingDifferences: Bool) {
        DispatchQueue.main.async {
            self.updateDataInMainQueue(animated: animatingDifferences)
        }
    }

    // room for improvement: instead of building out the entire snapshot each time for initial load and updates,
    // updates can be in a separate function that use the pre-existing snapshot and update the changed items only
    private func updateDataInMainQueue(animated: Bool = false) {
        guard let chatMessages = fetchedResultsController?.fetchedObjects else { return }
        guard let chatEvents = chatEventFetchedResultsController?.fetchedObjects else { return }
        guard let calls = callHistoryFetchedResultsController?.fetchedObjects else { return }

        var chatRows = [Row]()

        // Add messages
        chatMessages.forEach { msg in
            if let indexPath = fetchedResultsController?.indexPath(forObject: msg) {
                let chatMsgData = ChatMsgData(id: msg.id, cellHeight: msg.cellHeight, outgoingStatus: msg.outgoingStatus, incomingStatus: msg.incomingStatus, timestamp: msg.timestamp, indexPath: indexPath)
                chatRows.append(Row.chatMsg(chatMsgData))
            }
        }

        // Add key change events
        chatEvents.forEach { event in
            if let indexPath = chatEventFetchedResultsController?.indexPath(forObject: event) {
                let chatEventData = ChatEventData(timestamp: event.timestamp, indexPath: indexPath)
                chatRows.append(Row.chatEvent(chatEventData))
            }
        }

        // Add calls
        chatRows += calls
            .map { ChatCallData(userID: $0.peerUserID, timestamp: $0.timestamp, duration: $0.durationMs / 1000, wasSuccessful: $0.answered, wasIncoming: $0.direction == .incoming, type: $0.type) }
            .map { Row.chatCall($0) }

        // Sort by date
        chatRows = chatRows.sorted {
            ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture)
        }

        // Add date markers
        var rowIndex = 0
        var previousDate = Date.distantPast
        while rowIndex < chatRows.count {
            guard let currentDate = chatRows[rowIndex].timestamp else {
                rowIndex += 1
                continue
            }
            if Calendar.current.isDate(currentDate, inSameDayAs: previousDate) {
                rowIndex += 1
            } else {
                chatRows.insert(.dateMarker(currentDate), at: rowIndex)
                rowIndex += 2
            }
            previousDate = currentDate
        }

        /* apply snapshot */
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()

        snapshot.appendSections([ .chats ])
        snapshot.appendItems(chatRows, toSection: .chats)

        dataSource?.defaultRowAnimation = .fade

        dataSource?.apply(snapshot, animatingDifferences: animated) { [weak self] in
            // Need to dispatch this call to get the right offset after sending a message
            DispatchQueue.main.async {
                self?.scrollToBottomIfNecessary()
            }
        }
    }

    // MARK: Helpers

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
                DDLogInfo("ChatViewController/saveAllMediaInMessage: User denied photos permissions")
                
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
            DDLogError("ChatViewController/saveAllMediaInMessage/error: \(error)")
            
            Task { @MainActor in
                let alert = UIAlertController(title: nil, message: Localizations.mediaSaveError, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                present(alert, animated: true)
            }
        }
    }
    
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

    private var needsInitialScrollToBottom = true
    private var receivedNewItem = false

    private func incrementJumpButtonIfVisible() {
        guard !jumpButton.isHidden else { return }
        jumpButtonUnreadCount += 1
        jumpButtonUnreadCountLabel.text = String(jumpButtonUnreadCount)
    }

    private func scrollToBottomIfNecessary() {
        guard isHeaderSetup else {
            // NB: Header gets added asynchronously.
            // Wait for it before performing initial scroll.
            return
        }
        if needsInitialScrollToBottom {
            scrollToBottom(false)
        } else if receivedNewItem && jumpButton.isHidden {
            scrollToBottom(true)
        } else if receivedNewItem, (jumpButton.isHidden || shouldScrollToBottom) {
            scrollToBottom(true)
        }
        receivedNewItem = false
        needsInitialScrollToBottom = false
        shouldScrollToBottom = false
    }

    private func scrollToBottom(_ animated: Bool = true) {
        guard let dataSnapshot = dataSource?.snapshot() else { return }
        let numberOfRows = dataSnapshot.numberOfItems(inSection: Section.chats)
        guard numberOfRows > 0 else { return }
        let indexPath = IndexPath(row: numberOfRows - 1, section: ChatViewController.sectionMain)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
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
        let fromTheBottom = UIScreen.main.bounds.height * 1.5 - tableView.contentInset.bottom

        if tableView.contentSize.height - tableView.contentOffset.y > fromTheBottom {
            let aboveAccessoryView = tableView.contentInset.bottom + 50
            jumpButtonConstraint?.constant = -aboveAccessoryView
            jumpButton.isHidden = false
        } else {
            jumpButton.isHidden = true
            jumpButtonUnreadCount = 0
            jumpButtonUnreadCountLabel.text = nil
        }
    }

    private func jumpToMsg(tableIndexPath: IndexPath, indexPath: IndexPath) {
        guard let message = fetchedResultsController?.object(at: indexPath) else { return }

        if let feedPostId = message.feedPostId {
            guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext, archived: true) else {
                DDLogWarn("ChatViewController/Quoted feed post \(feedPostId) not found")
                return
            }

            let vc = feedPost.isMoment ? MomentViewController(post: feedPost, shouldFetchOtherMoments: false) : PostViewController.viewController(for: feedPost)
            present(vc, animated: true)
        } else  if let chatReplyMessageID = message.chatReplyMessageID {
            guard let allMessages = fetchedResultsController?.fetchedObjects else { return }
            guard let replyMessage = allMessages.first(where: {$0.id == chatReplyMessageID}) else { return }

            guard let replyMsgIndexPath = fetchedResultsController?.indexPath(forObject: replyMessage) else { return }
            let chatMsgData = ChatMsgData(id: replyMessage.id, cellHeight: replyMessage.cellHeight, outgoingStatus: replyMessage.outgoingStatus, incomingStatus: replyMessage.incomingStatus, timestamp: replyMessage.timestamp, indexPath: replyMsgIndexPath)
            guard let toIndexPath = dataSource?.indexPath(for: Row.chatMsg(chatMsgData)) else { return }
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
    }

    // MARK: Actions

    @IBAction func jumpDown(_ sender: Any?) {
        scrollToBottom(true)
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

        contentInputView.reset()
        removeChatDraft()

        if !firstActionHappened {
            delegate?.chatViewController(self, userActioned: true)
            firstActionHappened = true
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
            delegate?.chatViewController(self, userActioned: true)
            firstActionHappened = true
        }
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

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        contentInputView.textView.resignFirstResponder()
    }
}

// MARK: Chat Message FetchedResults
fileprivate extension ChatViewController {

    // room for improvements: fetchedcontrollers can be made more performant by fetching by offset instead of the entire table,
    // but will require additional support for scrolling to the top, jumping to a message not fetched, and future search feature for a
    // message not yet fetched
    private func setupChatMessageFetchedResultsController() {
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        guard let userID = fromUserId else { return }
        let appUserID = MainAppContext.shared.userData.userId
        fetchRequest.predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ && fromUserID = %@)", userID, appUserID, userID, appUserID)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true) // if timestamps are the same, break tie
        ]

        fetchedResultsController = NSFetchedResultsController<ChatMessage>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController?.delegate = self
        do {
            try fetchedResultsController!.performFetch()
        } catch {
            return
        }
    }

}

// MARK: Chat Event FetchedResults
fileprivate extension ChatViewController {

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
            try chatEventFetchedResultsController!.performFetch()
        } catch {
            return
        }
    }

}

// MARK: Call History FetchedResults
fileprivate extension ChatViewController {

    private func setupCallHistoryFetchedResultsController() {
        guard let userID = fromUserId else { return }
        let fetchRequest: NSFetchRequest<Core.Call> = Core.Call.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "peerUserID == %@ && endReasonValue != %d", userID, EndCallReason.unknown.rawValue)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Core.Call.timestamp, ascending: true)
        ]

        callHistoryFetchedResultsController = NSFetchedResultsController<Core.Call>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        callHistoryFetchedResultsController?.delegate = self
        do {
            try callHistoryFetchedResultsController!.performFetch()
        } catch {
            return
        }
    }

}

fileprivate class ChatDataSource: UITableViewDiffableDataSource<Section, Row> {
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

fileprivate enum Section: Hashable {
    case chats
}

fileprivate enum Row: Hashable, Equatable {
    case chatCall(ChatCallData)
    case chatMsg(ChatMsgData)
    case chatEvent(ChatEventData)
    case dateMarker(Date)

    var timestamp: Date? {
        switch self {
        case .chatMsg(let data):
            return data.timestamp
        case .chatEvent(let data):
            return data.timestamp
        case .chatCall(let data):
            return data.timestamp
        case .dateMarker(let date):
            return date
        }
    }
}

fileprivate struct ChatMsgData {
    let id: String
    let cellHeight: Int16
    let outgoingStatus: ChatMessage.OutgoingStatus
    let incomingStatus: ChatMessage.IncomingStatus
    let timestamp: Date?
    let indexPath: IndexPath
}

extension ChatMsgData : Hashable {

    /* hash must be the same if structs are equal (equatable) */
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(indexPath)
        if [.retracting, .retracted].contains(outgoingStatus) {
            hasher.combine(outgoingStatus)
        }
        if [.retracted, .rerequesting].contains(incomingStatus) {
            hasher.combine(incomingStatus)
        }
    }
}

extension ChatMsgData : Equatable {

    /* only update cell when it's retracted or rerequested successfully */
    static func == (lhs: Self, rhs: Self) -> Bool {

        var isOutboundMsgRetracted = false
        if lhs.outgoingStatus != rhs.outgoingStatus {
            isOutboundMsgRetracted = [.retracting, .retracted].contains(rhs.outgoingStatus)
        }

        var isInboundMsgRetracted = false
        var isInboundMsgRerequestedSuccessfully = false
        if lhs.incomingStatus != rhs.incomingStatus {
            if rhs.incomingStatus == .retracted {
                isInboundMsgRetracted = true
            }
            if lhs.incomingStatus == .rerequesting {
                isInboundMsgRerequestedSuccessfully = true
            }
        }

        let isOutboundStatusChange = isOutboundMsgRetracted
        let isInboundStatusChange = isInboundMsgRetracted || isInboundMsgRerequestedSuccessfully

        let isEqual = lhs.id == rhs.id &&
                      lhs.indexPath == rhs.indexPath &&
                      !isOutboundStatusChange &&
                      !isInboundStatusChange

        return isEqual
    }
}

fileprivate struct ChatEventData {
    let timestamp: Date?
    let indexPath: IndexPath
}

struct ChatCallData: Hashable {
    var userID: UserID
    var timestamp: Date?
    var duration: TimeInterval
    var wasSuccessful: Bool
    var wasIncoming: Bool
    var type: CallType
}

extension ChatEventData : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(indexPath)
    }
}

extension ChatEventData : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.indexPath == rhs.indexPath
    }
}

fileprivate struct TrackedChatMedia {
    var relativeFilePath: String?
    let order: Int

    init(with chatMedia: CommonMedia) {
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
    let timestamp: Date?

    init(with chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.cellHeight = Int(chatMessage.cellHeight)
        self.outgoingStatus = chatMessage.outgoingStatus
        self.incomingStatus = chatMessage.incomingStatus
        self.timestamp = chatMessage.timestamp

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

// MARK: ChatHeader Delegates
extension ChatViewController: ChatHeaderViewDelegate {

    func chatHeaderViewOpenEncryptionBlog(_ chatHeaderView: ChatHeaderView) {
        let viewController = SFSafariViewController(url: URL(string: "https://halloapp.com/blog/encrypted-chat")!)
        present(viewController, animated: true)
    }

    func chatHeaderViewUnblockContact(_ chatHeaderView: ChatHeaderView) {
        guard let userID = fromUserId else { return }

        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        let unBlockMessage = Localizations.unBlockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID, in: contactsViewContext))

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

// MARK: CNContact Delegates
extension ChatViewController: CNContactViewControllerDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        navigationController?.popViewController(animated: true)
        
        if contact == nil {
            // need to display the unknown contact sheet again
            setupOrRefreshHeaderAndFooter()
        }
    }
}

// MARK: PostComposerView Delegates
extension ChatViewController: PostComposerViewDelegate {
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

// MARK: UITableview Delegates
extension ChatViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let dataSourceItem = dataSource?.itemIdentifier(for: indexPath) else { return }

        switch dataSourceItem {
        case .chatMsg(let chatMsgData):
            guard let chatMessage = fetchedResultsController?.optionalObject(at: chatMsgData.indexPath) as? ChatMessage else { return }
            let height = Int(cell.bounds.height)
            guard chatMessage.cellHeight != height else { return }
            DDLogVerbose("ChatViewController/willDisplay/updateCellHeight/\(chatMessage.id) from \(chatMessage.cellHeight) to \(height)")
            MainAppContext.shared.chatData.updateChatMessageCellHeight(for: chatMessage.id, with: height)
        case .chatEvent, .chatCall, .dateMarker: break
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let defaultHeight:CGFloat = 50
        guard let dataSourceItem = dataSource?.itemIdentifier(for: indexPath) else { return defaultHeight }

        switch dataSourceItem {
        case .chatMsg(let chatMsgData):
            guard let chatMessage = fetchedResultsController?.optionalObject(at: chatMsgData.indexPath) else { break }
            guard chatMessage.cellHeight != 0 else { break }
            return CGFloat(chatMessage.cellHeight)
        case .chatEvent, .chatCall, .dateMarker:
            break
        }

        return defaultHeight
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
}

// MARK: ChatTitle Delegates
extension ChatViewController: ChatTitleViewDelegate {
    func chatTitleView(_ chatTitleView: ChatTitleView) {
        guard let userId = fromUserId else { return }
        let userViewController = UserFeedViewController(userId: userId)
        navigationController?.pushViewController(userViewController, animated: true)
    }
}

// MARK: InboundMsgViewCell Delegates
extension ChatViewController: InboundMsgViewCellDelegate {

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell) {
        guard let tableIndexPath = inboundMsgViewCell.tableIndexPath else { return }
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        jumpToMsg(tableIndexPath: tableIndexPath, indexPath: indexPath)
    }
    
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewMediaAt index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        guard message.media != nil else { return }

        presentMediaExplorer(media: message.orderedMedia, At: index, withDelegate: delegate)
    }

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewQuotedMediaAt index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        guard let quoted = message.quoted else { return }
        guard quoted.media != nil else { return }

        presentMediaExplorer(quotedMedia: quoted.orderedMedia, At: index, withDelegate: delegate)
    }

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didLongPressOn msgId: String) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        
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
                self.handleQuotedReply(msg: chatMessage, mediaIndex: inboundMsgViewCell.mediaIndex)
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

    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didCompleteVoiceNote msgId: String) {
        guard let indexPath = inboundMsgViewCell.indexPath else { return }
        playVoiceNote(after: indexPath)
    }
    
}

// MARK: OutboundMsgViewCell Delegates
extension ChatViewController: OutboundMsgViewCellDelegate {

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell) {
        guard let tableIndexPath = outboundMsgViewCell.tableIndexPath else { return }
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        jumpToMsg(tableIndexPath: tableIndexPath, indexPath: indexPath)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewMediaAt index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        guard message.media != nil else { return }

        presentMediaExplorer(media: message.orderedMedia, At: index, withDelegate: delegate)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewQuotedMediaAt index: Int, withDelegate delegate: MediaListAnimatorDelegate) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let message = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        guard let quoted = message.quoted else { return }
        guard quoted.media != nil else { return }

        presentMediaExplorer(quotedMedia: quoted.orderedMedia, At: index, withDelegate: delegate)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didLongPressOn msgId: String) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if ![.retracting, .retracted].contains(chatMessage.outgoingStatus) {
            if let media = chatMessage.media, !media.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.saveAllButton, style: .default) { _ in
                    Task { [weak self] in
                        await self?.saveAllMedia(in: chatMessage)
                    }
                })
            }
            
            actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.handleQuotedReply(msg: chatMessage, mediaIndex: outboundMsgViewCell.mediaIndex)
             })
            
            if let messageText = chatMessage.rawText, !messageText.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = messageText
                 })
            }
        }

        actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
            self?.showDeletionConfirmationMenu(for: chatMessage)
        })

        guard actionSheet.actions.count > 0 else { return }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        
        self.present(actionSheet, animated: true)
    }

    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didCompleteVoiceNote msgId: String) {
        guard let indexPath = outboundMsgViewCell.indexPath else { return }
        playVoiceNote(after: indexPath)
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
    
}

// MARK: MsgView Delegates
extension ChatViewController: MsgViewCellDelegate {

    func msgViewCell(_ msgViewCell: MsgViewCell, replyTo msgId: String) {
        guard let tableIndexPath = msgViewCell.tableIndexPath else { return }
        guard let indexPath = msgViewCell.indexPath else { return }
        guard let chatMessage = fetchedResultsController?.optionalObject(at: indexPath) as? ChatMessage else { return }
        guard chatMessage.incomingStatus != .retracted else { return }
        guard ![.retracting, .retracted].contains(chatMessage.outgoingStatus) else { return }

        if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
            guard let cell = tableView.cellForRow(at: tableIndexPath) as? OutboundMsgViewCell else { return }
            handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
        } else {
            guard let cell = tableView.cellForRow(at: tableIndexPath) as? InboundMsgViewCell else { return }
            handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
        }
    }

}

// MARK: ChatCallView Delegates
extension ChatViewController: ChatCallViewDelegate {
    func chatCallView(_ callView: ChatCallView, didTapCallButtonWithData callData: ChatCallData) {
        startCallIfPossible(with: callData.userID, type: callData.type)
    }
}

// MARK: - content input view delegate methods

extension ChatViewController: ContentInputDelegate {
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
        
        let newInsets = UIEdgeInsets(top: tableView.contentInset.top,
                                    left: 0,
                                  bottom: (height - view.safeAreaInsets.bottom) + 10,
                                   right: 0)
        
        var newOffset = tableView.contentOffset
        newOffset.y += newInsets.bottom - tableView.contentInset.bottom
        
        if tableView.contentInset.bottom != 0, tableView.contentInset != newInsets {
            // not having the second condition causes inertial scrolling to break
            tableView.setContentOffset(newOffset, animated: false)
        }
        
        tableView.contentInset = newInsets
        tableView.scrollIndicatorInsets = newInsets
        
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

fileprivate extension NSFetchedResultsController {
    @objc func optionalObject(at indexPath: IndexPath) -> AnyObject? {
        guard let sections = sections, sections.count > indexPath.section else { return nil }
        let sectionInfo = sections[indexPath.section]
        guard sectionInfo.numberOfObjects > indexPath.row else { return nil }
        return object(at: indexPath)
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
            stackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
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

        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        quoteFeedPanelNameLabel.text = MainAppContext.shared.contactStore.fullName(for: postInfo.userID, in: contactsViewContext)
        let ham = HAMarkdown(font: UIFont.preferredFont(forTextStyle: .subheadline), color: UIColor.secondaryLabel)
        quoteFeedPanelTextLabel.attributedText = ham.parse(postInfo.text)
        
        if postInfo.userID == MainAppContext.shared.userData.userId {
            quoteFeedPanelNameLabel.textColor = .chatOwnMsg
        } else {
            quoteFeedPanelNameLabel.textColor = .label
        }
        
        subviews.first?.backgroundColor = quoteFeedPanelNameLabel.textColor.withAlphaComponent(0.1)
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
        
        stack.layer.cornerRadius = 15
        stack.clipsToBounds = true
        
        return stack
    }()
    
    private lazy var quoteFeedPanelTextMediaContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelTextContent, quoteFeedPanelImage ])
        view.axis = .horizontal
        view.alignment = .top
        view.spacing = 3
        
        view.layoutMargins = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 8)
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
        label.font = UIFont.preferredFont(forTextStyle: .headline)
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
        
        imageView.layer.cornerRadius = 5
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
}
