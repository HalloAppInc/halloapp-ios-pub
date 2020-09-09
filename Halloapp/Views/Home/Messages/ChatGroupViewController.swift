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
import YPImagePicker

fileprivate struct Constants {
    static let WidthOfMsgBubble:CGFloat = 0.9
}

class ChatGroupViewController: UIViewController, UITableViewDelegate, ChatInputViewDelegate, NSFetchedResultsControllerDelegate {
    
    private var groupId: GroupID
    
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMessage>?
    private var dataSource: UITableViewDiffableDataSource<Int, ChatGroupMessage>?
    
    private var trackedChatGroupMessages: [String: TrackedChatGroupMessage] = [:]

    static private let sectionMain = 0
    static private let inboundMsgCellReuseIdentifier = "InboundMsgCell"
    static private let outboundMsgCellReuseIdentifier = "OutboundMsgCell"
    
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
        appearance.backgroundColor = UIColor.systemGray6
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
        titleView.update(with: groupId)
        titleView.delegate = self
        
        view.addSubview(tableView)
        tableView.constrain(to: view)

        tableView.backgroundColor = UIColor.systemGray6
        tableView.tableHeaderView = nil
        tableView.tableFooterView = nil
        
        self.dataSource = UITableViewDiffableDataSource<Int, ChatGroupMessage>(tableView: self.tableView) { [weak self] tableView, indexPath, chatGroupMessage in
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
            
            // outbound cell
            if chatGroupMessage.userId == MainAppContext.shared.userData.userId {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatGroupViewController.outboundMsgCellReuseIdentifier, for: indexPath) as? OutboundMsgCell {

                    cell.update(with: chatGroupMessage,
                                isPreviousMsgSameSender: isPreviousMsgSameSender,
                                isNextMsgSameSender: isNextMsgSameSender,
                                isNextMsgSameTime: isNextMsgSameTime)

                    if chatGroupMessage.media != nil {
                        cell.previewAction = { [weak self] previewType, mediaIndex in
                            guard let self = self else { return }
                            self.showPreviewView(previewType: previewType, media: chatGroupMessage.orderedMedia, quotedMedia: [], mediaIndex: mediaIndex)
                        }
                    }
                    
                    cell.delegate = self
                    return cell
                }
            } else {

                // inbound cell
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatGroupViewController.inboundMsgCellReuseIdentifier, for: indexPath) as? InboundMsgCell {

                    cell.update(with: chatGroupMessage,
                                isPreviousMsgSameSender: isPreviousMsgSameSender,
                                isNextMsgSameSender: isNextMsgSameSender,
                                isNextMsgSameTime: isNextMsgSameTime)

                    if chatGroupMessage.media != nil {
                        cell.previewAction = { [weak self] previewType, mediaIndex in
                            guard let self = self else { return }
                            self.showPreviewView(previewType: previewType, media: chatGroupMessage.orderedMedia, quotedMedia: [], mediaIndex: mediaIndex)
                        }
                    }

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
                
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        chatInputView.willAppear(in: self)
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
        
//        NotificationUtility.removeDelivered(forType: .chat, withFromId: self.fromUserId!)
        
        // TODO: group info should be sync-ed just in case every so often
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        MainAppContext.shared.chatData.setCurrentlyChattingInGroup(for: nil)
        chatInputView.willDisappear(in: self)
    }
    
    deinit {
        DDLogDebug("ChatGroupViewController/deinit/\(groupId)")
    }
    
    // MARK:
    
    private func showPreviewView(previewType: MediaPreviewController.PreviewType, media: [ChatMedia]?, quotedMedia: [ChatQuotedMedia]?, mediaIndex: Int) {
        let detailVC = MediaPreviewController(previewType: previewType, media: media, quotedMedia:quotedMedia, mediaIndex: mediaIndex)
        let navigationController = UINavigationController(rootViewController: detailVC)
        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.modalTransitionStyle = .crossDissolve
        present(navigationController, animated: true)

//        self.navigationController?.pushViewController(MediaPreviewController(for: chatMessage), animated: false)
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
        tableView.register(InboundMsgCell.self, forCellReuseIdentifier: ChatGroupViewController.inboundMsgCellReuseIdentifier)
        tableView.register(OutboundMsgCell.self, forCellReuseIdentifier: ChatGroupViewController.outboundMsgCellReuseIdentifier)
        tableView.delegate = self
        return tableView
    }()
    
    // MARK: Tableview Delegates
    
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
                return med
            }
        }
        return nil
    }
    
    private func updateCellMedia(for cell: InboundMsgCell, with med: ChatMedia) {
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
            self.skipDataUpdate = true
            guard let chatGroupMessage = anObject as? ChatGroupMessage else { break }

            if isOutgoingGroupMessageStatusUpdate(for: chatGroupMessage) {
                DDLogDebug("ChatGroupViewController/frc/update/outgoingGroupMessageStatusChange")
                self.skipDataUpdate = false
            }

            // incoming messages media changes, update directly
            if let updatedChatMedia = findUpdatedMedia(for: chatGroupMessage) {
                guard let cell = self.tableView.cellForRow(at: indexPath!) as? InboundMsgCell else { break }
                DDLogDebug("ChatGroupViewController/frc/update-cell-directly/updatedMedia")
                self.updateCellMedia(for: cell, with: updatedChatMedia)
            }
        case .insert:
            DDLogDebug("ChatGroupViewController/frc/insert")
            self.shouldScrollToBottom = true
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

    // MARK: Input view

    lazy var chatInputView: ChatInputView = {
        let inputView = ChatInputView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 90))
        inputView.delegate = self
        return inputView
    }()

    override var inputAccessoryView: UIView? {
        self.chatInputView.setInputViewWidth(self.view.bounds.size.width)
        return self.chatInputView
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

    // MARK: ChatInputView Delegates
    
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

    func chatInputView(_ inputView: ChatInputView, wantsToSend text: String) {
        self.sendGroupMessage(text: text, media: [])
    }
    
    func sendGroupMessage(text: String, media: [PendingMedia]) {
     
        MainAppContext.shared.chatData.sendGroupMessage(toGroupId: groupId, text: text, media: media)
        
        self.chatInputView.text = ""
    }
    
    // TODO: move chatInputViewCloseQuotePanel to a separate protocol
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView) {
    }
    
    func chatInputView(_ inputView: ChatInputView) {
        self.presentPhotoLibraryPicker()
    }
    
    private func presentPhotoLibraryPicker() {
        var config = YPImagePickerConfiguration()

        // General
        config.library.mediaType = .photoAndVideo
        config.shouldSaveNewPicturesToAlbum = false
        config.showsCrop = .none
        config.wordings.libraryTitle = "Gallery"
        config.showsPhotoFilters = false
        config.showsVideoTrimmer = false
        config.startOnScreen = YPPickerScreen.library
        config.screens = [.library, .photo, .video]
        config.hidesStatusBar = false
        config.hidesBottomBar = false
        
        // Library
        config.library.onlySquare = false
        config.library.isSquareByDefault = false
        config.library.mediaType = YPlibraryMediaType.photoAndVideo
        config.library.defaultMultipleSelection = false
        config.library.maxNumberOfItems = 10
        config.library.skipSelectionsGallery = true
        config.library.preselectedItems = nil

        // Video
        config.video.compression = AVAssetExportPresetPassthrough
        config.video.fileType = .mp4
        config.video.recordingTimeLimit = 60.0
        config.video.libraryTimeLimit = 60.0
        config.video.minimumTimeLimit = 3.0
        config.video.trimmerMaxDuration = 60.0
        config.video.trimmerMinDuration = 3.0

        let picker = YPImagePicker(configuration: config)
  
        picker.didFinishPicking { [unowned picker] items, cancelled in

            guard !cancelled else {
                picker.dismiss(animated: true)
                return
            }

            var mediaToPost: [PendingMedia] = []
            let mediaGroup = DispatchGroup()
            var orderCounter: Int = 1
            for item in items {
                mediaGroup.enter()
                switch item {
                case .photo(let photo):
                    let mediaItem = PendingMedia(type: .image)
                    mediaItem.order = orderCounter
                    mediaItem.image = photo.image
                    mediaItem.size = photo.image.size
                    orderCounter += 1
                    mediaToPost.append(mediaItem)
                    mediaGroup.leave()
                case .video(let video):
                    let mediaItem = PendingMedia(type: .video)
                    mediaItem.order = orderCounter
                    orderCounter += 1

                    if let videoSize = VideoUtils.resolutionForLocalVideo(url: video.url) {
                        mediaItem.size = videoSize
                        DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
                    }

                    if !video.fromCamera {
                        if let asset = video.asset {
                            PHCachingImageManager().requestAVAsset(forVideo: asset, options: nil) { (avAsset, _, _) in
                                let asset = avAsset as! AVURLAsset
                                mediaItem.videoURL = asset.url
                                mediaToPost.append(mediaItem)
                                mediaGroup.leave()
                            }
                        } else {
                            mediaGroup.leave()
                        }
                    } else {
                        mediaItem.videoURL = video.url
                        mediaToPost.append(mediaItem)
                        mediaGroup.leave()
                    }

                }
            }

            mediaGroup.notify(queue: .main) {
                mediaToPost.sort { $0.order < $1.order }
                picker.dismiss(animated: false) {
                    self.presentMessageComposer(with: mediaToPost)
                }
            }
        }
        
        self.present(picker, animated: true)
    }

    private func presentMessageComposer(with media: [PendingMedia]) {
        let vc = MessageComposerView(mediaItemsToPost: media)
        vc.delegate = self
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: false, completion: nil)
    }
    
    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        self.chatInputView.hideKeyboard()
    }
}



extension ChatGroupViewController: TitleViewDelegate {
    fileprivate func titleView(_ titleView: TitleView) {
        let vc = GroupInfoViewController(for: groupId)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ChatGroupViewController: OutboundMsgCellDelegate {
    
    func outboundMsgCell(_ outboundMsgCell: OutboundMsgCell, didLongPressOn msgId: String) {

        let actionSheet = UIAlertController(title: nil, message: "", preferredStyle: .actionSheet)
         actionSheet.addAction(UIAlertAction(title: "Info", style: .destructive) { [weak self] _ in
            guard let self = self else { return }

            let messageSeenByViewController = MessageSeenByViewController(chatGroupMessageId: msgId)
            self.present(UINavigationController(rootViewController: messageSeenByViewController), animated: true)
         })
         actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
         self.present(actionSheet, animated: true)
        
    }
    

}

extension ChatGroupViewController: MessageComposerViewDelegate {
    func messageComposerView(_ messageComposerView: MessageComposerView, text: String, media: [PendingMedia]) {
        self.sendGroupMessage(text: text, media: media)
    }
}

fileprivate struct TrackedChatGroupMedia {
    let relativeFilePath: String?
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
    func titleView(_ titleView: TitleView)
}

fileprivate class TitleView: UIView {
    
    weak var delegate: TitleViewDelegate?
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func update(with groupId: String) {
        if let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            self.nameLabel.text = chatGroup.name
        }
        
        //        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
    }

    private func setup() {
        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)

        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.nameColumn, spacer ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .leading
        hStack.spacing = 10

        self.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoGroupInfo(_:)))
        isUserInteractionEnabled = true
        addGestureRecognizer(tapGesture)
    }
    
    private lazy var contactImageView: AvatarView = {
        return AvatarView()
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
    
    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.nameLabel, self.lastSeenLabel])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.spacing = 0
        return view
    }()
    
    @objc func gotoGroupInfo(_ sender: UIView) {
        self.delegate?.titleView(self)
    }
}

class InboundMsgCell: UITableViewCell, IncomingMsgViewDelegate {

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
        backgroundColor = UIColor.systemGray6
        
        self.selectionStyle = .none
        
        self.contentView.preservesSuperviewLayoutMargins = false
        self.contentView.layoutMargins.top = 0
        self.contentView.layoutMargins.bottom = 0
        
        self.contentView.addSubview(self.incomingMsgView)
        
        self.incomingMsgView.translatesAutoresizingMaskIntoConstraints = false
        self.incomingMsgView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.incomingMsgView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.incomingMsgView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = false
        self.incomingMsgView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.incomingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * Constants.WidthOfMsgBubble).rounded()).isActive = true
    }
    
    private lazy var incomingMsgView: IncomingMsgView = {
        let view = IncomingMsgView()
        view.delegate = self
        return view
    }()
    
    func update(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        self.incomingMsgView.updateWithChatGroupMessage(with: chatGroupMessage,
                                                        isPreviousMsgSameSender: isPreviousMsgSameSender,
                                                        isNextMsgSameSender: isNextMsgSameSender,
                                                        isNextMsgSameTime: isNextMsgSameTime)
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


protocol OutboundMsgCellDelegate: AnyObject {
    func outboundMsgCell(_ outboundMsgCell: OutboundMsgCell, didLongPressOn msgId: String)
}

class OutboundMsgCell: UITableViewCell, OutgoingMsgViewDelegate {

    weak var delegate: OutboundMsgCellDelegate?
    
    var previewAction: ((_ previewType: MediaPreviewController.PreviewType, _ mediaIndex: Int) -> ())?
    var msgId: String?
    
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
        self.msgId = nil
        self.outgoingMsgView.reset()
    }

    private func setup() {
        backgroundColor = UIColor.systemGray6
        
        self.selectionStyle = .none
        
        self.contentView.preservesSuperviewLayoutMargins = false
        self.contentView.layoutMargins.top = 0
        self.contentView.layoutMargins.bottom = 0
        
        self.contentView.addSubview(self.outgoingMsgView)
        
        self.outgoingMsgView.translatesAutoresizingMaskIntoConstraints = false
        self.outgoingMsgView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = false
        self.outgoingMsgView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.outgoingMsgView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.outgoingMsgView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.outgoingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * Constants.WidthOfMsgBubble).rounded()).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoMsgInfo(_:)))
        outgoingMsgView.isUserInteractionEnabled = true
        outgoingMsgView.addGestureRecognizer(tapGesture)
        
    }

    private lazy var outgoingMsgView: OutgoingMsgView = {
        let view = OutgoingMsgView()
        view.delegate = self
        return view
    }()
    
    func update(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        self.msgId = chatGroupMessage.id
        self.outgoingMsgView.updateWithChatGroupMessage(with: chatGroupMessage,
                                                        isPreviousMsgSameSender: isPreviousMsgSameSender,
                                                        isNextMsgSameSender: isNextMsgSameSender,
                                                        isNextMsgSameTime: isNextMsgSameTime)
    }
    
    // MARK: OutgoingMsgView Delegates
    
    func outgoingMsgView(_ outgoingMsgView: OutgoingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int) {
        if self.previewAction != nil {
            self.previewAction!(previewType, mediaIndex)
        }
    }
    
    @objc func gotoMsgInfo(_ sender: UIView) {
        guard let messageId = msgId else { return }
        self.delegate?.outboundMsgCell(self, didLongPressOn: messageId)
    }
}
