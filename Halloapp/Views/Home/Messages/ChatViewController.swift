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
    static let WidthOfMsgBubble:CGFloat = 0.9
}

extension ChatViewController: MessageComposerViewDelegate {
    func messageComposerView(_ messageComposerView: MessageComposerView, text: String, media: [PendingMedia]) {
        self.sendMessage(text: text, media: media)
    }
}

class ChatViewController: UIViewController, UITableViewDelegate, ChatInputViewDelegate, NSFetchedResultsControllerDelegate {
    
    private var fromUserId: String?
    private var feedPostId: FeedPostID?
    private var feedPostMediaIndex: Int32 = 0
    
    private var fetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var dataSource: UITableViewDiffableDataSource<Int, ChatMessage>?
    
    private var trackedChatMessages: [String: TrackedChatMessage] = [:]

    static private let sectionMain = 0
    static private let incomingMsgCellReuseIdentifier = "IncomingMsgCell"
    static private let outgoingMsgCellReuseIdentifier = "OutgoingMsgCell"
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    // MARK: Lifecycle
    
    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        DDLogDebug("ChatViewController/init/\(fromUserId) [\(AppContext.shared.contactStore.fullName(for: fromUserId))]")
        self.fromUserId = fromUserId
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        guard let fromUserId = fromUserId else { return }

        super.viewDidLoad()
        
        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = UIColor.feedBackground
        appearance.shadowColor = .clear
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        
        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (self.view.frame.width*0.7))
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
        
        dataSource = UITableViewDiffableDataSource<Int, ChatMessage>(tableView: tableView) { [weak self] tableView, indexPath, chatMessage in
            guard let self = self else { return nil }
            
            self.trackedChatMessages[chatMessage.id] = TrackedChatMessage(with: chatMessage)
            
            var isPreviousMsgSameSender = false
            var isNextMsgSameSender = false
            var isNextMsgSameTime = false
            
            let previousRow = indexPath.row - 1
            let nextRow = indexPath.row + 1

            if previousRow >= 0 {
                let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)

                if let previousChatMessage = self.fetchedResultsController?.object(at: previousIndexPath) {
                    if previousChatMessage.fromUserId == chatMessage.fromUserId {
                        isPreviousMsgSameSender = true
                    }
                }
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
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.outgoingMsgCellReuseIdentifier, for: indexPath) as? OutgoingMsgCell {

                    cell.update(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)

                    if (chatMessage.media != nil) || (chatMessage.quoted != nil && chatMessage.quoted?.media != nil) {
                        cell.previewAction = { [weak self] previewType, mediaIndex in
                            guard let self = self else { return }
                            self.showPreviewView(previewType: previewType, media: chatMessage.orderedMedia, quotedMedia: chatMessage.quoted?.orderedMedia, mediaIndex: mediaIndex)
                        }
                    }
                    
                    return cell
                }
            } else {

                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.incomingMsgCellReuseIdentifier, for: indexPath) as? IncomingMsgCell {

                    cell.update(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)

                    if (chatMessage.media != nil) || (chatMessage.quoted != nil && chatMessage.quoted?.media != nil) {
                        cell.previewAction = { [weak self] previewType, mediaIndex in
                            guard let self = self else { return }
                            self.showPreviewView(previewType: previewType, media: chatMessage.orderedMedia, quotedMedia: chatMessage.quoted?.orderedMedia, mediaIndex: mediaIndex)
                        }
                    }

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
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: mediaItem.type, mediaUrl: mediaItem.relativeFilePath, from: self)
                } else {
                    chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: nil, mediaUrl: nil, from: self)
                }
            }
        }
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] status, ts in
                DDLogInfo("ChatViewController/didGetCurrentChatPresence")
                guard let self = self else { return }
                guard let userId = self.fromUserId else { return }
                self.titleView.update(with: userId, status: status, lastSeen: ts)
            }
        )

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
            MainAppContext.shared.chatData.updateUnreadThreadCount()
            MainAppContext.shared.chatData.updateUnreadMessageCount()
            MainAppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)
        }
        self.chatInputView.didAppear(in: self)
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(forType: .chatMessage, fromId: self.fromUserId!)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let id = fromUserId {
            MainAppContext.shared.chatData.saveDraft(type: .oneToOne, for: id, with: chatInputView.text)
        }
        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        chatInputView.willDisappear(in: self)
    }
    
    deinit {
        DDLogDebug("ChatViewController/deinit/\(fromUserId ?? "")")
    }
    
    // MARK:
    
    private func showPreviewView(previewType: MediaPreviewController.PreviewType, media: [ChatMedia]?, quotedMedia: [ChatQuotedMedia]?, mediaIndex: Int) {
        let detailVC = MediaPreviewController(previewType: previewType, media: media, quotedMedia:quotedMedia, mediaIndex: mediaIndex)
        let navigationController = UINavigationController(rootViewController: detailVC)
        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.modalTransitionStyle = .crossDissolve
        self.present(navigationController, animated: true)
        
//        self.navigationController?.pushViewController(MediaPreviewController(for: chatMessage), animated: false)
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
        tableView.register(IncomingMsgCell.self, forCellReuseIdentifier: ChatViewController.incomingMsgCellReuseIdentifier)
        tableView.register(OutgoingMsgCell.self, forCellReuseIdentifier: ChatViewController.outgoingMsgCellReuseIdentifier)
        tableView.delegate = self
        return tableView
    }()
    
    // MARK: Tableview Delegates
    
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
    
    private func isOutgoingMessageStatusUpdate(for chatMessage: ChatMessage) -> Bool {
        guard chatMessage.fromUserId == MainAppContext.shared.userData.userId else { return false }
        guard let trackedChatMessage = self.trackedChatMessages[chatMessage.id] else { return false }
        if trackedChatMessage.outgoingStatus != chatMessage.outgoingStatus {
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
                return med
            }
        }
        return nil
    }
    
    private func updateCellMedia(for cell: IncomingMsgCell, with med: ChatMedia) {
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
            
            if isOutgoingMessageStatusUpdate(for: chatMessage) {
                DDLogDebug("ChatViewController/frc/update/outgoingMessageStatusChange")
                self.skipDataUpdate = false
            }
            
            // incoming messages media changes, update directly
            if let updatedChatMedia = findUpdatedMedia(for: chatMessage) {
                guard let cell = self.tableView.cellForRow(at: indexPath!) as? IncomingMsgCell else { break }
                DDLogDebug("ChatViewController/frc/update-cell-directly/updatedMedia")
                self.updateCellMedia(for: cell, with: updatedChatMedia)
            }
        case .insert:
            DDLogDebug("ChatViewController/frc/insert")
            self.shouldScrollToBottom = true
        case .move:
            DDLogDebug("ChatViewController/frc/move")
        case .delete:
            DDLogDebug("ChatViewController/frc/delete")
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        if self.skipDataUpdate {
            DDLogDebug("ChatViewController/frc/update/skipDataUpdate")
            self.skipDataUpdate = false
            return
        }
        
        self.updateData(animatingDifferences: false)
        
        if self.shouldScrollToBottom {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.scrollToBottom(true)
            }
            self.shouldScrollToBottom = false
        }
    }

    func updateData(animatingDifferences: Bool = true) {
        guard let chatMessages = self.fetchedResultsController?.fetchedObjects else { return}

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, ChatMessage>()
        diffableDataSourceSnapshot.appendSections([ ChatViewController.sectionMain ])
        diffableDataSourceSnapshot.appendItems(chatMessages)
        self.dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences)
    }

    private func scrollToBottom(_ animated: Bool = true) {
        if let dataSnapshot = self.dataSource?.snapshot() {
            let numberOfRows = dataSnapshot.numberOfItems(inSection: ChatViewController.sectionMain)
            let indexPath = IndexPath(row: numberOfRows - 1, section: ChatViewController.sectionMain)
            self.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
        }
    }

    // MARK: Input view

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

    // MARK: ChatInputView Delegates
    
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
        }
        if animationDuration > 0 {
            updateBlock()
        } else {
            UIView.performWithoutAnimation(updateBlock)
        }
    }

    func chatInputView(_ inputView: ChatInputView, wantsToSend text: String) {
        sendMessage(text: text, media: [])
    }
    
    func sendMessage(text: String, media: [PendingMedia]) {
        guard let sendToUserId = self.fromUserId else { return }
        
        MainAppContext.shared.chatData.sendMessage(toUserId: sendToUserId, text: text, media: media, feedPostId: self.feedPostId, feedPostMediaIndex: self.feedPostMediaIndex)
        
        self.chatInputView.closeQuoteFeedPanel()
        
        self.feedPostId = nil
        self.feedPostMediaIndex = 0
        self.chatInputView.text = ""
    }
    
    func chatInputView(_ inputView: ChatInputView) {
        presentPhotoLibraryPickerNew()
    }
    
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView) {
        self.feedPostId = nil
        self.feedPostMediaIndex = 0
    }

    private func presentPhotoLibraryPickerNew() {
        let pickerController = MediaPickerViewController(camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }

            controller.dismiss(animated: true) {
                if !cancel {
                    self.presentMessageComposer(with: media)
                }
            }
        }

        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func presentMessageComposer(with media: [PendingMedia]) {
        let vc = MessageComposerView(mediaItemsToPost: media)
        vc.delegate = self
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: false, completion: nil)
    }
    
    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        chatInputView.hideKeyboard()
    }
}

extension ChatViewController: TitleViewDelegate {
    fileprivate func titleView(_ titleView: TitleView) {
        guard let userID = fromUserId else { return }
        let userViewController = UserFeedViewController(userID: userID)
        navigationController?.pushViewController(userViewController, animated: true)
    }
}

fileprivate struct TrackedChatMedia {
    let relativeFilePath: String?
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
    var media: [TrackedChatMedia] = []

    init(with chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.cellHeight = Int(chatMessage.cellHeight)
        self.outgoingStatus = chatMessage.outgoingStatus

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
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    private func setup() {
        let imageSize: CGFloat = 35
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
        let view = UIStackView(arrangedSubviews: [nameLabel, lastSeenLabel])
        view.axis = .vertical
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
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
    
    func update(with fromUserId: String, status: UserPresenceType, lastSeen: Date?) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: fromUserId)
        
        switch status {
        case .away:
            if let lastSeen = lastSeen {
                lastSeenLabel.text = lastSeen.lastSeenTimestamp()
                lastSeenLabel.isHidden = false
            }
        case .available:
            lastSeenLabel.isHidden = false
            lastSeenLabel.text = "online"
        default:
            lastSeenLabel.isHidden = true
            lastSeenLabel.text = ""
        }
        
        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
    }
    
    @objc func gotoProfile(_ sender: UIView) {
        delegate?.titleView(self)
    }
}

class IncomingMsgCell: UITableViewCell, IncomingMsgViewDelegate {

    var previewAction: ((_ previewType: MediaPreviewController.PreviewType, _ mediaIndex: Int) -> ())?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.incomingMsgView.reset()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = UIColor.feedBackground
        
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins.top = 0
        contentView.layoutMargins.bottom = 0
        
        contentView.addSubview(incomingMsgView)
        
        incomingMsgView.translatesAutoresizingMaskIntoConstraints = false
        incomingMsgView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        incomingMsgView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        incomingMsgView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = false
        incomingMsgView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        incomingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * Constants.WidthOfMsgBubble).rounded()).isActive = true
    }
    
    private lazy var incomingMsgView: IncomingMsgView = {
        let view = IncomingMsgView()
        view.delegate = self
        return view
    }()
    
    func update(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        self.incomingMsgView.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)
    }
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        self.incomingMsgView.updateMedia(sliderMedia)
    }
    
    // MARK: ChatViewDelegates
    
    func incomingMsgView(_ incomingMsgView: IncomingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int) {
        if self.previewAction != nil {
            self.previewAction!(previewType, mediaIndex)
        }
    }
}

class OutgoingMsgCell: UITableViewCell, OutgoingMsgViewDelegate {

    var previewAction: ((_ previewType: MediaPreviewController.PreviewType, _ mediaIndex: Int) -> ())?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        outgoingMsgView.reset()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = UIColor.feedBackground
        
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins.top = 0
        contentView.layoutMargins.bottom = 0
        
        contentView.addSubview(outgoingMsgView)
        
        outgoingMsgView.translatesAutoresizingMaskIntoConstraints = false
        outgoingMsgView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = false
        outgoingMsgView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        outgoingMsgView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        outgoingMsgView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        outgoingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * Constants.WidthOfMsgBubble).rounded()).isActive = true
    }

    private lazy var outgoingMsgView: OutgoingMsgView = {
        let view = OutgoingMsgView()
        view.delegate = self
        return view
    }()
    
    func update(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        outgoingMsgView.updateWithChatMessage(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender, isNextMsgSameSender: isNextMsgSameSender, isNextMsgSameTime: isNextMsgSameTime)
    }
    
    // MARK: OutgoingMsgView Delegates
    
    func outgoingMsgView(_ outgoingMsgView: OutgoingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int) {
        guard previewAction != nil else { return }
        previewAction!(previewType, mediaIndex)
    }
}
