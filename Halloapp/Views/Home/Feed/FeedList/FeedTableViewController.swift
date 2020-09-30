//
//  FeedTableView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import UIKit

fileprivate enum FeedTableSection {
    case main
}

fileprivate extension FeedPost {
    var hideFooterSeparator: Bool {
        !orderedMedia.isEmpty && text?.isEmpty ?? true
    }
}

class FeedTableViewController: UIViewController, NSFetchedResultsControllerDelegate, UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate, FeedTableViewCellDelegate {

    private struct Constants {
        static let activePostCellReuseIdentifier = "active-post"
        static let deletedPostCellReuseIdentifier = "deleted-post"
    }

    let tableView = UITableView()
    private(set) var fetchedResultsController: NSFetchedResultsController<FeedPost>?

    private var cancellableSet: Set<AnyCancellable> = []

    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        DDLogInfo("FeedTableViewController/viewDidLoad")

        navigationItem.standardAppearance = .opaqueAppearance

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.showsVerticalScrollIndicator = false
        tableView.register(FeedPostTableViewCell.self, forCellReuseIdentifier: Constants.activePostCellReuseIdentifier)
        tableView.register(DeletedPostTableViewCell.self, forCellReuseIdentifier: Constants.deletedPostCellReuseIdentifier)
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self
        tableView.dataSource = self

        setupFetchedResultsController()

        cancellableSet.insert(MainAppContext.shared.feedData.willDestroyStore.sink { [weak self] in
            guard let self = self else { return }
            self.fetchedResultsController = nil
            self.tableView.reloadData()
            self.view.isUserInteractionEnabled = false
        })

        cancellableSet.insert(
            MainAppContext.shared.feedData.didReloadStore.sink { [weak self] in
                guard let self = self else { return }
                self.view.isUserInteractionEnabled = true
                self.setupFetchedResultsController()
                self.tableView.reloadData()
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.stopAllVideoPlayback()
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.refreshTimestamps()
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                guard let indexPaths = self.tableView.indexPathsForVisibleRows else { return }
                indexPaths.forEach { (indexPath) in
                    self.didShowPost(atIndexPath: indexPath)
                }
        })
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: tableView)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigationBarStyleUsing(scrollView: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stopAllVideoPlayback()
    }

    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        if firstSection.numberOfObjects > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: true)
        }
    }

    // MARK: FeedTableViewController Customization

    public var fetchRequest: NSFetchRequest<FeedPost> {
        fatalError("Must be implemented in a subclass.")
    }

    public func shouldOpenFeed(for userID: UserID) -> Bool {
        return true
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    func reloadTableView() {
        guard fetchedResultsController != nil else { return }
        fetchedResultsController?.delegate = nil
        setupFetchedResultsController()
        if isViewLoaded {
            tableView.reloadData()
        }
    }

    private func setupFetchedResultsController() {
        fetchedResultsController = newFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest,
                                                                            managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                                            sectionNameKeyPath: nil,
                                                                            cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        trackPerRowFRCChanges = view.window != nil && UIApplication.shared.applicationState == .active
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                self.tableView.setNeedsLayout()
                self.tableView.layoutIfNeeded()
            }
        }
        DDLogDebug("FeedTableView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/insert [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .fade)
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .none)
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/move [\(feedPost)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            }

        case .update:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { return }
            DDLogDebug("FeedTableView/frc/update [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                var reloadRow = feedPost.isPostRetracted
                if !reloadRow {
                    // Update UI without doing full cell reuse-reload if possible to avoid flickering.
                    if let cell = tableView.cellForRow(at: indexPath) as? FeedPostTableViewCellBase, cell.postId == feedPost.id {
                        let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
                        let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * tableView.layoutMargins.left
                        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)
                        DDLogDebug("FeedTableView/frc/update/soft [\(feedPost)] at [\(indexPath)]")
                    } else {
                        reloadRow = true
                    }
                }
                if reloadRow {
                    DDLogDebug("FeedTableView/frc/update/full [\(feedPost)] at [\(indexPath)]")
                    tableView.reloadRows(at: [ indexPath ], with: .none)
                }
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedTableView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
            CATransaction.commit()
        } else {
            tableView.reloadData()
        }
    }

    // MARK: UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController?.sections else {
            return 0
        }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let feedPost = fetchedResultsController?.object(at: indexPath) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        let cellReuseIdentifier = feedPost.isPostRetracted ? Constants.deletedPostCellReuseIdentifier : Constants.activePostCellReuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! FeedPostTableViewCellBase

        let postId = feedPost.id
        let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
        let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * tableView.layoutMargins.left
        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)

        if let activePostCell = cell as? FeedPostTableViewCell {
            activePostCell.commentAction = { [weak self] in
                guard let self = self else { return }
                self.showCommentsView(for: postId)
            }
            activePostCell.messageAction = { [weak self] in
                guard let self = self else { return }
                self.showMessageView(for: postId)
            }
            activePostCell.showSeenByAction = { [weak self] in
                guard let self = self else { return }
                self.showSeenByView(for: postId)
            }
            activePostCell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
            activePostCell.cancelSendingAction = { [weak self] in
                guard let self = self else { return }
                self.cancelSending(postId: postId)
            }
            activePostCell.retrySendingAction = { [weak self] in
                guard let self = self else { return }
                self.retrySending(postId: postId)
            }
            activePostCell.delegate = self
        }
        if let deletedPostCell = cell as? DeletedPostTableViewCell {
            deletedPostCell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        didShowPost(atIndexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let feedCell = cell as? FeedPostTableViewCell {
            feedCell.stopPlayback()
        }
    }

    // MARK: FeedTableViewCellDelegate

    fileprivate func feedTableViewCell(_ cell: FeedPostTableViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    fileprivate func feedTableViewCellDidRequestReloadHeight(_ cell: FeedPostTableViewCell, animations animationBlock: () -> Void) {
        tableView.beginUpdates()
        animationBlock()
        tableView.endUpdates()

        if let postId = cell.postId, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            feedDataItem.textExpanded = true
        }
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        let commentsViewController = CommentsViewController(feedPostId: postId)
        commentsViewController.highlightedCommentId = commentId
        navigationController?.pushViewController(commentsViewController, animated: true)
    }

    private func showMessageView(for postId: FeedPostID) {
        if let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            navigationController?.pushViewController(ChatViewController(for: feedDataItem.userId, with: postId, at: Int32(feedDataItem.currentMediaIndex ?? 0)), animated: true)
        }
    }

    private func showSeenByView(for postId: FeedPostID) {
        let seenByViewController = FeedPostSeenByViewController(feedPostId: postId)
        present(UINavigationController(rootViewController: seenByViewController), animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        guard shouldOpenFeed(for: userID) else { return }
        let userViewController = UserFeedViewController(userID: userID)
        navigationController?.pushViewController(userViewController, animated: true)
    }

    private func cancelSending(postId: FeedPostID) {
        MainAppContext.shared.feedData.cancelMediaUpload(postId: postId)
    }

    private func retrySending(postId: FeedPostID) {
        MainAppContext.shared.feedData.retryPosting(postId: postId)
    }

    // MARK: Misc

    private func stopAllVideoPlayback() {
        for cell in tableView.visibleCells {
            if let feedTableViewCell = cell as? FeedPostTableViewCell {
                feedTableViewCell.stopPlayback()
            }
        }
    }

    private func refreshTimestamps() {
        guard let indexPaths = tableView.indexPathsForVisibleRows else { return }
        for indexPath in indexPaths {
            if let feedTableViewCell = tableView.cellForRow(at: indexPath) as? FeedPostTableViewCell,
                let feedPost = fetchedResultsController?.object(at: indexPath) {
                feedTableViewCell.refreshTimestamp(using: feedPost)
            }
        }
    }

    private func didShowPost(atIndexPath indexPath: IndexPath) {
        if let feedPost = fetchedResultsController?.object(at: indexPath) {
            // Load downloaded images into memory.
            MainAppContext.shared.feedData.feedDataItem(with: feedPost.id)?.loadImages()

            // Initiate download for images that were not yet downloaded.
            MainAppContext.shared.feedData.downloadMedia(in: [ feedPost ])

            // If app is in foreground and is currently active:
            // • send "seen" receipt for the post
            // • remove notifications for the post
            if UIApplication.shared.applicationState == .active {
                MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
                UNUserNotificationCenter.current().removeDeliveredNotifications(forType: .feedpost, contentId: feedPost.id)
            }
        }
    }
}


private protocol FeedTableViewCellDelegate: AnyObject {
    func feedTableViewCell(_ cell: FeedPostTableViewCell, didRequestOpen url: URL)
    func feedTableViewCellDidRequestReloadHeight(_ cell: FeedPostTableViewCell, animations animationBlock: () -> Void)
}

private class FeedTableViewCellBackgroundPanelView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.backgroundColor = .secondarySystemGroupedBackground
        self.layer.shadowRadius = 8
        self.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.layer.shadowColor = UIColor.black.cgColor
        self.updateShadowPath()
    }

    override var bounds: CGRect {
        didSet { updateShadowPath() }
    }

    override var frame: CGRect {
        didSet { updateShadowPath() }
    }

    var isShadowHidden: Bool = false {
        didSet { self.layer.shadowOpacity = isShadowHidden ? 0 : 0.08 }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { self.layer.cornerRadius = cornerRadius }
    }

    private func updateShadowPath() {
        // Explicitly set shadow's path for better performance.
        self.layer.shadowPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: cornerRadius).cgPath
    }
}

private class FeedPostTableViewCellBase: UITableViewCell {

    var postId: FeedPostID? = nil

    fileprivate struct LayoutConstants {
        static let backgroundCornerRadius: CGFloat = 15
        /**
         Content view (vertical stack takes standard table view content width: tableView.width - tableView.layoutMargins.left - tableView.layoutMargins.right
         Background "card" horizontal insets are 1/2 of the layout margin.
         */
        static let backgroundPanelViewOutsetV: CGFloat = 8
        /**
         In contrast with horizontal margins, vertical margins are defined relative to cell's top and bottom edges.
         Background "card" has 25 pt margins on top and bottom (so that space between cards is 50 pt).
         Content is further inset 8 points relative to the card's top and bottom edges.
         */
        static let backgroundPanelVMargin: CGFloat = 25
        /**
         The background panel's width is defined as a ratio of the table view's layout margins. Because it is 0.5,
         the edge of the card lies halfway between the edge of the cell's content and the edge of the screen.
         */
        static let backgroundPanelHMarginRatio: CGFloat = 0.5
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private(set) var backgroundPanelView: FeedTableViewCellBackgroundPanelView!

    private func commonInit() {
        selectionStyle = .none
        backgroundColor = .clear

        backgroundPanelView = FeedTableViewCellBackgroundPanelView()
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius

        let backgroundView = UIView()
        backgroundView.preservesSuperviewLayoutMargins = true
        backgroundView.addSubview(backgroundPanelView)
        self.backgroundView = backgroundView
        updateBackgroundPanelShadow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundView = backgroundView {
            let panelInsets = UIEdgeInsets(
                top: LayoutConstants.backgroundPanelVMargin,
                left: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.left,
                bottom: LayoutConstants.backgroundPanelVMargin,
                right: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.right)
            backgroundPanelView.frame = backgroundView.bounds.inset(by: panelInsets)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            // Shadow color needs to be updated when user interface style changes between dark and light.
            updateBackgroundPanelShadow()
        }
    }

    private func updateBackgroundPanelShadow() {
        backgroundPanelView.isShadowHidden = traitCollection.userInterfaceStyle == .dark
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        DDLogVerbose("FeedTableViewCell/configure [\(post.id)]")

        postId = post.id
    }
}


private class FeedPostTableViewCell: FeedPostTableViewCellBase, TextLabelDelegate {

    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var showUserAction: ((UserID) -> ())?
    var cancelSendingAction: (() -> ())?
    var retrySendingAction: (() -> ())?

    weak var delegate: FeedTableViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var headerView: FeedItemHeaderView!

    private var itemContentView: FeedItemContentView!

    private var footerView: FeedItemFooterView!

    private func commonInit() {
        headerView = FeedItemHeaderView()
        headerView.preservesSuperviewLayoutMargins = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        itemContentView = FeedItemContentView()
        itemContentView.translatesAutoresizingMaskIntoConstraints = false
        itemContentView.textLabel.delegate = self
        contentView.addSubview(itemContentView)

        footerView = FeedItemFooterView()
        footerView.preservesSuperviewLayoutMargins = true
        footerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerView)

        // Lower constraint priority to avoid unsatisfiable constraints situation when UITableViewCell's height is 44 during early table view layout passes.
        let footerViewBottomConstraint = footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV))
        footerViewBottomConstraint.priority = .required - 10

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // CONTENT
            itemContentView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            itemContentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            itemContentView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // FOOTER
            footerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            footerView.topAnchor.constraint(equalTo: itemContentView.bottomAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            footerViewBottomConstraint
        ])

        // Separator in the footer view needs to be extended past view bounds to be the same width as background "card".
        addConstraints([
            footerView.separator.leadingAnchor.constraint(equalTo: backgroundPanelView.leadingAnchor),
            footerView.separator.trailingAnchor.constraint(equalTo: backgroundPanelView.trailingAnchor)
        ])

        // Connect actions of footer view buttons
        footerView.commentButton.addTarget(self, action: #selector(showComments), for: .touchUpInside)
        footerView.messageButton.addTarget(self, action: #selector(messageContact), for: .touchUpInside)
        footerView.facePileView.addTarget(self, action: #selector(showSeenBy), for: .touchUpInside)
        footerView.cancelAction = { [weak self] in
            self?.cancelSendingAction?()
        }
        footerView.retryAction = { [weak self] in
            self?.retrySendingAction?()
        }
    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)
        footerView.configure(with: post, contentWidth: contentWidth)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
        itemContentView.prepareForReuse()
        footerView.prepareForReuse()
    }

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url, let delegate = delegate {
                delegate.feedTableViewCell(self, didRequestOpen: url)
            }
        case .userMention:
            if let userID = link.userID {
                showUserAction?(userID)
            }
        default:
            break
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        delegate?.feedTableViewCellDidRequestReloadHeight(self) {
            itemContentView.textLabel.numberOfLines = 0
        }
    }

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        headerView.configure(with: feedPost)
    }

    // MARK: Button actions

    @objc private func showComments() {
        if let action = commentAction {
            action()
        }
    }

    @objc private func messageContact() {
        if let action = messageAction {
            action()
        }
    }

    @objc private func showSeenBy() {
        if let action = showSeenByAction {
            action()
        }
    }
}


private class DeletedPostTableViewCell: FeedPostTableViewCellBase {

    var showUserAction: ((UserID) -> ())?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var headerView: FeedItemHeaderView!

    private func commonInit() {
        headerView = FeedItemHeaderView()
        headerView.preservesSuperviewLayoutMargins = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textAlignment = .center
        textLabel.textColor = .secondaryLabel
        textLabel.text = "This post has been deleted"
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        let view = UIView()
        view.backgroundColor = .clear
        view.layoutMargins.top = 20
        view.layoutMargins.bottom = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textLabel)
        textLabel.constrainMargins(to: view)
        contentView.addSubview(view)

        // Lower constraint priority to avoid unsatisfiable constraints situation when UITableViewCell's height is 44 during early table view layout passes.
        let viewBottomConstraint = view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV))
        viewBottomConstraint.priority = .required - 10

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // TEXT
            view.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            viewBottomConstraint
        ])

    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
    }
}


private class FeedItemContentView: UIView {

    private var postId: FeedPostID? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private var vStack: UIStackView!

    private var textContentView: UIView!

    private(set) var textLabel: TextLabel!

    private var mediaView: MediaCarouselView?

    private func setupView() {
        isUserInteractionEnabled = true
        layoutMargins = UIEdgeInsets(top: 5, left: 0, bottom: 8, right: 0)

        textLabel = TextLabel()
        textLabel.textColor = .label
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        textContentView = UIView()
        textContentView.translatesAutoresizingMaskIntoConstraints = false
        textContentView.addSubview(textLabel)
        textLabel.constrainMargins(to: textContentView)

        vStack = UIStackView(arrangedSubviews: [ textContentView ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        addSubview(vStack)
        vStack.constrainMargins(to: self)
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        guard let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: post.id) else { return }

        if let mediaView = mediaView {
            let keepMediaView = postId == post.id
            if !keepMediaView {
                vStack.removeArrangedSubview(mediaView)
                mediaView.removeFromSuperview()
                self.mediaView = nil
            } else {
                DDLogInfo("FeedTableViewCell/content-view/reuse-media-view post=[\(post.id)]")
            }
        }

        let postContainsMedia = !feedDataItem.media.isEmpty
        if postContainsMedia && mediaView == nil {
            let mediaViewHeight = MediaCarouselView.preferredHeight(for: feedDataItem.media, width: contentWidth)
            var mediaViewConfiguration = MediaCarouselViewConfiguration.default
            mediaViewConfiguration.gutterWidth = gutterWidth
            let mediaView = MediaCarouselView(feedDataItem: feedDataItem, configuration: mediaViewConfiguration)
            mediaView.addConstraint({
                let constraint = mediaView.heightAnchor.constraint(equalToConstant: mediaViewHeight)
                constraint.priority = .required - 10
                return constraint
            }())
            vStack.insertArrangedSubview(mediaView, at: 0)
            self.mediaView = mediaView
        }

        // With media or > 180 chars long: System 16 pt (Body - 1)
        // Text-only under 180 chars long: System 20 pt (Body + 3)
        let postContainsText = !(post.text ?? "").isEmpty
        if postContainsText {
            textContentView.isHidden = false

            let postText = MainAppContext.shared.contactStore.textWithMentions(
                post.text,
                orderedMentions: post.orderedMentions)
            let postFont: UIFont = {
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let fontSizeDiff: CGFloat = postContainsMedia || (postText?.string ?? "").count > 180 ? -1 : 3
                return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
            }()
            textLabel.attributedText = postText?.with(font: postFont, color: .label)
            textLabel.numberOfLines = feedDataItem.textExpanded ? 0 : postContainsMedia ? 3 : 10
            // Adjust vertical margins around text.
            textContentView.layoutMargins.top = postContainsMedia ? 11 : 9
        } else {
            textContentView.isHidden = true
        }

        // Remove extra spacing
        layoutMargins.bottom = post.hideFooterSeparator ? 2 : 8

        postId = post.id
    }

    func prepareForReuse() { }

    func stopPlayback() {
        if let mediaView = mediaView {
            mediaView.stopPlayback()
        }
    }
}


private class FeedItemHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    var showUserAction: (() -> ())? = nil

    private var contentSizeCategoryDidChangeCancellable: AnyCancellable!

    private lazy var avatarViewButton: AvatarViewButton = {
        let avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        avatarViewButton.addTarget(self, action: #selector(showUser), for: .touchUpInside)
        return avatarViewButton
    }()

    // Gotham Medium, 15 pt (Subhead)
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUser)))
        return label
    }()

    // Gotham Medium, 14 pt (Footnote + 1)
    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = {
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
            return UIFont.gothamFont(ofSize: fontDescriptor.pointSize + 1, weight: .medium)
        }()
        label.textColor = .tertiaryLabel
        label.textAlignment = .natural
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal) // higher than contact name
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(avatarViewButton)

        let hStack = UIStackView(arrangedSubviews: [ nameLabel, timestampLabel ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.spacing = 8
        configure(stackView: hStack, forVerticalLayout: UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory)
        addSubview(hStack)

        avatarViewButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        avatarViewButton.heightAnchor.constraint(equalTo: avatarViewButton.widthAnchor).isActive = true
        avatarViewButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        avatarViewButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        avatarViewButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalToSystemSpacingAfter: avatarViewButton.trailingAnchor, multiplier: 1).isActive = true
        hStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        hStack.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true

        contentSizeCategoryDidChangeCancellable = NotificationCenter.default
            .publisher(for: UIContentSizeCategory.didChangeNotification)
            .compactMap { $0.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? UIContentSizeCategory }
            .sink { [weak self ]category in
                guard let self = self else { return }
                self.configure(stackView: hStack, forVerticalLayout: category.isAccessibilityCategory)
        }
    }

    private func configure(stackView: UIStackView, forVerticalLayout verticalLayout: Bool) {
        if verticalLayout {
            stackView.axis = .vertical
            stackView.alignment = .fill
        } else {
            stackView.axis = .horizontal
            stackView.alignment = .firstBaseline
        }
    }

    func configure(with post: FeedPost) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: post.userId)
        timestampLabel.text = post.timestamp.feedTimestamp()
        avatarViewButton.avatarView.configure(with: post.userId, using: MainAppContext.shared.avatarStore)
    }

    func prepareForReuse() {
        avatarViewButton.avatarView.prepareForReuse()
    }

    @objc func showUser() {
        showUserAction?()
    }

}


private class FeedItemFooterView: UIView {

    class ButtonWithBadge: UIButton {

        enum BadgeState {
            case hidden
            case unread
            case read
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.setupView()
        }

        var badge: BadgeState = .hidden {
            didSet {
                switch self.badge {
                case .hidden:
                    self.badgeView.isHidden = true

                case .unread:
                    self.badgeView.isHidden = false
                    self.badgeView.fillColor = .systemBlue
                    self.badgeView.alpha = 0.7

                case .read:
                    self.badgeView.isHidden = false
                    self.badgeView.fillColor = .systemGray4
                    self.badgeView.alpha = 1.0
                }
            }
        }

        private let badgeView = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: 7, height: 7)))

        private func setupView() {
            self.addSubview(badgeView)
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            guard let titleLabel = self.titleLabel else { return }

            let spacing: CGFloat = 6
            let spacingToCenter = spacing + badgeView.bounds.width/2
            let badgeCenterX: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? titleLabel.frame.maxX + spacingToCenter : titleLabel.frame.minX - spacingToCenter
            self.badgeView.center = self.badgeView.alignedCenter(from: CGPoint(x: badgeCenterX, y: titleLabel.frame.midY))
        }

    }

    class PostingProgressView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        var isIndeterminate = false {
            didSet {
                progressView.isHidden = isIndeterminate
                cancelButton.isHidden = isIndeterminate
                textLabel.isHidden = !isIndeterminate
                if isIndeterminate {
                    activityIndicatorView.startAnimating()
                } else {
                    activityIndicatorView.stopAnimating()
                }
            }
        }

        var progress: Float {
            get { progressView.progress }
            set { progressView.progress = newValue }
        }

        var indeterminateProgressText: String? {
            get { textLabel.text }
            set { textLabel.text = newValue }
        }

        lazy private var progressView = UIProgressView(progressViewStyle: .default)
        lazy private var textLabel: UILabel = {
            let label = UILabel()
            label.text = "Posting..."
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            return label
        }()
        lazy private var activityIndicatorView = UIActivityIndicatorView()
        lazy private(set) var cancelButton: UIButton = {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
            return button
        }()

        private func commonInit() {
            addSubview(progressView)
            progressView.translatesAutoresizingMaskIntoConstraints = false
            progressView.constrainMargin(anchor: .leading, to: self)
            progressView.centerYAnchor.constraint(equalTo: self.layoutMarginsGuide.centerYAnchor).isActive = true

            addSubview(textLabel)
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            textLabel.constrain([ .leading, .trailing ], to: progressView)
            textLabel.constrainMargins([ .top, .bottom ], to: self)

            addSubview(cancelButton)
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            cancelButton.constrainMargins([ .trailing, .top, .bottom ], to: self)
            cancelButton.widthAnchor.constraint(equalTo: cancelButton.heightAnchor).isActive = true
            cancelButton.leadingAnchor.constraint(equalToSystemSpacingAfter: progressView.trailingAnchor, multiplier: 2).isActive = true

            addSubview(activityIndicatorView)
            activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
            activityIndicatorView.centerXAnchor.constraint(equalTo: cancelButton.centerXAnchor).isActive = true
            activityIndicatorView.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor).isActive = true
        }
    }

    private enum State {
        case normal
        case ownPost
        case sending
        case retracting
        case error
    }

    var cancelAction: (() -> ())? = nil
    var retryAction: (() -> ())? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // Gotham Medium, 15 pt (Subhead)
    lazy var commentButton: ButtonWithBadge = {
        let spacing: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? 6 : -6
        let button = ButtonWithBadge(type: .system)
        button.setTitle("Comment", for: .normal)
        button.setImage(UIImage(named: "FeedPostComment"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium, maximumPointSize: 21)
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        return button
    }()

    // Gotham Medium, 15 pt (Subhead)
    lazy var messageButton: UIButton = {
        let spacing: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? 8 : -8
        let button = UIButton(type: .system)
        button.setTitle("Message", for: .normal)
        button.setImage(UIImage(named: "FeedPostMessage"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium, maximumPointSize: 21)
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        return button
    }()
    
    lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()

    lazy var separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }()

    var buttonStack: UIStackView!

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(separator)

        separator.topAnchor.constraint(equalTo: topAnchor).isActive = true
        // Horizontal size / position constraints will be installed by the cell.

        buttonStack = UIStackView(arrangedSubviews: [ commentButton, messageButton ])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 24
        addSubview(buttonStack)
        buttonStack.constrain(to: self)

        addSubview(facePileView)
        facePileView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        facePileView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4).isActive = true
    }

    private class func state(for post: FeedPost) -> State {
        switch post.status {
        case .sending: return .sending
        case .sendError: return .error
        case .retracting: return .retracting
        default: return post.userId == MainAppContext.shared.userData.userId ? .ownPost : .normal
        }
    }

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        separator.isHidden = post.hideFooterSeparator

        let state = Self.state(for: post)

        buttonStack.isHidden = state == .sending || state == .error || state == .retracting
        if buttonStack.isHidden {
            if state == .sending || state == .retracting {
                showProgressView()
                hideErrorView()

                let postId = post.id
                let mediaUploader = MainAppContext.shared.feedData.mediaUploader

                if mediaUploader.hasTasks(forGroupId: postId) {
                    progressView.isIndeterminate = false

                    if uploadProgressCancellable == nil {
                        uploadProgressCancellable = mediaUploader.uploadProgressDidChange.sink { [weak self] (groupId, progress) in
                            guard let self = self else { return }
                            if postId == groupId {
                                self.progressView.progress = progress
                            }
                        }
                        progressView.progress = mediaUploader.uploadProgress(forGroupId: postId)
                    }
                } else {
                    progressView.isIndeterminate = true
                    progressView.indeterminateProgressText = state == .sending ? "Posting..." : "Deleting..."
                }
            } else {
                showSendErrorView()
                hideProgressView()
            }
        } else {
            hideProgressView()
            hideErrorView()

            commentButton.badge = (post.comments ?? []).isEmpty ? .hidden : (post.unreadCount > 0 ? .unread : .read)
            messageButton.alpha = state == .ownPost ? 0 : 1
        }

        facePileView.isHidden = state != .ownPost
        if !facePileView.isHidden {
            facePileView.configure(with: post)
        }

    }

    func prepareForReuse() {
        uploadProgressCancellable?.cancel()
        uploadProgressCancellable = nil

        facePileView.prepareForReuse()
    }

    // MARK: Upload Progress

    static private let progressViewTag = 1

    private var uploadProgressCancellable: AnyCancellable?

    private lazy var progressView: PostingProgressView = {
        let view = PostingProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)
        view.tag = Self.progressViewTag
        view.cancelButton.addTarget(self, action: #selector(cancelButtonAction), for: .touchUpInside)
        return view
    }()

    private func showProgressView() {
        if progressView.superview == nil {
            addSubview(progressView)
            progressView.constrain(to: buttonStack)
        }
        progressView.isHidden = false
    }

    private func hideProgressView() {
        uploadProgressCancellable?.cancel()
        uploadProgressCancellable = nil

        subviews.first(where: { $0.tag == Self.progressViewTag })?.isHidden = true
    }

    @objc private func cancelButtonAction() {
        cancelAction?()
    }

    // MARK: Error / retry View

    static private let errorViewTag = 2

    private lazy var errorView: UIView = {
        let errorText = UILabel()
        errorText.translatesAutoresizingMaskIntoConstraints = false
        errorText.font = .preferredFont(forTextStyle: .subheadline)
        errorText.numberOfLines = 0
        errorText.textColor = .systemRed
        errorText.text = "Failed to post."

        let retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setImage(UIImage(systemName: "arrow.counterclockwise.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
        retryButton.addTarget(self, action: #selector(retryButtonAction), for: .touchUpInside)

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)
        view.tag = Self.errorViewTag
        view.addSubview(errorText)
        view.addSubview(retryButton)

        errorText.constrainMargins([ .leading, .top, .bottom ], to: view)
        retryButton.constrainMargins([ .trailing, .top, .bottom ], to: view)
        retryButton.widthAnchor.constraint(equalTo: retryButton.heightAnchor).isActive = true
        retryButton.leadingAnchor.constraint(equalToSystemSpacingAfter: errorText.trailingAnchor, multiplier: 1).isActive = true

        return view
    }()

    private func showSendErrorView() {
        if errorView.superview == nil {
            addSubview(errorView)
            errorView.constrain(to: buttonStack)
        }
        errorView.isHidden = false
    }

    private func hideErrorView() {
        subviews.first(where: { $0.tag == Self.errorViewTag })?.isHidden = true
    }

    @objc private func retryButtonAction() {
        retryAction?()
    }
}


private class FacePileView: UIControl {
    var avatarViews: [AvatarView] = []
    let numberOfFaces = 3
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        for index in 0 ..< numberOfFaces {
            // The avatars are added from right to left
            let avatarView = AvatarView()
            avatarView.backgroundColor = .secondarySystemGroupedBackground
            avatarView.borderColor = .secondarySystemGroupedBackground
            avatarView.borderWidth = 2
            avatarView.isHidden = true
            avatarView.isUserInteractionEnabled = false // Let FacePileView handle touch event
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            
            self.addSubview(avatarView)
            avatarViews.append(avatarView)
            
            if index == 0 {
                // The rightmost avatar
                avatarView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            } else {
                let previousView = self.avatarViews[index - 1]
                avatarView.trailingAnchor.constraint(equalTo: previousView.centerXAnchor, constant: -3).isActive = true
            }
            
            avatarView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
            avatarView.heightAnchor.constraint(equalToConstant: 25).isActive = true
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor).isActive = true
        }
        
        let lastView = avatarViews.last!
        self.leadingAnchor.constraint(equalTo: lastView.leadingAnchor).isActive = true
        self.topAnchor.constraint(equalTo: lastView.topAnchor).isActive = true
        self.bottomAnchor.constraint(equalTo: lastView.bottomAnchor).isActive = true
    }
    
    func configure(with post: FeedPost) {
        let seenByUsers = MainAppContext.shared.feedData.seenByUsers(for: post)
        
        var usersWithAvatars: [UserAvatar] = []
        var usersWithoutAvatar: [UserAvatar] = []
        
        for user in seenByUsers {
            let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: user.userId)
            if !userAvatar.isEmpty {
                usersWithAvatars.append(userAvatar)
            } else {
                usersWithoutAvatar.append(userAvatar)
            }
            if usersWithAvatars.count >= numberOfFaces {
                break
            }
        }
        
        if usersWithAvatars.count < numberOfFaces {
            usersWithAvatars.append(contentsOf: usersWithoutAvatar.prefix(numberOfFaces - usersWithAvatars.count))
        }
        
        if !usersWithAvatars.isEmpty {
            // The avatars are applied from right to left
            usersWithAvatars.reverse()
            for userIndex in 0 ..< usersWithAvatars.count {
                let avatarView = avatarViews[userIndex]
                avatarView.isHidden = false
                avatarView.configure(with: usersWithAvatars[userIndex], using: MainAppContext.shared.avatarStore)
                
                switch usersWithAvatars.count - userIndex {
                case 3:
                    avatarView.imageAlpha = 0.7 // The rightmost avatar
                case 2:
                    avatarView.imageAlpha = 0.9 // The middle avatar
                default:
                    avatarView.imageAlpha = 1 // The leftmost avatar
                }
                
            }
        } else { // No one has seen this post. Just show a dummy avatar.
            guard let avatarView = avatarViews.first else { return }
            avatarView.resetImage()
            avatarView.imageAlpha = 1
            avatarView.isHidden = false
        }
    }

    func prepareForReuse() {
        for avatarView in avatarViews {
            avatarView.prepareForReuse()
            avatarView.isHidden = true
        }
    }
}
