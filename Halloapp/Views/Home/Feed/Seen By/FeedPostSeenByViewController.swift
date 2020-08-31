//
//  FeedPostSeenByViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

struct FeedPostReceipt {
    enum ReceiptType: Int {
        case seen = 0
        case delivered = 1
    }

    let userId: UserID
    let type: ReceiptType
    let contactName: String?
    let phoneNumber: String?
    let timestamp: Date
}

extension FeedPostReceipt : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(type)
    }
}

extension FeedPostReceipt : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.userId == rhs.userId && lhs.type == rhs.type
    }
}

fileprivate extension ContactTableViewCell {

    func configureWithReceipt(_ receipt: FeedPostReceipt, using avatarStore: AvatarStore) {
        contactImage.configure(with: receipt.userId, using: avatarStore)

        nameLabel.text = receipt.contactName
        subtitleLabel.text = receipt.phoneNumber
    }
}

fileprivate class SectionHeaderView: UITableViewHeaderFooterView {

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    var sectionNameLabel: UILabel!

    private func commonInit() {
        directionalLayoutMargins.top = 16
        directionalLayoutMargins.bottom = 16

        let view = UIView(frame: bounds)
        view.backgroundColor = .feedBackground
        backgroundView = view

        sectionNameLabel = UILabel()
        sectionNameLabel.textColor = .label
        sectionNameLabel.font = UIFont.gothamFont(forTextStyle: .headline, weight: .medium)
        sectionNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sectionNameLabel)
        sectionNameLabel.constrainMargins(to: contentView)
    }
}

fileprivate class PostReceiptsDataSource: UITableViewDiffableDataSource<FeedPostReceipt.ReceiptType, FeedPostReceipt> {

}

class FeedPostSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private struct Constants {
        static let cellReuseIdentifier = "contact-cell"
        static let headerReuseIdentifier = "header"
    }

    private let feedPostId: FeedPostID

    private var dataSource: PostReceiptsDataSource!
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>!

    required init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "Your Post"
        navigationItem.standardAppearance = .opaqueAppearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarTrashBinWithLid"), style: .plain, target: self, action: #selector(retractPostAction))

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: Constants.headerReuseIdentifier)
        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        dataSource = PostReceiptsDataSource(tableView: tableView) { (tableView, indexPath, receipt) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.configureWithReceipt(receipt, using: MainAppContext.shared.avatarStore)
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            if let feedPost = fetchedResultsController.fetchedObjects?.first {
                reloadData(from: feedPost)
            }
        }
        catch {
            fatalError("Failed to fetch feed post. \(error)")
        }
    }

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    // MARK: Deleting Post

    @objc private func retractPostAction() {
        let actionSheet = UIAlertController(title: nil, message: "Delete this post? This action cannot be undone.", preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Delete Post", style: .destructive) { _ in
            self.reallyRetractPost()
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
    }

    private func reallyRetractPost() {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) else {
            dismiss(animated: true)
            return
        }
        // Stop processing data changes because all post is about to be deleted.
        fetchedResultsController.delegate = nil
        MainAppContext.shared.feedData.retract(post: feedPost)
        dismiss(animated: true)
    }

    // MARK: Table View Support

    private func titleForHeader(inSection section: Int) -> String? {
        guard let receiptType = FeedPostReceipt.ReceiptType(rawValue: section) else { return nil }
        switch receiptType  {
        case .seen:
            return "Viewed by"

        case .delivered:
            return "Delivered to"
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        var headerView: SectionHeaderView! = tableView.dequeueReusableHeaderFooterView(withIdentifier: Constants.headerReuseIdentifier) as? SectionHeaderView
        if headerView == nil {
            headerView = SectionHeaderView(reuseIdentifier: Constants.headerReuseIdentifier)
        }
        headerView.directionalLayoutMargins.top = section > 0 ? 32 : 16
        headerView.sectionNameLabel.text = titleForHeader(inSection: section)
        return headerView
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let feedPost = controller.fetchedObjects?.last as? FeedPost {
            reloadData(from: feedPost)
        }
    }

    private func reloadData(from feedPost: FeedPost) {
        let allContacts: [ABContact]
        // Only use userIds from receipts if privacy list was actually saved into feedPost.info.
        if let receiptUserIds = feedPost.info?.receipts?.keys, feedPost.info?.privacyListType != nil {
            allContacts = MainAppContext.shared.contactStore.sortedContacts(withUserIds: Array(receiptUserIds))
        } else {
            allContacts = MainAppContext.shared.contactStore.allInNetworkContacts(sorted: true)
        }

        let seenRows: [FeedPostReceipt] = MainAppContext.shared.feedData.seenByUsers(for: feedPost)

        var addedUserIds = Set(seenRows.map(\.userId))

        // Hide self.
        addedUserIds.insert(AppContext.shared.userData.userId)

        // All other contacts go into "delivered" section.
        var deliveredRows = [FeedPostReceipt]()
        allContacts.forEach { (abContact) in
            if addedUserIds.insert(abContact.userId!).inserted {
                deliveredRows.append(FeedPostReceipt(userId: abContact.userId!, type: .delivered, contactName: abContact.fullName, phoneNumber: abContact.phoneNumber, timestamp: Date()))
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<FeedPostReceipt.ReceiptType, FeedPostReceipt>()
        snapshot.appendSections([ .seen, .delivered ])
        snapshot.appendItems(seenRows, toSection: .seen)
        snapshot.appendItems(deliveredRows, toSection: .delivered)
        dataSource?.apply(snapshot, animatingDifferences: viewIfLoaded?.window != nil)
    }

}
