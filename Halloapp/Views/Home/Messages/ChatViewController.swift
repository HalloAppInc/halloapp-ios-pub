//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Combine
import Core
import CoreData
import Photos
import UIKit
import SwiftUI
import YPImagePicker

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

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        guard self.fromUserId != nil else { return }

        super.viewDidLoad()
        
        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = UIColor.systemGray6
        appearance.shadowColor = .clear
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        
        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (self.view.frame.width*0.7))
        ])
        
        self.navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        self.titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        titleView.update(with: self.fromUserId!, status: UserPresenceType.none, lastSeen: nil)
        
        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.tableHeaderView = nil
        self.tableView.tableFooterView = nil
        
        self.dataSource = UITableViewDiffableDataSource<Int, ChatMessage>(tableView: self.tableView) { [weak self] tableView, indexPath, chatMessage in
            guard let self = self else { return nil }
            
            self.trackedChatMessages[chatMessage.id] = TrackedChatMessage(with: chatMessage)
            
            var isPreviousMsgSameSender = false

            if chatMessage.fromUserId == MainAppContext.shared.userData.userId {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.outgoingMsgCellReuseIdentifier, for: indexPath) as? OutgoingMsgCell {

                    let previousRow = indexPath.row - 1

                    if previousRow >= 0 {
                        let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)

                        if let previousChatMessage = self.fetchedResultsController?.object(at: previousIndexPath) {
                            if previousChatMessage.fromUserId == chatMessage.fromUserId {
                                isPreviousMsgSameSender = true
                            }
                        }
                    }

                    cell.update(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender)
                    cell.backgroundColor = UIColor.systemGray6

                    if (chatMessage.media != nil) || (chatMessage.quoted != nil && chatMessage.quoted?.media != nil) {
                        cell.previewAction = { [weak self] previewType, mediaIndex in
                            guard let self = self else { return }
                            self.showPreviewView(for: chatMessage, previewType: previewType, mediaIndex: mediaIndex)
                        }
                    }
                    
                    return cell
                }
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.incomingMsgCellReuseIdentifier, for: indexPath) as! IncomingMsgCell

            let previousRow = indexPath.row - 1

            if previousRow >= 0 {
                let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)

                if let previousChatMessage = self.fetchedResultsController?.object(at: previousIndexPath) {
                    if previousChatMessage.fromUserId == chatMessage.fromUserId {
                        isPreviousMsgSameSender = true
                    }
                }
            }

            cell.update(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender)
            cell.backgroundColor = UIColor.systemGray6

            if (chatMessage.media != nil) || (chatMessage.quoted != nil && chatMessage.quoted?.media != nil) {
                cell.previewAction = { [weak self] previewType, mediaIndex in
                    guard let self = self else { return }
                    self.showPreviewView(for: chatMessage, previewType: previewType, mediaIndex: mediaIndex)
                }
            }

            return cell
        }

        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(fromUserId = %@ AND toUserId = %@) || (toUserId = %@ && fromUserId = %@)", self.fromUserId!, MainAppContext.shared.userData.userId, self.fromUserId!, AppContext.shared.userData.userId)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.id, ascending: true) // if timestamps are the same, break tie
        ]
        
        self.fetchedResultsController =
            NSFetchedResultsController<ChatMessage>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext,
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
        
        if let feedPostId = self.feedPostId {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    self.chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: mediaItem.type, mediaUrl: mediaItem.relativeFilePath)
                } else {
                    self.chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: nil, mediaUrl: nil)
                }
            }
        }
        
        self.cancellableSet.insert(
            MainAppContext.shared.chatData.didGetCurrentChatPresence.sink { [weak self] status, ts in
                DDLogInfo("ChatViewController/didGetCurrentChatPresence")
                guard let self = self else { return }
                guard let userId = self.fromUserId else { return }
                self.titleView.update(with: userId, status: status, lastSeen: ts)
            }
        )

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.chatInputView.willAppear(in: self)
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
            MainAppContext.shared.chatData.markThreadAsRead(for: chatWithUserId)
            MainAppContext.shared.chatData.updateUnreadThreadCount()
            MainAppContext.shared.chatData.updateUnreadMessageCount()
            MainAppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)
        }
        self.chatInputView.didAppear(in: self)
        
        NotificationUtility.removeDelivered(forType: .chat, withFromId: self.fromUserId!)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        MainAppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        self.chatInputView.willDisappear(in: self)
    }
    
    deinit {
        DDLogDebug("ChatViewController/deinit/\(fromUserId ?? "")")
    }
    
    // MARK:
    
    private func showPreviewView(for chatMessage: ChatMessage, previewType: MediaPreviewController.PreviewType, mediaIndex: Int) {
        let detailVC = MediaPreviewController(for: chatMessage, previewType: previewType, mediaIndex: mediaIndex)
        let navigationController = UINavigationController(rootViewController: detailVC)
        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.modalTransitionStyle = .crossDissolve
        self.present(navigationController, animated: true)
        
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
        self.sendMessage(text: text, media: [])
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
        self.presentPhotoLibraryPicker()
    }
    
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView) {
        self.feedPostId = nil
        self.feedPostMediaIndex = 0
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

                    if let videoSize = VideoUtils().resolutionForLocalVideo(url: video.url) {
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

fileprivate class TitleView: UIView {
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder){
        super.init(coder: aDecoder)
        setup()
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
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
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
    }

    func update(with fromUserId: String, status: UserPresenceType, lastSeen: Date?) {
        self.nameLabel.text = MainAppContext.shared.contactStore.fullName(for: fromUserId)
        
        switch status {
        case .away:
            if let lastSeen = lastSeen {
                self.lastSeenLabel.text = lastSeen.lastSeenTimestamp()
                self.lastSeenLabel.isHidden = false
            }
        case .available:
            self.lastSeenLabel.isHidden = false
            self.lastSeenLabel.text = "online"
        default:
            self.lastSeenLabel.isHidden = true
            self.lastSeenLabel.text = ""
        }
        
        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
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

        self.incomingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * 0.8).rounded()).isActive = true
    }
    
    private lazy var incomingMsgView: IncomingMsgView = {
        let view = IncomingMsgView()
        view.delegate = self
        return view
    }()
    
    var savedChatMessage: ChatMessage?
    
    func update(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool) {
        self.savedChatMessage = chatMessage
        self.incomingMsgView.updateWith(chatMessage: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender)
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
        self.outgoingMsgView.reset()
    }

    private func setup() {
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

        self.outgoingMsgView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(UIScreen.main.bounds.width * 0.8).rounded()).isActive = true
    }

    private lazy var outgoingMsgView: OutgoingMsgView = {
        let view = OutgoingMsgView()
        view.delegate = self
        return view
    }()
    
    func update(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool) {
        self.outgoingMsgView.updateWith(with: chatMessage, isPreviousMsgSameSender: isPreviousMsgSameSender)
    }
    
    // MARK: OutgoingMsgView Delegates
    
    func outgoingMsgView(_ outgoingMsgView: OutgoingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int) {
        if self.previewAction != nil {
            self.previewAction!(previewType, mediaIndex)
        }
    }
    
}
