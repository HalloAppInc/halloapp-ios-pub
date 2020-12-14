//
//  GroupChatViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Photos
import UIKit

// MARK: Constraint Constants
fileprivate struct Constants {
    static let WidthOfMsgBubble: CGFloat = 0.9
}

fileprivate class ChatGroupDataSource: UITableViewDiffableDataSource<Int, ChatGroupMessage> {
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}

class ChatGroupViewController: UIViewController, NSFetchedResultsControllerDelegate {
  
    private var groupId: GroupID
    
    private var chatReplyMessageID: String?
    private var chatReplyMessageSenderID: String?
    private var chatReplyMessageMediaIndex: Int32 = 0
    
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMessage>?
    private var dataSource: ChatGroupDataSource?
    
    private lazy var mentionableUsers: [MentionableUser] = {
        computeMentionableUsers()
    }()
    
    private var trackedChatGroupMessages: [String: TrackedChatGroupMessage] = [:]

    static private let sectionMain = 0
    static private let inboundMsgViewCellReuseIdentifier = "InboundMsgViewCell"
    static private let outboundMsgViewCellReuseIdentifier = "OutboundMsgViewCell"
    static private let eventMsgTableViewCellReuseIdentifier = "EventMsgTableViewCell"
    
    private var mediaPickerController: MediaPickerViewController?
        
    private var cancellableSet: Set<AnyCancellable> = []
    
    // MARK: Lifecycle
    
    init(for groupId: String) {
        DDLogDebug("GroupChatViewController/init/\(groupId)")
        self.groupId = groupId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = UIColor.feedBackground
        appearance.shadowColor = .clear
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        
        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.7))
        ])
        
        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        titleView.delegate = self
        
        view.addSubview(tableView)
        tableView.constrain(to: view)

        tableView.backgroundColor = UIColor.feedBackground
        tableView.tableHeaderView = nil
        tableView.tableFooterView = nil
        
        dataSource = ChatGroupDataSource(tableView: self.tableView) { [weak self] tableView, indexPath, chatGroupMessage in
            guard let self = self else { return nil }
            
            self.trackedChatGroupMessages[chatGroupMessage.id] = TrackedChatGroupMessage(with: chatGroupMessage)
            
            var isPreviousMsgSameSender = false
            var isNextMsgSameSender = false
            var isNextMsgSameTime = false
            
            let previousRow = indexPath.row - 1
            let nextRow = indexPath.row + 1

            if previousRow >= 0 {
                let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)

                if let previousChatGroupMessage = self.fetchedResultsController?.object(at: previousIndexPath) {
                    if previousChatGroupMessage.userId == chatGroupMessage.userId {
                        isPreviousMsgSameSender = true
                    }
                }
            }
            
            if nextRow < tableView.numberOfRows(inSection: 0) {
                let nextIndexPath = IndexPath(row: nextRow, section: indexPath.section)
                
                if let nextChatGroupMessage = self.fetchedResultsController?.object(at: nextIndexPath) {
                    
                    if nextChatGroupMessage.userId == chatGroupMessage.userId {
                        isNextMsgSameSender = true
                        if nextChatGroupMessage.timestamp?.chatTimestamp() == chatGroupMessage.timestamp?.chatTimestamp() {
                            isNextMsgSameTime = true
                        }
                    }

                }
            }
            
            //TODO: refactor out/inbound cells and update params after ui stabilize
            
            if chatGroupMessage.isEvent {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatGroupViewController.eventMsgTableViewCellReuseIdentifier, for: indexPath) as? EventMsgTableViewCell {
                    guard let text = chatGroupMessage.event?.text else { cell.isHidden = true; return cell }
                    cell.configure(with: text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.titleView.update(with: self.groupId) // update for group name/avatar changes
                    }
                    return cell
                }
            } else if chatGroupMessage.userId == MainAppContext.shared.userData.userId {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatGroupViewController.outboundMsgViewCellReuseIdentifier, for: indexPath) as? OutboundMsgViewCell {
                    cell.indexPath = indexPath
                    cell.updateWithChatGroupMessage(with: chatGroupMessage,
                                isPreviousMsgSameSender: isPreviousMsgSameSender,
                                isNextMsgSameSender: isNextMsgSameSender,
                                isNextMsgSameTime: isNextMsgSameTime)

                    cell.delegate = self
                    return cell
                }
            } else {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatGroupViewController.inboundMsgViewCellReuseIdentifier, for: indexPath) as? InboundMsgViewCell {
                    cell.indexPath = indexPath
                    cell.updateWithChatGroupMessage(with: chatGroupMessage,
                                isPreviousMsgSameSender: isPreviousMsgSameSender,
                                isNextMsgSameSender: isNextMsgSameSender,
                                isNextMsgSameTime: isNextMsgSameTime)
                    cell.delegate = self

                    return cell
                }
            }
            return UITableViewCell()
        }

        let fetchRequest: NSFetchRequest<ChatGroupMessage> = ChatGroupMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupId = %@", self.groupId)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatGroupMessage.id, ascending: true) // if timestamps are the same, break tie
        ]
        
        self.fetchedResultsController =
            NSFetchedResultsController<ChatGroupMessage>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
            self.updateData(animatingDifferences: false)
        } catch {
            return
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard(_:)))
        self.view.addGestureRecognizer(tapGesture)
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetChatStateInfo.sink { [weak self] in
                DDLogInfo("ChatGroupViewController/didGetChatStateInfo")
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.configureTitleViewWithTypingIndicator()
                }
            }
        )
        
        configureTitleViewWithTypingIndicator()
        
        guard let thread = MainAppContext.shared.chatData.chatThread(type: .group, id: groupId) else { return }
        guard thread.draft != "", let draft = thread.draft else { return }
        chatInputView.setDraftText(text: draft)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        titleView.update(with: groupId)
//        chatInputView.willAppear(in: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.tableHeaderView = nil
        tableView.tableFooterView = nil
        let scrollPoint = CGPoint(x: 0, y: tableView.contentSize.height + 1000)
        tableView.setContentOffset(scrollPoint, animated: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        MainAppContext.shared.chatData.markThreadAsRead(type: .group, for: groupId)
        MainAppContext.shared.chatData.updateUnreadThreadCount()
        MainAppContext.shared.chatData.setCurrentlyChattingInGroup(for: groupId)
        MainAppContext.shared.chatData.syncGroupIfNeeded(for: groupId)

        chatInputView.didAppear(in: self)
        
        UNUserNotificationCenter.current().removeDeliveredChatNotifications(groupId: groupId)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        MainAppContext.shared.chatData.saveDraft(type: .group, for: groupId, with: chatInputView.text)
        MainAppContext.shared.chatData.setCurrentlyChattingInGroup(for: nil)
        chatInputView.willDisappear(in: self)
    }
    
    deinit {
        DDLogDebug("ChatGroupViewController/deinit/\(groupId)")
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
        tableView.register(InboundMsgViewCell.self, forCellReuseIdentifier: ChatGroupViewController.inboundMsgViewCellReuseIdentifier)
        tableView.register(OutboundMsgViewCell.self, forCellReuseIdentifier: ChatGroupViewController.outboundMsgViewCellReuseIdentifier)
        tableView.register(EventMsgTableViewCell.self, forCellReuseIdentifier: ChatGroupViewController.eventMsgTableViewCellReuseIdentifier)
        tableView.delegate = self
        return tableView
    }()
    
    // MARK: Data

    private var shouldScrollToBottom = true
    private var skipDataUpdate = false
    
    private func isCellHeightUpdate(for chatGroupMessage: ChatGroupMessage) -> Bool {
        guard let trackedChatGroupMessage = self.trackedChatGroupMessages[chatGroupMessage.id] else { return false }
        if trackedChatGroupMessage.cellHeight != chatGroupMessage.cellHeight {
            return true
        }
        return false
    }
    
    private func isRetractStatusUpdate(for groupChatMessage: ChatGroupMessage) -> Bool {
        if groupChatMessage.inboundStatus == .retracted {
            return true
        }
        if [.retracting, .retracted].contains(groupChatMessage.outboundStatus) {
            return true
        }
        return false
    }
    
    private func isOutgoingGroupMessageStatusUpdate(for chatGroupMessage: ChatGroupMessage) -> Bool {
        guard chatGroupMessage.userId == MainAppContext.shared.userData.userId else { return false }
        guard let trackedChatGroupMessage = self.trackedChatGroupMessages[chatGroupMessage.id] else { return false }
        if trackedChatGroupMessage.outboundStatus != chatGroupMessage.outboundStatus {
            return true
        }
        return false
    }
    
    private func findUpdatedMedia(for chatGroupMessage: ChatGroupMessage) -> ChatMedia? {
        guard chatGroupMessage.userId != MainAppContext.shared.userData.userId else { return nil }
        guard let trackedChatGroupMessage = self.trackedChatGroupMessages[chatGroupMessage.id] else { return nil }
        guard let media = chatGroupMessage.media else { return nil }
        for med in media {
            guard med.relativeFilePath != nil else { continue }
            if trackedChatGroupMessage.media[Int(med.order)].relativeFilePath == nil {
                self.trackedChatGroupMessages[chatGroupMessage.id]?.media[Int(med.order)].relativeFilePath = med.relativeFilePath
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
            DDLogDebug("ChatGroupViewController/frc/update")
            skipDataUpdate = true
            guard let chatGroupMessage = anObject as? ChatGroupMessage else { break }

            // todo: check for changes and not just state
            if isRetractStatusUpdate(for: chatGroupMessage) {
                DDLogDebug("ChatViewController/frc/update/isInboundGroupMessageStatusUpdate")
                skipDataUpdate = false
            }
            
            if isOutgoingGroupMessageStatusUpdate(for: chatGroupMessage) {
                DDLogDebug("ChatGroupViewController/frc/update/isOutgoingGroupMessageStatusUpdate")
                skipDataUpdate = false
            }

            // incoming messages media changes, update directly
            if let updatedChatMedia = findUpdatedMedia(for: chatGroupMessage) {
                guard let cell = tableView.cellForRow(at: indexPath!) as? InboundMsgViewCell else { break }
                DDLogDebug("ChatGroupViewController/frc/update-cell-directly/updatedMedia")
                updateCellMedia(for: cell, with: updatedChatMedia)
            }
        case .insert:
            DDLogDebug("ChatGroupViewController/frc/insert")
            shouldScrollToBottom = true
        case .move:
            DDLogDebug("ChatGroupViewController/frc/move")
        case .delete:
            DDLogDebug("ChatGroupViewController/frc/delete")
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if self.skipDataUpdate {
            DDLogDebug("ChatGroupViewController/frc/update/skipDataUpdate")
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
        guard let chatGroupMessages = self.fetchedResultsController?.fetchedObjects else { return}

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, ChatGroupMessage>()
        diffableDataSourceSnapshot.appendSections([ ChatGroupViewController.sectionMain ])
        diffableDataSourceSnapshot.appendItems(chatGroupMessages)
        self.dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences)
    }

    private func scrollToBottom(_ animated: Bool = true) {
        if let dataSnapshot = self.dataSource?.snapshot() {
            let numberOfRows = dataSnapshot.numberOfItems(inSection: ChatGroupViewController.sectionMain)
            let indexPath = IndexPath(row: numberOfRows - 1, section: ChatGroupViewController.sectionMain)
            self.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
        }
    }

    private func configureTitleViewWithTypingIndicator() {
        let typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .group, id: self.groupId)
        
        if typingIndicatorStr == nil && !self.titleView.isShowingTypingIndicator {
            return
        }

        titleView.showChatState(with: typingIndicatorStr)
    }
    
    
    // MARK: Input view

    lazy var chatInputView: ChatInputView = {
        let inputView = ChatInputView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 90))
        inputView.delegate = self
        inputView.mentionsDelegate = self
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
        let topInset = self.tableView.contentInset.top
        let extraBottomInset: CGFloat = 10 // extra margin for the bottom of the table
        let bottomInset = keyboardHeight - self.tableView.safeAreaInsets.bottom + extraBottomInset
        let currentInset = self.tableView.contentInset
        var contentOffset = self.tableView.contentOffset
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
            self.tableView.contentOffset = contentOffset
        }
        // Setting contentInset below will also adjust contentOffset as needed if it is outside of the
        // UITableView's scrollable range.
        self.tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        let scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        self.tableView.scrollIndicatorInsets = scrollIndicatorInsets
    }

    
    func sendGroupMessage(mentionText: MentionText, media: [PendingMedia]) {
        MainAppContext.shared.chatData.sendGroupMessage(toGroupId: groupId,
                                                        mentionText: mentionText,
                                                        media: media,
                                                        chatReplyMessageID: chatReplyMessageID,
                                                        chatReplyMessageSenderID: chatReplyMessageSenderID,
                                                        chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)
        
        chatInputView.closeQuoteFeedPanel()
        
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

        self.present(UINavigationController(rootViewController: mediaPickerController!), animated: true)
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
            recipientName: MainAppContext.shared.chatData.chatGroup(groupId: groupId)?.name,
            configuration: .message,
            delegate: self)
        pickerController.present(UINavigationController(rootViewController: composerController), animated: false)
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        chatInputView.hideKeyboard()
    }
}

// MARK: PostComposerView Delegates
extension ChatGroupViewController: PostComposerViewDelegate {
    func composerShareAction(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia]) {
        sendGroupMessage(mentionText: mentionText, media: media)
    }

    func composerDidFinish(controller: PostComposerViewController, media: [PendingMedia], isBackAction: Bool) {
        controller.dismiss(animated: false)
        if isBackAction {
            mediaPickerController?.reset(selected: media)
        } else {
            dismissMediaPicker(animated: false)
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        chatInputView.text = mentionInput.text
    }
}

// MARK: UITableView Delegates
extension ChatGroupViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let chatGroupMessage = self.fetchedResultsController?.object(at: indexPath) else { return }

        let height = Int(cell.bounds.height)
        
        if chatGroupMessage.cellHeight != height {
            DDLogDebug("ChatGroupViewController/updateCellHeight/\(chatGroupMessage.id) from \(chatGroupMessage.cellHeight) to \(height)")
            MainAppContext.shared.chatData.updateChatGroupMessageCellHeight(for: chatGroupMessage.id, with: height)
        }
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        
        guard let chatGroupMessage = self.fetchedResultsController?.object(at: indexPath) else { return 50 }

        if chatGroupMessage.cellHeight != 0 {
            return CGFloat(chatGroupMessage.cellHeight)
        }
        
        let result:CGFloat = 50

//        if chatGroupMessage.media != nil {
//            result += 100
//        }

        DDLogDebug("ChatGroupViewController/estimatedCellHeight/\(chatGroupMessage.id) \(result)")
        return result
    }
    
}

// MARK: UITableView Datasource Delegates
extension ChatGroupViewController {
    
    // disable default swipe to delete
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return UITableViewCell.EditingStyle.none
    }
    
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatGroupMessage = self.fetchedResultsController?.object(at: indexPath), !chatGroupMessage.isEvent else {
            return UISwipeActionsConfiguration(actions: [])
        }
        guard chatGroupMessage.inboundStatus != .retracted else { return nil }
        guard ![.retracting, .retracted].contains(chatGroupMessage.outboundStatus) else { return nil }
        
        let action = UIContextualAction(style: .normal, title: Localizations.messageReply) { [weak self] (action, view, completionHandler) in
            
            if chatGroupMessage.userId == MainAppContext.shared.userData.userId {
                guard let cell = tableView.cellForRow(at: indexPath) as? OutboundMsgViewCell else { return }
                self?.handleQuotedReply(msg: chatGroupMessage, mediaIndex: cell.mediaIndex)
            } else {
                guard let cell = tableView.cellForRow(at: indexPath) as? InboundMsgViewCell else { return }
                self?.handleQuotedReply(msg: chatGroupMessage, mediaIndex: cell.mediaIndex)
            }
            
            completionHandler(true)
        }
        
        action.backgroundColor = UIColor.systemBlue
        return UISwipeActionsConfiguration(actions: [action])
    }
    
    private func handleQuotedReply(msg chatGroupMessage: ChatGroupMessage, mediaIndex: Int) {
        chatReplyMessageID = chatGroupMessage.id
        chatReplyMessageSenderID = chatGroupMessage.userId
        chatReplyMessageMediaIndex = Int32(mediaIndex)
        
        guard let userID = chatReplyMessageSenderID else { return }
        
        let mentionText = MainAppContext.shared.contactStore.textWithMentions(chatGroupMessage.text, orderedMentions: chatGroupMessage.orderedMentions)
        
        if let mediaItem = chatGroupMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
            let mediaType: ChatMessageMediaType = mediaItem.type == .video ? .video : .image
            let mediaUrl = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(mediaItem.relativeFilePath ?? "", isDirectory: false)
            
            chatInputView.showQuoteFeedPanel(with: userID, text: mentionText?.string ?? "", mediaType: mediaType, mediaUrl: mediaUrl, groupID: groupId, from: self)
        } else {
            chatInputView.showQuoteFeedPanel(with: userID, text: mentionText?.string ?? "", mediaType: nil, mediaUrl: nil, groupID: groupId, from: self)
        }

    }
    
}

extension ChatGroupViewController: TitleViewDelegate {
    fileprivate func titleViewRequestsOpenGroupInfo(_ titleView: TitleView) {
        let vc = GroupInfoViewController(for: groupId)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    fileprivate func titleViewRequestsOpenGroupFeed(_ titleView: TitleView) {
        if MainAppContext.shared.chatData.chatGroup(groupId: groupId) != nil {
            let vc = GroupFeedViewController(groupId: groupId)
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension ChatGroupViewController: InboundMsgViewCellDelegate {
 
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
        guard let chatGroupMessage = fetchedResultsController?.object(at: indexPath) else { return }

        guard chatGroupMessage.inboundStatus != .retracted else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.handleQuotedReply(msg: chatGroupMessage, mediaIndex: inboundMsgViewCell.mediaIndex)
         })

        if let messageText = chatGroupMessage.text, !messageText.isEmpty {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                let pasteboard = UIPasteboard.general
                pasteboard.string = messageText
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        
        present(actionSheet, animated: true)
    }
}

extension ChatGroupViewController: OutboundMsgViewCellDelegate {
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
        guard let chatGroupMessage = fetchedResultsController?.object(at: indexPath) else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if ![.retracting, .retracted].contains(chatGroupMessage.outboundStatus) {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageReply, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.handleQuotedReply(msg: chatGroupMessage, mediaIndex: outboundMsgViewCell.mediaIndex)
             })
        
        
            if let messageText = chatGroupMessage.text, !messageText.isEmpty {
                actionSheet.addAction(UIAlertAction(title: Localizations.messageCopy, style: .default) { _ in
                    let pasteboard = UIPasteboard.general
                    pasteboard.string = messageText
                })
            }
        }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.messageInfo, style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            let messageSeenByViewController = MessageSeenByViewController(chatGroupMessageId: msgId)
            self.present(UINavigationController(rootViewController: messageSeenByViewController), animated: true)
        })
        
        if [.sentOut, .delivered, .seen].contains(chatGroupMessage.outboundStatus) {
            actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                MainAppContext.shared.chatData.retractGroupChatMessage(groupID: self.groupId, messageToRetractID: chatGroupMessage.id)
            })
        }
        
        guard actionSheet.actions.count > 0 else { return }
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        self.present(actionSheet, animated: true)
    }
}

// MARK: ChatInputView Delegates
extension ChatGroupViewController: ChatInputViewDelegate {

    func chatInputView(_ inputView: ChatInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        var animationDuration = animationDuration
        if self.transitionCoordinator != nil {
            animationDuration = 0
        }
        var adjustContentOffset = true
        // Prevent the content offset from changing when the user drags the keyboard down.
        if self.tableView.panGestureRecognizer.state == .ended || self.tableView.panGestureRecognizer.state == .changed {
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
    
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView) {
        chatReplyMessageID = nil
        chatReplyMessageSenderID = nil
        chatReplyMessageMediaIndex = 0
    }
    
    func chatInputView(_ inputView: ChatInputView, isTyping: Bool) {
        if isTyping {
            MainAppContext.shared.chatData.sendChatState(type: .group, id: groupId, state: .typing)
        } else {
            MainAppContext.shared.chatData.sendChatState(type: .group, id: groupId, state: .available)
        }
    }
    
    func chatInputView(_ inputView: ChatInputView) {
        presentMediaPicker()
    }

    func chatInputView(_ inputView: ChatInputView, mentionText: MentionText) {
        sendGroupMessage(mentionText: mentionText, media: [])
    }
}

// MARK: ChatInputViewMentionsDelegate
extension ChatGroupViewController: ChatInputViewMentionsDelegate {
    func computeMentionableUsers() -> [MentionableUser] {
        return Mentions.mentionableUsers(forGroupID: groupId)
    }
    
    func chatInputView(_ inputView: ChatInputView, possibleMentionsForInput input: String) -> [MentionableUser] {
        return mentionableUsers.filter { Mentions.isPotentialMatch(fullName: $0.fullName, input: input) }
    }
}

fileprivate struct TrackedChatGroupMedia {
    var relativeFilePath: String?
    let order: Int

    init(with chatMedia: ChatMedia) {
        self.order = Int(chatMedia.order)
        self.relativeFilePath = chatMedia.relativeFilePath
    }
}

fileprivate struct TrackedChatGroupMessage {
    let id: String
    let cellHeight: Int
    let outboundStatus: ChatGroupMessage.OutboundStatus
    var media: [TrackedChatGroupMedia] = []

    init(with chatGroupMessage: ChatGroupMessage) {
        self.id = chatGroupMessage.id
        self.cellHeight = Int(chatGroupMessage.cellHeight)
        self.outboundStatus = chatGroupMessage.outboundStatus

        if let media = chatGroupMessage.media {
            for med in media {
                self.media.append(TrackedChatGroupMedia(with: med))
            }
        }
        self.media.sort {
            $0.order < $1.order
        }
    }
}

fileprivate protocol TitleViewDelegate: AnyObject {
    func titleViewRequestsOpenGroupInfo(_ titleView: TitleView)
    func titleViewRequestsOpenGroupFeed(_ titleView: TitleView)
}

fileprivate class TitleView: UIView {

    private struct LayoutConstants {
        static let avatarSize: CGFloat = 30
    }
    
    weak var delegate: TitleViewDelegate?
    
    public var isShowingTypingIndicator: Bool = false
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func update(with groupId: String) {
        if let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            nameLabel.text = chatGroup.name
        }
        
        avatarView.configure(groupId: groupId, using: MainAppContext.shared.avatarStore)
    }

    func showChatState(with typingIndicatorStr: String?) {
        let show: Bool = typingIndicatorStr != nil
        
        lastSeenLabel.isHidden = show
        typingLabel.isHidden = !show
        isShowingTypingIndicator = show
        
        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
        
    }
    
    private func setup() {
        avatarView = AvatarViewButton(type: .custom)
        avatarView.hasNewPostsIndicator = ServerProperties.isGroupFeedEnabled
        avatarView.newPostsIndicatorRingWidth = 3
        avatarView.newPostsIndicatorRingSpacing = 1
        let avatarButtonWidth: CGFloat = LayoutConstants.avatarSize + (avatarView.hasNewPostsIndicator ? 2*(avatarView.newPostsIndicatorRingSpacing + avatarView.newPostsIndicatorRingWidth) : 0)
        avatarView.widthAnchor.constraint(equalToConstant: avatarButtonWidth).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
        if ServerProperties.isGroupFeedEnabled {
            avatarView.addTarget(self, action: #selector(avatarButtonTapped), for: .touchUpInside)
        } else {
            avatarView.isUserInteractionEnabled = false
        }

        let hStack = UIStackView(arrangedSubviews: [ avatarView, nameColumn ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10

        addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(gesture:)))
        addGestureRecognizer(tapGesture)
    }
    
    private var avatarView: AvatarViewButton!
    
    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [nameLabel, lastSeenLabel, typingLabel])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.spacing = 0
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
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()
    
    private lazy var typingLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()
    
    @objc func handleSingleTap(gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            delegate?.titleViewRequestsOpenGroupInfo(self)
        }
    }

    @objc private func avatarButtonTapped() {
        delegate?.titleViewRequestsOpenGroupFeed(self)
    }
}

class EventMsgTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = ""
    }

    func configure(with text: String) {
        messageLabel.text = text
    }
    
    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 12, right: 18)

        contentView.addSubview(mainView)
        
        mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        
        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ messageRow ])
        view.axis = .vertical
        view.alignment = .center
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var messageRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ messageLabel])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.5)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        return view
    }()
    
    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .label
        label.textAlignment = .center
        
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
}
