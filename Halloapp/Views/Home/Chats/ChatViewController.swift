//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Photos
import UIKit

fileprivate struct Constants {
    static let WidthOfMsgBubble:CGFloat = 0.8
}

fileprivate class ChatDataSource: UITableViewDiffableDataSource<Int, ChatMessage> {
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

class ChatViewController: UIViewController, NSFetchedResultsControllerDelegate {
    
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
    
    private var currentUnseenChatThreadsList: [UserID: Int] = [:]
    private var currentUnseenGroupChatThreadsList: [GroupID: Int] = [:]
    
    private var cancellableSet: Set<AnyCancellable> = []

    private var mediaPickerController: MediaPickerViewController?

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
        navAppearance.backgroundColor = UIColor.feedBackground
        navAppearance.shadowColor = nil
        navAppearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance

        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (self.view.frame.width*0.8))
        ])
        
        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        titleView.update(with: fromUserId, status: UserPresenceType.none, lastSeen: nil)
        
        view.addSubview(tableView)
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        tableView.backgroundColor = UIColor.feedBackground
        tableView.tableHeaderView = nil
        tableView.tableFooterView = nil
        
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
            updateData(animatingDifferences: false)
            
        } catch {
            return
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        view.addGestureRecognizer(tapGesture)
        
        if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                let mentionText = MainAppContext.shared.contactStore.textWithMentions(feedPost.text, orderedMentions: feedPost.orderedMentions)
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

        configureTitleViewWithTypingIndicator()

        guard let thread = MainAppContext.shared.chatData.chatThread(type: .oneToOne, id: fromUserId) else { return }
        guard thread.draft != "", let draft = thread.draft else { return }
        chatInputView.setDraftText(text: draft)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        chatInputView.willAppear(in: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.tableView.tableHeaderView = nil
        self.tableView.tableFooterView = nil
        let scrollPoint = CGPoint(x: 0, y: self.tableView.contentSize.height + 1000)
        self.tableView.setContentOffset(scrollPoint, animated: false)
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
            MainAppContext.shared.chatData.saveDraft(type: .oneToOne, for: id, with: chatInputView.text)
        }
        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        chatInputView.willDisappear(in: self)
        
        jumpButton.removeFromSuperview()
        
        navigationController?.navigationBar.backItem?.backBarButtonItem = UIBarButtonItem()
    }
    
    deinit {
        DDLogDebug("ChatViewController/deinit/\(fromUserId ?? "")")
    }
    
    private func updateBackButtonUnreadCount(num: Int) {
        let backButton = UIBarButtonItem()
        backButton.title = num > 0 ? String(num) : " \u{00a0}"

        navigationController?.navigationBar.backItem?.backBarButtonItem = backButton
    }
    
    // MARK:

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
    
    // MARK: Data

    private var shouldScrollToBottom = true
    private var skipDataUpdate = false
    
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
    
    private func updateCellMedia(for cell: InboundMsgViewCell, with med: ChatMedia) {
        guard let relativeFilePath = med.relativeFilePath else { return }
        var img: UIImage?
        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
        
        if med.type == .image {
            if let image = UIImage(contentsOfFile: fileURL.path) {
                img = image
            }
        } else if med.type == .video {
            if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
                img = image
            }
        }
        cell.updateMedia(SliderMedia(image: img, type: med.type, order: Int(med.order)))
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
                    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
        case .update:
            DDLogDebug("ChatViewController/frc/update")
            self.skipDataUpdate = true
            guard let chatMessage = anObject as? ChatMessage else { break }
            
            if isRetractStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/inboundMessageStatusChange")
                self.skipDataUpdate = false
            }
            
            if isOutgoingMessageStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/outgoingMessageStatusChange")
                self.skipDataUpdate = false
            }

            if isRerequestStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/rerequestStatusUpdate")
                self.skipDataUpdate = false
            }
            
            // inbound message media changes, update directly
            if let updatedChatMedia = findUpdatedMedia(for: chatMessage) {
                guard let cell = self.tableView.cellForRow(at: indexPath!) as? InboundMsgViewCell else { break }
                DDLogDebug("ChatViewController/frc/update-cell-directly/updatedMedia")
                self.updateCellMedia(for: cell, with: updatedChatMedia)
            }
        case .insert:
            DDLogDebug("ChatViewController/frc/insert")
            guard let chatMsg = anObject as? ChatMessage else { break }
            shouldScrollToBottom = checkIfShouldScrollToBottom(chatMsg)
        case .move:
            DDLogDebug("ChatViewController/frc/move")
        case .delete:
            DDLogDebug("ChatViewController/frc/delete")
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        if skipDataUpdate {
            DDLogDebug("ChatViewController/frc/update/skipDataUpdate")
            skipDataUpdate = false
            return
        }
        
        updateData(animatingDifferences: false)
        
        if shouldScrollToBottom {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.scrollToBottom(true)
            }
            shouldScrollToBottom = false
        }
    }

    func updateData(animatingDifferences: Bool = true) {
        guard let chatMessages = self.fetchedResultsController?.fetchedObjects else { return}

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, ChatMessage>()
        diffableDataSourceSnapshot.appendSections([ ChatViewController.sectionMain ])
        diffableDataSourceSnapshot.appendItems(chatMessages)
        self.dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences)
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
        if let dataSnapshot = self.dataSource?.snapshot() {
            let numberOfRows = dataSnapshot.numberOfItems(inSection: ChatViewController.sectionMain)
            let indexPath = IndexPath(row: numberOfRows - 1, section: ChatViewController.sectionMain)
            self.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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

    func sendMessage(text: String, media: [PendingMedia]) {
        guard let sendToUserId = self.fromUserId else { return }
        
        MainAppContext.shared.chatData.sendMessage(toUserId: sendToUserId,
                                                   text: text,
                                                   media: media,
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
    }
    
    private func presentMediaPicker() {
        guard mediaPickerController == nil else { return }

        mediaPickerController = MediaPickerViewController(camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }

            if cancel {
                self.dismissMediaPicker(animated: true)
            } else {
                self.presentMediaComposer(pickerController: controller, media: media)
            }
        }

        present(UINavigationController(rootViewController: mediaPickerController!), animated: true)
    }

    private func dismissMediaPicker(animated: Bool) {
        if mediaPickerController != nil {
            dismiss(animated: animated)
        }
        mediaPickerController = nil
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

// MARK: PostComposerView Delegates
extension ChatViewController: PostComposerViewDelegate {
    func composerDidTapShare(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia]) {
        sendMessage(text: mentionText.trimmed().collapsedText, media: media)
        controller.dismiss(animated: false)
        dismissMediaPicker(animated: false)
    }

    func composerDidTapBack(controller: PostComposerViewController, media: [PendingMedia]) {
        controller.dismiss(animated: false)
        mediaPickerController?.reset(selected: media)
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        chatInputView.text = mentionInput.text
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
    
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatMessage = self.fetchedResultsController?.object(at: indexPath) else {
            return UISwipeActionsConfiguration(actions: [])
        }
        guard chatMessage.incomingStatus != .retracted else { return nil }
        guard ![.retracting, .retracted].contains(chatMessage.outgoingStatus) else { return nil }
        
        let action = UIContextualAction(style: .normal, title: Localizations.messageReply) { [weak self] (action, view, completionHandler) in
            
            if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
                guard let cell = tableView.cellForRow(at: indexPath) as? OutboundMsgViewCell else { return }
                self?.handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
            } else {
                guard let cell = tableView.cellForRow(at: indexPath) as? InboundMsgViewCell else { return }
                self?.handleQuotedReply(msg: chatMessage, mediaIndex: cell.mediaIndex)
            }
            
            completionHandler(true)
        }
        
        action.backgroundColor = .systemBlue
        
        let configuration = UISwipeActionsConfiguration(actions: [action])

        return configuration
    }
    
    private func handleQuotedReply(msg chatMessage: ChatMessage, mediaIndex: Int) {
        chatReplyMessageID = chatMessage.id
        chatReplyMessageSenderID = chatMessage.fromUserId
        chatReplyMessageMediaIndex = Int32(mediaIndex)
        
        guard let userID = chatReplyMessageSenderID else { return }
        
        if let mediaItem = chatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
            let mediaType: ChatMessageMediaType = mediaItem.type == .video ? .video : .image
            let mediaUrl = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
            
            chatInputView.showQuoteFeedPanel(with: userID, text: chatMessage.text ?? "", mediaType: mediaType, mediaUrl: mediaUrl, from: self)
        } else {
            chatInputView.showQuoteFeedPanel(with: userID, text: chatMessage.text ?? "", mediaType: nil, mediaUrl: nil, from: self)
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
                actionSheet.message = MainAppContext.shared.cryptoData.details(for: chatMessage.id)
            }
        }
        
        guard actionSheet.actions.count > 0 else { return }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        
        self.present(actionSheet, animated: true)
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
        
        if [.sentOut, .delivered, .seen].contains(chatMessage.outgoingStatus) {
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
}

// MARK: ChatInputView Delegates
extension ChatViewController: ChatInputViewDelegate {
    
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
    
    func chatInputView(_ inputView: ChatInputView) {
        presentMediaPicker()
    }
    
    func chatInputView(_ inputView: ChatInputView, mentionText: MentionText) {
        let text = mentionText.trimmed().collapsedText
        sendMessage(text: text, media: [])
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
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: fromUserId)
        
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
            lastSeenLabel.text = "online"
        default:
            lastSeenLabel.isHidden = true
            lastSeenLabel.text = ""
        }

        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
    }
    
    func showChatState(with typingIndicatorStr: String?) {
        let showTyping: Bool = typingIndicatorStr != nil
        
        lastSeenLabel.isHidden = showTyping
        typingLabel.isHidden = !showTyping
        isShowingTypingIndicator = showTyping
        
        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
        
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
