//
//  FeedTableView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import SwiftUI
import UIKit

fileprivate enum FeedTableSection {
    case main
}

class FeedTableViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "FeedTableViewCell"

    private var isOnProfilePage: Bool = false
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>?

    private var cancellableSet: Set<AnyCancellable> = []

    init(isOnProfilePage: Bool) {
        self.isOnProfilePage = isOnProfilePage
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func dismantle() {
        DDLogInfo("FeedTableViewController/dismantle")
        self.cancellableSet.forEach{ $0.cancel() }
        self.cancellableSet.removeAll()
    }

    override func viewDidLoad() {
        DDLogInfo("FeedTableViewController/viewDidLoad")
        // Initial width so that layout constraints aren't upset during setup.
        let tableWidth = self.view.frame.size.width
        self.tableView.backgroundColor = UIColor.systemGroupedBackground
        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = false
        self.tableView.register(FeedTableViewCell.self, forCellReuseIdentifier: FeedTableViewController.cellReuseIdentifier)

        if self.isOnProfilePage {
            let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
            headerView.frame.size.height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
            self.tableView.tableHeaderView = headerView
        }

        self.setupFetchedResultsController()

        self.cancellableSet.insert(AppContext.shared.feedData.willDestroyStore.sink {
            self.fetchedResultsController = nil
            self.tableView.reloadData()
            self.view.isUserInteractionEnabled = false
        })

        self.cancellableSet.insert(AppContext.shared.feedData.didReloadStore.sink {
            self.view.isUserInteractionEnabled = true
            self.setupFetchedResultsController()
            self.tableView.reloadData()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("FeedTableViewController/viewWillAppear")
        super.viewWillAppear(animated)
//        self.tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("FeedTableViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

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
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        if self.isOnProfilePage {
            fetchRequest.predicate = NSPredicate(format: "userId == %@", AppContext.shared.userData.userId)
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.feedData.viewContext,
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
                self.tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .automatic)
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
                self.tableView.reloadRows(at: [ indexPath ], with: .automatic)
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
            cell.configure(with: feedPost, contentWidth: contentWidth)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let feedPost = fetchedResultsController?.object(at: indexPath) {
            // Load downloaded images into memory.
            AppContext.shared.feedData.feedDataItem(with: feedPost.id)?.loadImages()

            // Initiate download for images that were not yet downloaded.
            AppContext.shared.feedData.downloadMedia(in: [ feedPost ])
        }
    }
}


fileprivate class FeedTableViewCell: UITableViewCell {
    static let backgroundCornerRadius: CGFloat = 15
    /**
     Content view (vertical stack takes standard table view content width: tableView.width - tableView.layoutMargins.left - tableView.layoutMargins.right
     Width of the background "card" is defined as: leftOutset + contentWidth + rightOutset. Margins around background "card" vary: 10 pt for plus screen devices, 8 pt for all others.
     */
    static let backgroundPanelViewOutsetH: CGFloat = 8
    static let backgroundPanelViewOutsetV: CGFloat = 8
    /**
     In contrast with horizontal margins, vertical margins are defined relative to cell's top and bottom edges.
     Background "card" has 25 pt margins on top and bottom (so that space between cards is 50 pt).
     Content is further inset 8 points relative to the card's top and bottom edges.
     */
    static let backgroundPanelVMargin: CGFloat = 25

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var backgroundPanelView: UIView = {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = FeedTableViewCell.backgroundCornerRadius
        panel.layer.shadowColor = UIColor.systemGray5.cgColor
        panel.layer.shadowRadius = 5
        panel.layer.shadowOpacity = 1
        panel.layer.shadowOffset = .zero
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
        return view
    }()

    private lazy var footerView: FeedItemFooterView = {
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
        backgroundView.addSubview(self.backgroundPanelView)
        backgroundView.preservesSuperviewLayoutMargins = true
        backgroundView.addConstraint({
            let constraint = self.backgroundPanelView.leadingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.leadingAnchor, constant: -FeedTableViewCell.backgroundPanelViewOutsetH)
            constraint.priority = .defaultHigh
            return constraint
            }())
        backgroundView.addConstraint({
            let constraint = self.backgroundPanelView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: FeedTableViewCell.backgroundPanelVMargin)
            constraint.priority = .defaultHigh
            return constraint
            }())
        backgroundView.addConstraint({
            let constraint = self.backgroundPanelView.trailingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.trailingAnchor, constant: FeedTableViewCell.backgroundPanelViewOutsetH)
            constraint.priority = .defaultHigh
            return constraint
            }())
        backgroundView.addConstraint({
            let constraint = self.backgroundPanelView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -FeedTableViewCell.backgroundPanelVMargin)
            constraint.priority = .defaultHigh
            return constraint
            }())
        self.backgroundPanelView.backgroundColor = UIColor.secondarySystemGroupedBackground
        self.backgroundView = backgroundView

        // Content view: a vertical stack of header, content and footer.
        let vStack = UIStackView(arrangedSubviews: [ self.headerView, self.itemContentView, self.footerView ])
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: FeedTableViewCell.backgroundPanelVMargin + FeedTableViewCell.backgroundPanelViewOutsetV).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -(FeedTableViewCell.backgroundPanelVMargin + FeedTableViewCell.backgroundPanelViewOutsetV)).isActive = true
    }

    public func configure(with post: FeedPost, contentWidth: CGFloat) {
        self.headerView.configure(with: post, contentWidth: contentWidth)
        self.itemContentView.configure(with: post, contentWidth: contentWidth)
        if post.isPostDeleted {
            self.footerView.isHidden = true
        } else {
            self.footerView.isHidden = false
            self.footerView.configure(with: post, contentWidth: contentWidth)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.headerView.prepareForReuse()
        self.itemContentView.prepareForReuse()
        self.footerView.prepareForReuse()
        // Shadow color needs to be updated when user interface style changes between dark and light.
        self.backgroundPanelView.layer.shadowColor = UIColor.systemGray5.cgColor
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
        view.layoutMargins.bottom = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.textLabel)
        self.textLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        self.textLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor).isActive = true
        self.textLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        self.textLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
        return view
    }()

    static let deletedPostViewTag = 1
    private lazy var deletedPostView: UIView = {
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textAlignment = .center
        textLabel.textColor = .secondaryLabel
        textLabel.text = "This post has been deleted"
        textLabel.font = {
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSymbolicTraits(.traitItalic)!
            return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + 3)
        }()
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

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var mediaView: UIView?

    private func setupView() {
        self.isUserInteractionEnabled = true

        self.addSubview(self.vStack)
        self.vStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        // This is the required amount of spacing between profile photo (bottom of the header view) and top of the post media.
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 5).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8).isActive = true
    }

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: post.id) else { return }
        // TODO: This is a hack that needs to be improved.
        var mediaHeight = feedDataItem.mediaHeight(for: contentWidth)
        if mediaHeight > 0 {
            DDLogDebug("FeedTableViewCell/configure [\(feedDataItem.id)]")
            // Extra space for page indicator dots.
            if feedDataItem.media.count > 1 {
                mediaHeight += MediaSlider.pageIndicatorHeight
            }
            let controller = UIHostingController(rootView: MediaSlider(feedDataItem).frame(height: mediaHeight))
            controller.view.backgroundColor = .clear
            controller.view.addConstraint({
                let constraint = NSLayoutConstraint.init(item: controller.view!, attribute: .height, relatedBy: .equal,
                                                         toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: mediaHeight)
                constraint.priority = .defaultHigh + 10
                return constraint
            }())

            self.vStack.insertArrangedSubview(controller.view, at: 0)
            self.mediaView = controller.view
        }

        if post.isPostDeleted {
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

            self.textLabel.text = post.text
            self.textLabel.font = {
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let fontSizeDiff: CGFloat = mediaHeight > 0 || (self.textLabel.text ?? "").count > 180 ? -1 : 3
                return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
            }()
            self.textLabel.numberOfLines = mediaHeight > 0 ? 3 : 10
            // Adjust vertical margins around text.
            self.textContentView.layoutMargins.top = mediaHeight > 0 ? 11 : 9
        } else {
            self.textContentView.isHidden = true
        }
    }

    func prepareForReuse() {
        if let mediaView = self.mediaView {
            self.vStack.removeArrangedSubview(mediaView)
            mediaView.removeFromSuperview()
            self.mediaView = nil
        }
        // Hide "This post has been deleted" view.
        // Use tags so as to not trigger lazy initialization of the view.
        if let deletedPostView = self.vStack.arrangedSubviews.first(where: { $0.tag == FeedItemContentView.deletedPostViewTag }) {
            deletedPostView.isHidden = true
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

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()

    // Gotham Medium, 15 pt (Subhead)
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = {
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            return UIFont.systemFont(ofSize: fontDescriptor.pointSize, weight: .medium)
        }()
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        return label
    }()

    // Gotham Medium, 14 pt (Footnote + 1)
    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = {
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
            return UIFont.systemFont(ofSize: fontDescriptor.pointSize + 1, weight: .medium)
        }()
        label.textColor = .secondaryLabel
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

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        self.nameLabel.text = AppContext.shared.contactStore.fullName(for: post.userId)
        self.timestampLabel.text = post.timestamp.postTimestamp()
    }

    func prepareForReuse() {
        
    }
}


fileprivate class FeedItemFooterView: UIView {
    private var buttonsView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.isUserInteractionEnabled = true

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(separator)
        separator.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -FeedTableViewCell.backgroundPanelViewOutsetH).isActive = true
        separator.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: FeedTableViewCell.backgroundPanelViewOutsetH).isActive = true
        separator.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    }

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: post.id) else { return }
        let controller = UIHostingController(rootView: FeedItemFooterButtonsView(feedDataItem: feedDataItem))
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(controller.view)
        controller.view.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        controller.view.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        controller.view.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        controller.view.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        let viewHeight = controller.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        controller.view.heightAnchor.constraint(equalToConstant: viewHeight).isActive = true
        self.buttonsView = controller.view
        // WARNING: Retaining UIHostingController instead of its view breaks NavigationLink.
    }

    func prepareForReuse() {
        if let buttonsView = self.buttonsView {
            buttonsView.removeFromSuperview()
            self.buttonsView = nil
        }
    }
}


fileprivate class FeedTableHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = UIColor.label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = AppContext.shared.userData.name
        return label
    }()
    
    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = UIColor.label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = AppContext.shared.userData.phone
        return label
    }()

    private func setupView() {
        let vStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.nameLabel, self.textLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 8
        vStack.axis = .vertical
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        contactImageView.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }
}

/**
 * Implement buttons in the feed item card because of NavigationLink.
 */
fileprivate struct FeedItemFooterButtonsView: View {
    private var feedDataItem: FeedDataItem
    @State private var showMessageView = false
    @State private var hasComments = false
    @State private var hasUnreadComments = false
    @State private var isNavigationLinkActive = false

    init(feedDataItem: FeedDataItem) {
        self.feedDataItem = feedDataItem
        self._hasComments = State(wrappedValue: feedDataItem.numberOfComments > 0)
        self._hasUnreadComments = State(wrappedValue: feedDataItem.hasUnreadComments)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Comment button
            NavigationLink(destination: CommentsView(feedPostId: self.feedDataItem.id).navigationBarTitle("Comments", displayMode: .inline).edgesIgnoringSafeArea(.bottom)) {
                VStack {
                    HStack {
                        Image(systemName: "message")
                            .font(.system(size: 20, weight: .regular))

                        Text("Comment")
                            .font(Font.system(.subheadline).weight(.medium))
                            // Green Dot if there are unread comments
                            .overlay (
                                Image(systemName: "circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(self.hasUnreadComments ? Color.green : (self.hasComments ? Color(UIColor.systemGray4) : Color.clear))
                                    .frame(width: 10, height: 10, alignment: .center)
                                    .offset(x: 17)
                                , alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(EdgeInsets(top: 15, leading: 20, bottom: 9, trailing: 24))
                }
            }

            // Message button
            if (AppContext.shared.userData.userId != self.feedDataItem.userId) {
                Spacer()

                Button(action: { self.showMessageView = true }) {
                    VStack {
                        HStack {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .regular))

                            Text("Message")
                                .font(Font.system(.subheadline).weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(EdgeInsets(top: 15, leading: 24, bottom: 9, trailing: 20))
                    }
                }
                .sheet(isPresented: self.$showMessageView) {
                    MessageUser(isViewPresented: self.$showMessageView)
                }
            }
        }
        .foregroundColor(.primary)
        .onReceive(self.feedDataItem.commentsDidChange) { (numberOfComments, hasUnreadComments) in
            self.hasComments = numberOfComments > 0
            self.hasUnreadComments = hasUnreadComments
        }
    }
}
