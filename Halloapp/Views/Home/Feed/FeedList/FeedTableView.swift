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

struct FeedTableView: UIViewRepresentable {
    private static let cellReuseIdentifier = "FeedTableViewCell"

    @EnvironmentObject var mainViewController: MainViewController

    var isOnProfilePage: Bool

    func makeUIView(context: Context) -> UITableView {
        // Initial width so that layout constraints aren't upset during setup.
        let tableWidth = UIScreen.main.bounds.size.width
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth), style: .plain)
        tableView.backgroundColor = UIColor.systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.delegate = context.coordinator
        tableView.preservesSuperviewLayoutMargins = true

        if self.isOnProfilePage {
            let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
            headerView.frame.size = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            tableView.tableHeaderView = headerView
        }

        tableView.register(FeedTableViewCell.self, forCellReuseIdentifier: FeedTableView.cellReuseIdentifier)
        let dataSource = UITableViewDiffableDataSource<FeedTableSection, FeedDataItem>(tableView: tableView) { (tableView, indexPath, feedDataItem) in
            let cell = tableView.dequeueReusableCell(withIdentifier: FeedTableView.cellReuseIdentifier, for: indexPath) as! FeedTableViewCell
            cell.configure(with: feedDataItem)
            return cell
        }

        let fetchRequest = NSFetchRequest<FeedCore>(entityName: FeedCore.entity().name!)
        if self.isOnProfilePage {
            fetchRequest.predicate = NSPredicate(format: "username == %@", AppContext.shared.userData.phone)
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedCore.timestamp, ascending: false) ]
        let fetchedResultsController =
            NSFetchedResultsController<FeedCore>(fetchRequest: fetchRequest,
                                                 managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
                                                 sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = context.coordinator
        do {
            try fetchedResultsController.performFetch()
            if let feedItems = fetchedResultsController.fetchedObjects {
                self.update(dataSource: dataSource, with: feedItems, animatingDifferences: false)
            }
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }

        context.coordinator.dataSource = dataSource
        context.coordinator.fetchedResultsController = fetchedResultsController
        context.coordinator.tableView = tableView

        return tableView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {
        uiView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: BottomBarView.currentBarHeight(), right: 0)
        uiView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: BottomBarView.currentBarHeight(), right: 0)
        // reloadData() is only necessary to reload shadow color in table view cells on interface style change (dark <-> light).
        uiView.reloadData()
    }

    private func update(dataSource: UITableViewDiffableDataSource<FeedTableSection, FeedDataItem>,
                        with feedItems: [FeedCore], animatingDifferences: Bool = true) {
        // FIXME: this is a bad bad code.
        let feedPostIds: Set<String> = Set(feedItems.compactMap({ $0.itemId }))
        let feedDataItems = AppContext.shared.feedData.feedDataItems.filter { feedPostIds.contains($0.itemId) }
        var snapshot = NSDiffableDataSourceSnapshot<FeedTableSection, FeedDataItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(feedDataItems)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }


    class Coordinator: NSObject, UITableViewDelegate, NSFetchedResultsControllerDelegate {
        var parent: FeedTableView
        var dataSource: UITableViewDiffableDataSource<FeedTableSection, FeedDataItem>?
        var fetchedResultsController: NSFetchedResultsController<FeedCore>?
        var tableView: UITableView?

        init(_ view: FeedTableView) {
            self.parent = view
        }

        /**
         This property prevents table view data from being reloaded when invidual feed objects change because that would be a no-op.
         */
        private var reloadDataInDidChangeContent = false
        func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
            DDLogDebug("FeedTableView/fetched-results-controller/will-change")
            reloadDataInDidChangeContent = false
        }

        func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
            DDLogDebug("FeedTableView/fetched-results-controller/change type=[\(type.rawValue)]")
            switch type {
            case .delete, .insert, .move:
                DDLogDebug("FeedTableView/fetched-results-controller/\(type.rawValue) object=[\(anObject)]")
                reloadDataInDidChangeContent = true
            default:
                DDLogDebug("FeedTableView/fetched-results-controller/update object=[\(anObject)]")
                break
            }
        }

        func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
            DDLogDebug("FeedTableView/fetched-results-controller/did-change reload=[\(reloadDataInDidChangeContent)]")
            guard reloadDataInDidChangeContent else { return }
            guard let dataSource = self.dataSource else { return }
            if let feedItems = controller.fetchedObjects {
                // Animating changes while the view is off-screen causes weird layout glitches.
                let animate = tableView?.window != nil && UIApplication.shared.applicationState == .active
                self.parent.update(dataSource: dataSource, with: feedItems as! [FeedCore], animatingDifferences: animate)
            }
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let fetchedObjects = fetchedResultsController?.fetchedObjects else { return }
            guard indexPath.row < fetchedObjects.count else { return }
            AppContext.shared.feedData.getItemMedia(fetchedObjects[indexPath.row].itemId!)
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

    public func configure(with item: FeedDataItem) {
        self.headerView.configure(with: item)
        self.itemContentView.configure(with: item)
        self.footerView.configure(with: item)
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

    func configure(with feedDataItem: FeedDataItem) {
        if let mediaHeight = feedDataItem.mediaHeight {
            DDLogDebug("FeedTableViewCell/configure [\(feedDataItem.itemId)]")
            let controller = UIHostingController(rootView: MediaSlider(feedDataItem))
            controller.view.backgroundColor = UIColor.clear
            controller.view.addConstraint({
                let constraint = NSLayoutConstraint.init(item: controller.view!, attribute: .height, relatedBy: .equal,
                                                         toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: CGFloat(mediaHeight))
                constraint.priority = .defaultHigh + 10
                return constraint
            }())
            // This is important to set frame at this point, otherwise UICollectionView within gets corrupted.
            controller.view.frame.size = CGSize(width: self.vStack.frame.size.width, height: CGFloat(mediaHeight))

            self.vStack.insertArrangedSubview(controller.view, at: 0)
            self.mediaView = controller.view
        }

        self.textLabel.text = feedDataItem.text
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

    func configure(with feedDataItem: FeedDataItem) {
        self.nameLabel.text = AppContext.shared.contactStore.fullName(for: feedDataItem.username)
        self.timestampLabel.text = feedDataItem.timestamp.postTimestamp()
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

    func configure(with feedDataItem: FeedDataItem) {
        let controller = UIHostingController(rootView: FeedItemFooterButtonsView(feedDataItem: feedDataItem))
        controller.view.backgroundColor = UIColor.clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(controller.view)
        controller.view.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        controller.view.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        controller.view.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        controller.view.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
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
            NavigationLink(destination: CommentsView(itemId: self.feedDataItem.itemId).navigationBarTitle("Comments", displayMode: .inline).edgesIgnoringSafeArea(.bottom)) {
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
