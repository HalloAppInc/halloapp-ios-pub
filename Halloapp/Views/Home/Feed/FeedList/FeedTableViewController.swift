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

class FeedTableViewController: UITableViewController, NSFetchedResultsControllerDelegate, FeedTableViewCellDelegate {
    private static let cellReuseIdentifier = "FeedTableViewCell"

    private(set) var fetchedResultsController: NSFetchedResultsController<FeedPost>?

    private var cancellableSet: Set<AnyCancellable> = []

    init(title: String) {
        super.init(style: .plain)
        self.title = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        DDLogInfo("FeedTableViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance

        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = false
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.register(FeedTableViewCell.self, forCellReuseIdentifier: FeedTableViewController.cellReuseIdentifier)
        self.tableView.backgroundColor = .feedBackground

        self.setupFetchedResultsController()

        self.cancellableSet.insert(MainAppContext.shared.feedData.willDestroyStore.sink { [weak self] in
            guard let self = self else { return }
            self.fetchedResultsController = nil
            self.tableView.reloadData()
            self.view.isUserInteractionEnabled = false
        })

        self.cancellableSet.insert(
            MainAppContext.shared.feedData.didReloadStore.sink { [weak self] in
                guard let self = self else { return }
                self.view.isUserInteractionEnabled = true
                self.setupFetchedResultsController()
                self.tableView.reloadData()
        })

        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.stopAllVideoPlayback()
        })

        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.refreshTimestamps()
        })

        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                guard let indexPaths = self.tableView.indexPathsForVisibleRows else { return }
                indexPaths.forEach { (indexPath) in
                    self.didShowPost(atIndexPath: indexPath)
                }
        })
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: tableView)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppear()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppear()
        updateNavigationBarStyleUsing(scrollView: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewWillDisappear()
        stopAllVideoPlayback()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidDisappear()
    }

    func scrollToTop(animated: Bool) {
        guard let firstSection = self.fetchedResultsController?.sections?.first else { return }
        if firstSection.numberOfObjects > 0 {
            self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
    }

    // MARK: FeedTableViewController Customization

    public var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            fatalError("Must be implemented in a subclass.")
        }
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    func reloadTableView() {
        guard self.fetchedResultsController != nil else { return }
        self.fetchedResultsController?.delegate = nil
        setupFetchedResultsController()
        if self.isViewLoaded {
            self.tableView.reloadData()
        }
    }

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: self.fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("FeedTableView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            self.tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/insert [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.insertRows(at: [ indexPath ], with: .none)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .none)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/move [\(feedPost)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { return }
            DDLogDebug("FeedTableView/frc/update [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.reloadRows(at: [ indexPath ], with: .none)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedTableView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            self.tableView.endUpdates()
        } else if reloadTableViewInDidChangeContent {
            self.tableView.reloadData()
        }
    }

    // MARK: UITableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FeedTableViewController.cellReuseIdentifier, for: indexPath) as! FeedTableViewCell
        if let feedPost = fetchedResultsController?.object(at: indexPath) {
            let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
            let gutterWidth = (1 - FeedTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * tableView.layoutMargins.left
            cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)
            cell.commentAction = { [weak self] in
                guard let self = self else { return }
                self.showCommentsView(for: feedPost.id)
            }
            cell.messageAction = { [weak self] in
                guard let self = self else { return }
                self.showMessageView(for: feedPost.id)
            }
            cell.showSeenByAction = { [weak self] in
                guard let self = self else { return }
                self.showSeenByView(for: feedPost.id)
            }
            cell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
        }
        cell.delegate = self
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        didShowPost(atIndexPath: indexPath)
    }

    override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let feedCell = cell as? FeedTableViewCell {
            feedCell.stopPlayback()
        }
    }

    // MARK: FeedTableViewCellDelegate

    fileprivate func feedTableViewCell(_ cell: FeedTableViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    fileprivate func feedTableViewCellDidRequestReloadHeight(_ cell: FeedTableViewCell, animations animationBlock: () -> Void) {
        self.tableView.beginUpdates()
        animationBlock()
        self.tableView.endUpdates()

        if let postId = cell.postId, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            feedDataItem.textExpanded = true
        }
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        let commentsViewController = CommentsViewController(feedPostId: postId)
        commentsViewController.highlightedCommentId = commentId
        self.navigationController?.pushViewController(commentsViewController, animated: true)
    }

    private func showMessageView(for postId: FeedPostID) {
        if let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            self.navigationController?.pushViewController(ChatViewController(for: feedDataItem.userId, with: postId, at: Int32(feedDataItem.currentMediaIndex ?? 0)), animated: true)
        }
    }

    private func showSeenByView(for postId: FeedPostID) {
        let seenByViewController = FeedPostSeenByViewController(feedPostId: postId)
        self.present(UINavigationController(rootViewController: seenByViewController), animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userID: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    // MARK: Misc

    private func stopAllVideoPlayback() {
        for cell in tableView.visibleCells {
            if let feedTableViewCell = cell as? FeedTableViewCell {
                feedTableViewCell.stopPlayback()
            }
        }
    }

    private func refreshTimestamps() {
        guard let indexPaths = tableView.indexPathsForVisibleRows else { return }
        for indexPath in indexPaths {
            if let feedTableViewCell = tableView.cellForRow(at: indexPath) as? FeedTableViewCell,
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
                NotificationUtility.removeDelivered(forType: .feedpost, withContentId: feedPost.id)
            }
        }
    }
}


fileprivate protocol FeedTableViewCellDelegate: AnyObject {
    func feedTableViewCell(_ cell: FeedTableViewCell, didRequestOpen url: URL)
    func feedTableViewCellDidRequestReloadHeight(_ cell: FeedTableViewCell, animations animationBlock: () -> Void)
}

fileprivate class FeedTableViewCellBackgroundPanelView: UIView {

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


fileprivate class FeedTableViewCell: UITableViewCell, TextLabelDelegate {

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

    var postId: FeedPostID? = nil

    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var showUserAction: ((UserID) -> ())?

    weak var delegate: FeedTableViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var backgroundPanelView: FeedTableViewCellBackgroundPanelView = {
        let panel = FeedTableViewCellBackgroundPanelView()
        panel.cornerRadius = LayoutConstants.backgroundCornerRadius
        return panel
    }()

    private lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.preservesSuperviewLayoutMargins = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var itemContentView: FeedItemContentView = {
        let view = FeedItemContentView()
        view.preservesSuperviewLayoutMargins = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.textLabel.delegate = self
        return view
    }()

    lazy var footerView: FeedItemFooterView = {
        let view = FeedItemFooterView()
        view.preservesSuperviewLayoutMargins = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func setupView() {
        self.selectionStyle = .none
        self.backgroundColor = .clear

        // Background
        let backgroundView = UIView()
        backgroundView.preservesSuperviewLayoutMargins = true
        backgroundView.addSubview(backgroundPanelView)
        self.backgroundView = backgroundView
        self.updateBackgroundPanelShadow()

        // Content view: a vertical stack of header, content and footer.
        let vStack = UIStackView(arrangedSubviews: [ self.headerView, self.itemContentView, self.footerView ])
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -(LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV)).isActive = true

        // Separator in the footer view needs to be extended past view bounds to be the same width as background "card".
        footerView.separator.leadingAnchor.constraint(equalTo: backgroundPanelView.leadingAnchor).isActive = true
        footerView.separator.trailingAnchor.constraint(equalTo: backgroundPanelView.trailingAnchor).isActive = true

        // Connect actions of footer view buttons
        footerView.commentButton.addTarget(self, action: #selector(showComments), for: .touchUpInside)
        footerView.messageButton.addTarget(self, action: #selector(messageContact), for: .touchUpInside)
        footerView.facePileView.addTarget(self, action: #selector(showSeenBy), for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundView = self.backgroundView {
            let panelInsets = UIEdgeInsets(
                top: LayoutConstants.backgroundPanelVMargin,
                left: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.left,
                bottom: LayoutConstants.backgroundPanelVMargin,
                right: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.right)
            backgroundPanelView.frame = backgroundView.bounds.inset(by: panelInsets)
        }
    }

    public func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        DDLogVerbose("FeedTableViewCell/configure [\(post.id)]")

        self.postId = post.id
        self.headerView.configure(with: post)
        self.headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        self.itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)
        if post.isPostRetracted {
            self.footerView.isHidden = true
        } else {
            self.footerView.isHidden = false
            self.footerView.configure(with: post, contentWidth: contentWidth)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != self.traitCollection.userInterfaceStyle {
            // Shadow color needs to be updated when user interface style changes between dark and light.
            self.updateBackgroundPanelShadow()
        }
    }

    private func updateBackgroundPanelShadow() {
        self.backgroundPanelView.isShadowHidden = self.traitCollection.userInterfaceStyle == .dark
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.headerView.prepareForReuse()
        self.itemContentView.prepareForReuse()
        self.footerView.prepareForReuse()
    }

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                self.delegate?.feedTableViewCell(self, didRequestOpen: url)
            }
        case .readMoreLink:
            self.delegate?.feedTableViewCellDidRequestReloadHeight(self) {
                self.itemContentView.textLabel.numberOfLines = 0
            }
        case .userMention:
            if let userID = link.userID {
                showUserAction?(userID)
            }
        default:
            break
        }
    }

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        self.headerView.configure(with: feedPost)
    }

    // MARK: Button actions

    @objc(showComments)
    private func showComments() {
        if self.commentAction != nil {
            self.commentAction!()
        }
    }

    @objc(messageContact)
    private func messageContact() {
        if self.messageAction != nil {
            self.messageAction!()
        }
    }

    @objc(showSeenBy)
    private func showSeenBy() {
        if self.showSeenByAction != nil {
            self.showSeenByAction!()
        }
    }
}


fileprivate class FeedItemContentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ self.textContentView ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        return vStack
    }()

    private lazy var textContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.textLabel)
        self.textLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        self.textLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor).isActive = true
        self.textLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        self.textLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
        return view
    }()

    static let deletedPostViewTag = 1
    fileprivate lazy var deletedPostView: UIView = {
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
        view.tag = FeedItemContentView.deletedPostViewTag
        view.addSubview(textLabel)
        textLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        textLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        textLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
        return view
    }()

    private(set) lazy var textLabel: TextLabel = {
        let label = TextLabel()
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var mediaView: MediaCarouselView?

    private var feedPostId: FeedPostID? = nil

    private func setupView() {
        self.isUserInteractionEnabled = true
        self.layoutMargins = UIEdgeInsets(top: 5, left: 0, bottom: 8, right: 0)

        self.addSubview(self.vStack)
        self.vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        // This is the required amount of spacing between profile photo (bottom of the header view) and top of the post media.
        self.vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        guard let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: post.id) else { return }

        var reuseMediaView = false
        if let mediaView = self.mediaView {
            reuseMediaView = feedPostId == post.id && !post.isPostRetracted
            if !reuseMediaView {
                self.vStack.removeArrangedSubview(mediaView)
                mediaView.removeFromSuperview()
                self.mediaView = nil
            }
        }

        if reuseMediaView {
            DDLogInfo("FeedTableViewCell/content-view/reuse-media post=[\(post.id)]")
        }

        let postContainsMedia = !feedDataItem.media.isEmpty
        if postContainsMedia && !reuseMediaView {
            let mediaViewHeight = MediaCarouselView.preferredHeight(for: feedDataItem.media, width: contentWidth)
            var mediaViewConfiguration = MediaCarouselViewConfiguration.default
            mediaViewConfiguration.gutterWidth = gutterWidth
            let mediaView = MediaCarouselView(feedDataItem: feedDataItem, configuration: mediaViewConfiguration)
            mediaView.addConstraint({
                let constraint = NSLayoutConstraint.init(item: mediaView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: mediaViewHeight)
                constraint.priority = .defaultHigh
                return constraint
            }())
            self.vStack.insertArrangedSubview(mediaView, at: 0)
            self.mediaView = mediaView
        }

        if post.isPostRetracted {
            self.textContentView.isHidden = true

            self.deletedPostView.isHidden = false
            if !self.vStack.arrangedSubviews.contains(self.deletedPostView) {
                self.vStack.addArrangedSubview(self.deletedPostView)
            }
        }
        // With media or > 180 chars long: System 16 pt (Body - 1)
        // Text-only under 180 chars long: System 20 pt (Body + 3)
        else if !(post.text ?? "").isEmpty {
            self.textContentView.isHidden = false

            let postText = MainAppContext.shared.contactStore.textWithMentions(
                post.text,
                orderedMentions: post.orderedMentions)
            let postFont: UIFont = {
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let fontSizeDiff: CGFloat = postContainsMedia || (postText?.string ?? "").count > 180 ? -1 : 3
                return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
            }()
            self.textLabel.attributedText = postText?.with(font: postFont, color: .label)
            self.textLabel.numberOfLines = feedDataItem.textExpanded ? 0 : postContainsMedia ? 3 : 10
            // Adjust vertical margins around text.
            self.textContentView.layoutMargins.top = postContainsMedia ? 11 : 9
        } else {
            self.textContentView.isHidden = true
        }

        // Remove extra spacing
        self.layoutMargins.bottom = post.hideFooterSeparator ? 2 : 8

        feedPostId = post.id
    }

    func prepareForReuse() {
        // Hide "This post has been deleted" view.
        // Use tags so as to not trigger lazy initialization of the view.
        if let deletedPostView = self.vStack.arrangedSubviews.first(where: { $0.tag == FeedItemContentView.deletedPostViewTag }) {
            deletedPostView.isHidden = true
        }
    }

    func stopPlayback() {
        if let mediaView = self.mediaView {
            mediaView.stopPlayback()
        }
    }
}


fileprivate class FeedItemHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    var showUserAction: (() -> ())? = nil

    private lazy var contactImageView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUser)))
        return avatarView
    }()

    // Gotham Medium, 15 pt (Subhead)
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.textColor = .label
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
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private func setupView() {
        self.isUserInteractionEnabled = true
        
        self.contactImageView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true

        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.nameLabel, self.timestampLabel ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.spacing = 8
        hStack.axis = .horizontal
        self.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }

    func configure(with post: FeedPost) {
        self.nameLabel.text = MainAppContext.shared.contactStore.fullName(for: post.userId)
        self.timestampLabel.text = post.timestamp.feedTimestamp()
        self.contactImageView.configure(with: post.userId, using: MainAppContext.shared.avatarStore)
    }

    func prepareForReuse() {
        contactImageView.prepareForReuse()
    }

    @objc(showUser)
    func showUser() {
        showUserAction?()
    }

}


fileprivate class FeedItemFooterView: UIView {

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

            let spacing: CGFloat = 8
            let badgeCenterX: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? titleLabel.frame.maxX + spacing : titleLabel.frame.minX - spacing
            self.badgeView.center = self.badgeView.alignedCenter(from: CGPoint(x: badgeCenterX, y: titleLabel.frame.midY))
        }

    }

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
        let spacing: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? 8 : -8
        let button = ButtonWithBadge(type: .system)
        button.setTitle("Comment", for: .normal)
        button.setImage(UIImage(named: "FeedPostComment"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
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
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
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

    private func setupView() {
        self.isUserInteractionEnabled = true

        self.addSubview(separator)

        separator.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        // Horizontal size / position constraints will be installed by the cell.

        let hStack = UIStackView(arrangedSubviews: [ self.commentButton, self.messageButton ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.distribution = .fillEqually
        self.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true

        self.addSubview(self.facePileView)
        self.facePileView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8).isActive = true
        self.facePileView.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: 4).isActive = true
    }

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        separator.isHidden = post.hideFooterSeparator
        self.commentButton.badge = (post.comments ?? []).isEmpty ? .hidden : (post.unreadCount > 0 ? .unread : .read)
        let usersOwnPost = post.userId == MainAppContext.shared.userData.userId
        self.messageButton.alpha = usersOwnPost ? 0 : 1
        if usersOwnPost {
            self.facePileView.isHidden = false
            self.facePileView.configure(with: post)
        } else {
            self.facePileView.isHidden = true
        }
    }

    func prepareForReuse() {
        self.facePileView.prepareForReuse()
    }
}

fileprivate class FacePileView: UIControl {
    var avatarViews: [AvatarView] = []
    let numberOfFaces = 3
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        for index in 0 ..< numberOfFaces {
            // The avatars are added from right to left
            let avatarView = AvatarView()
            avatarView.backgroundColor = .secondarySystemGroupedBackground
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            
            self.addSubview(avatarView)
            avatarViews.append(avatarView)
            
            if index == 0 {
                // The rightmost avatar
                avatarView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            } else {
                let previousView = self.avatarViews[index - 1]
                avatarView.trailingAnchor.constraint(equalTo: previousView.centerXAnchor).isActive = true
            }
            
            avatarView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
            avatarView.heightAnchor.constraint(equalToConstant: 25).isActive = true
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor).isActive = true
            avatarView.isHidden = true
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
                avatarView.configure(with: usersWithAvatars[userIndex], using: MainAppContext.shared.avatarStore)
                avatarView.isHidden = false
            }
        } else { // No one has seen this post. Just show a dummy avatar.
            avatarViews.first!.isHidden = false
        }
    }

    func prepareForReuse() {
        for avatarView in avatarViews {
            avatarView.prepareForReuse()
            avatarView.isHidden = true
        }
    }
}
