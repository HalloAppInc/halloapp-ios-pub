//
//  FeedTableView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import SwiftUI
import UIKit

enum FeedTableSection {
    case main
}

class FeedTableViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "FeedTableViewCell"

    private var isOnProfilePage: Bool = false
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>?

    init(isOnProfilePage: Bool) {
        self.isOnProfilePage = isOnProfilePage
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func dismantle() {
        DDLogInfo("FeedTableViewController/dismantle")
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

        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        if self.isOnProfilePage {
            fetchRequest.predicate = NSPredicate(format: "userId == %@", AppContext.shared.userData.phone)
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        self.fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.feedData.viewContext,
                                                                             sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
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
            // Do nothing for now because the only thing that updates is "unread comments" indicator,
            // and those updates are driven by SwiftUI.

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
            cell.configure(with: feedPost)
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


class FeedTableViewCell: UITableViewCell {
    static let backgroundCornerRadius: CGFloat = 10

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
        self.backgroundColor = UIColor.clear

        let padding: CGFloat = 8

        // Background
        let backgroundView = UIView()
        backgroundView.addSubview(self.backgroundPanelView)
        let views = [ "panel": self.backgroundPanelView ]
        let metrics = [ "padding": padding ]
        // Priority isn't "required" because view is created with zero frame and that causes UIViewAlertForUnsatisfiableConstraints.
        backgroundView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-padding@750-[panel]-padding@750-|", options: .directionLeadingToTrailing, metrics: metrics, views: views))
        backgroundView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-padding@750-[panel]-padding@750-|", options: [], metrics: metrics, views: views))
        self.backgroundPanelView.backgroundColor = UIColor.secondarySystemGroupedBackground
        self.backgroundView = backgroundView

        let vStack = UIStackView(arrangedSubviews: [ self.headerView, self.itemContentView, self.footerView ])
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: padding).isActive = true
        vStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: padding).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -padding).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -padding).isActive = true
    }

    public func configure(with post: FeedPost) {
        self.headerView.configure(with: post)
        self.itemContentView.configure(with: post)
        self.footerView.configure(with: post)
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


class FeedItemContentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ self.textLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 8
        vStack.axis = .vertical
        return vStack
    }()

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = UIColor.label
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var mediaView: UIView?

    private func setupView() {
        self.isUserInteractionEnabled = true

        self.addSubview(self.vStack)
        self.vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor, constant: 4).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 4).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor, constant: -4).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -12).isActive = true
    }

    func configure(with post: FeedPost) {
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: post.id) else { return }
        // TODO: This is a hack that needs to be improved.
        let width = self.frame != .zero ? self.frame.size.width : UIScreen.main.bounds.size.width - 8*4
        let mediaHeight = feedDataItem.mediaHeight(for: width)
        if mediaHeight > 0 {
            DDLogDebug("FeedTableViewCell/configure [\(feedDataItem.id)]")
            let controller = UIHostingController(rootView: MediaSlider(feedDataItem).frame(height: mediaHeight))
            controller.view.backgroundColor = UIColor.clear
            controller.view.addConstraint({
                let constraint = NSLayoutConstraint.init(item: controller.view!, attribute: .height, relatedBy: .equal,
                                                         toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: mediaHeight)
                constraint.priority = .defaultHigh + 10
                return constraint
            }())

            self.vStack.insertArrangedSubview(controller.view, at: 0)
            self.mediaView = controller.view
        }

        self.textLabel.text = post.text
    }

    func prepareForReuse() {
        if let mediaView = self.mediaView {
            self.vStack.removeArrangedSubview(mediaView)
            mediaView.removeFromSuperview()
            self.mediaView = nil
        }
    }
}


class FeedItemHeaderView: UIView {
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
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        return label
    }()

    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor.secondaryLabel
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
        hStack.spacing = 10
        hStack.axis = .horizontal
        self.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor, constant: 4).isActive = true
        hStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor, constant: -4).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    func configure(with post: FeedPost) {
        self.nameLabel.text = AppContext.shared.contactStore.fullName(for: post.userId)
        self.timestampLabel.text = post.timestamp.postTimestamp()
    }

    func prepareForReuse() {
        
    }
}


class FeedItemFooterView: UIView {
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
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(separator)
        separator.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        separator.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    }

    func configure(with post: FeedPost) {
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: post.id) else { return }
        let controller = UIHostingController(rootView: FeedItemFooterButtonsView(feedDataItem: feedDataItem))
        controller.view.backgroundColor = UIColor.clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(controller.view)
        controller.view.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        controller.view.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        controller.view.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
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


class FeedTableHeaderView: UIView {
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
        let vStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.textLabel ])
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
struct FeedItemFooterButtonsView: View {
    private var feedDataItem: FeedDataItem
    @State private var showMessageView = false
    @State private var hasUnreadComments = false
    @State private var isNavigationLinkActive = false

    init(feedDataItem: FeedDataItem) {
        self.feedDataItem = feedDataItem
        self._hasUnreadComments = State(wrappedValue: feedDataItem.unreadComments > 0)
    }

    var body: some View {
        HStack {
            // Comment button
            NavigationLink(destination: CommentsView(feedPostId: self.feedDataItem.id).navigationBarTitle("Comments", displayMode: .inline).edgesIgnoringSafeArea(.bottom)) {
                HStack {
                    Image(systemName: "message")
                        .font(.system(size: 20, weight: .regular))

                    Text("Comment")
                        .font(.system(.body))

                    // Green Dot if there are unread comments
                    if (self.hasUnreadComments) {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color.green)
                            .clipShape(Circle())
                            .frame(width: 10, height: 10, alignment: .center)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }

            // Message button
            if (AppContext.shared.userData.phone != self.feedDataItem.username) {
                Spacer()

                Button(action: { self.showMessageView = true }) {
                    HStack {
                        Image(systemName: "envelope")
                            .font(.system(size: 20, weight: .regular))

                        Text("Message")
                            .font(.system(.body))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
                .sheet(isPresented: self.$showMessageView) {
                    MessageUser(isViewPresented: self.$showMessageView)
                }
            }
        }
        .foregroundColor(Color.primary)
        .padding(.all, 10)
        .onReceive(self.feedDataItem.commentsChange) { number in
            self.hasUnreadComments = number > 0
        }
    }
}
