//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import UIKit
import YPImagePicker
import AVFoundation
import Photos
import SwiftUI

class ChatViewController: UIViewController, UITableViewDelegate, ChatInputViewDelegate, NSFetchedResultsControllerDelegate {
    
    private var fromUserId: String?
    private var feedPostId: FeedPostID?
    private var feedPostMediaIndex: Int32 = 0
    
    private var fetchedResultsController: NSFetchedResultsController<ChatMessage>?
    private var dataSource: UITableViewDiffableDataSource<Int, ChatMessage>?
    
    static private let sectionMain = 0
    static private let otherUserCellReuseIdentifier = "OtherUserCell"
    static private let userCellReuseIdentifier = "UserCell"

    // MARK: Lifecycle
    
    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        DDLogDebug("ChatViewController/init/\(fromUserId)")
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
        titleView.update(with: self.fromUserId!)
        
        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.tableHeaderView = nil
        self.tableView.tableFooterView = nil
        
//        /* NOTE: seem too brittle to have to estimate a correct height, else wonkiness happens
//         * should investigate if there's a way to find the exact height,
//         * perhaps manually calculate it and then cache it
//         */
////        tableView.rowHeight = UITableView.automaticDimension
//        tableView.estimatedRowHeight = 53
        
        self.dataSource = UITableViewDiffableDataSource<Int, ChatMessage>(tableView: self.tableView) { tableView, indexPath, chatMessage in
            if chatMessage.fromUserId == AppContext.shared.userData.userId {
                if let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.userCellReuseIdentifier, for: indexPath) as? ChatTableViewUserCell {
                    cell.update(with: chatMessage)
                    cell.backgroundColor = UIColor.systemGray6
                    
                    if chatMessage.quoted != nil && chatMessage.quoted?.media != nil {
                        cell.previewAction = { [weak self] in
                            guard let self = self else { return }
                            self.showPreviewView(for: chatMessage)
                        }
                    }
                    
                    return cell
                }
            }
                
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatViewController.otherUserCellReuseIdentifier, for: indexPath) as! ChatTableViewCell
            cell.update(with: chatMessage)
            cell.backgroundColor = UIColor.systemGray6

            if chatMessage.quoted != nil && chatMessage.quoted?.media != nil {
                cell.previewAction = { [weak self] in
                    guard let self = self else { return }
                    self.showPreviewView(for: chatMessage)
                }
            }
            
            return cell
        }

        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(fromUserId = %@ AND toUserId = %@) || (toUserId = %@ && fromUserId = %@)", self.fromUserId!, AppContext.shared.userData.userId, self.fromUserId!, AppContext.shared.userData.userId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true) ]
        
        self.fetchedResultsController =
            NSFetchedResultsController<ChatMessage>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.chatData.viewContext,
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
            if let feedPost = AppContext.shared.feedData.feedPost(with: feedPostId) {
                if let mediaItem = feedPost.media?.first(where: { $0.order == self.feedPostMediaIndex }) {
                    self.chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: mediaItem.type, mediaUrl: mediaItem.relativeFilePath)
                } else {
                    self.chatInputView.showQuoteFeedPanel(with: feedPost.userId, text: feedPost.text ?? "", mediaType: nil, mediaUrl: nil)
                }
            }
        }
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
            AppContext.shared.chatData.markThreadAsRead(for: chatWithUserId)
            AppContext.shared.chatData.updateUnreadMessageCount()
            AppContext.shared.chatData.subscribeToPresence(to: chatWithUserId)
            AppContext.shared.chatData.setCurrentlyChattingWithUserId(for: chatWithUserId)
        }
        self.chatInputView.didAppear(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AppContext.shared.chatData.setCurrentlyChattingWithUserId(for: nil)
        self.chatInputView.willDisappear(in: self)
    }
    
    func dismantle() {
        DDLogDebug("ChatViewController/dismantle/\(fromUserId ?? "")")
        self.fetchedResultsController = nil
    }

    // MARK:
    
    private func showPreviewView(for chatMessage: ChatMessage) {
        
        let detailVC = MediaPreviewController(for: chatMessage)
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
        tableView.register(ChatTableViewCell.self, forCellReuseIdentifier: ChatViewController.otherUserCellReuseIdentifier)
        tableView.register(ChatTableViewUserCell.self, forCellReuseIdentifier: ChatViewController.userCellReuseIdentifier)
        tableView.delegate = self
        return tableView
    }()
    
    // MARK: Tableview Delegates
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // TODO: too brittle, need a way to have correct heights
        guard let chatMessage = self.fetchedResultsController?.object(at: indexPath) else { return 50 }
        var result:CGFloat = 50.0
        if chatMessage.quoted != nil {
            result += 70
        }
        
        if chatMessage.media != nil {
            if !chatMessage.media!.isEmpty {
                result += 30
            }
        }
        
        return result
    }
    
    // MARK: Data

    private var shouldScrollToBottom = true
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
                    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
        case .update:
            DDLogDebug("ChatView/frc/update")
        case .insert:
            DDLogDebug("ChatView/frc/insert")
            self.shouldScrollToBottom = true
        case .move:
            DDLogDebug("ChatView/frc/move")
        case .delete:
            DDLogDebug("ChatView/frc/delete")
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.updateData(animatingDifferences: false)
        
        if self.shouldScrollToBottom {
            self.scrollToBottom(true)
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
        let bottomInset = keyboardHeight - self.tableView.safeAreaInsets.bottom
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
        if let toUserId = self.fromUserId {
            AppContext.shared.chatData.sendMessage(toUserId: toUserId, text: text, media: [], feedPostId: self.feedPostId ?? "", feedPostMediaIndex: self.feedPostMediaIndex)
//            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
//                self.scrollToBottom(false)
//            }
            
            self.feedPostId = nil
            self.feedPostMediaIndex = 0
            self.chatInputView.text = ""
            
        }
        
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
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: false, completion: nil)
    }
    
    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        self.chatInputView.hideKeyboard()
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

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)

        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var lastSeenLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private func setup() {
        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        
        let vStack = UIStackView(arrangedSubviews: [self.nameLabel, self.lastSeenLabel])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 2
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)

        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, vStack, spacer ])
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

    func update(with fromUserId: String) {
        self.nameLabel.text = AppContext.shared.contactStore.fullName(for: fromUserId)
//        self.lastSeenLabel.text = AppContext.shared.contactStore.fullName(for: fromUserId)
    }
    
}


class ChatTableViewCell: UITableViewCell, ChatViewDelegate {

    var previewAction: (() -> ())?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupTableViewCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTableViewCell()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.chatView.reset()
    }

    private func setupTableViewCell() {
        self.selectionStyle = .none
        
        self.contentView.preservesSuperviewLayoutMargins = false
        self.contentView.layoutMargins.top = 0
        self.contentView.layoutMargins.bottom = 10
        
        self.contentView.addSubview(self.chatView)
        
        self.chatView.translatesAutoresizingMaskIntoConstraints = false
        self.chatView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.chatView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.chatView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = false
        self.chatView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.chatView.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.85).isActive = true
        self.chatView.layer.cornerRadius = 20.0
        
    }
    
    private lazy var chatView: ChatView = {
        let view = ChatView()
        view.delegate = self
        return view
    }()
    
    func update(with chatMessage: ChatMessage) {
        self.chatView.updateWith(chatMessage: chatMessage)
    }
    
    // MARK: ChatViewDelegates
    
    func chatView(_ chatView: ChatView) {
        if self.previewAction != nil {
            self.previewAction!()
        }
    }
}

class ChatTableViewUserCell: UITableViewCell, ChatUserViewDelegate {

    var previewAction: (() -> ())?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupTableViewCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTableViewCell()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.chatUserView.reset()
    }

    private func setupTableViewCell() {
        self.selectionStyle = .none
        
        self.contentView.preservesSuperviewLayoutMargins = false
        self.contentView.layoutMargins.top = 0
        self.contentView.layoutMargins.bottom = 10
        
        self.contentView.addSubview(self.chatUserView)
        
        self.chatUserView.translatesAutoresizingMaskIntoConstraints = false
        self.chatUserView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = false
        self.chatUserView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.chatUserView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.chatUserView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.chatUserView.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.85).isActive = true
        self.chatUserView.layer.cornerRadius = 20.0
        
    }

    private lazy var chatUserView: ChatUserView = {
        let view = ChatUserView()
        view.delegate = self
        return view
    }()
    
    func update(with chatMessage: ChatMessage) {
        self.chatUserView.updateWith(with: chatMessage)
    }
    
    // MARK: ChatUserViewDelegates
    
    func chatUserView(_ chatView: ChatUserView) {
        print("chatuser")
        if self.previewAction != nil {
            self.previewAction!()
        }
    }
    
}
