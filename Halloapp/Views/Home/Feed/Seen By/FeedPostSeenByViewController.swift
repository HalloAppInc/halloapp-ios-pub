//
//  FeedPostSeenByViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreData
import UIKit

fileprivate enum PostStatus: Int {
    case seen = 0
    case delivered = 1
}

fileprivate struct TableRow {
    let userId: UserID
    let postStatus: PostStatus
    let contactName: String?
    let timestamp: Date
}

extension TableRow : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(postStatus)
        hasher.combine(contactName)
    }
}

extension TableRow : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.postStatus == rhs.postStatus && lhs.userId == rhs.userId && lhs.contactName == rhs.contactName
    }
}

class FeedPostSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    static let cellReuseIdentifier = "contact-cell"

    private let feedPostId: FeedPostID

    private var dataSource: UITableViewDiffableDataSource<PostStatus, TableRow>?
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>?

    required init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = "Viewed by"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))

        self.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        self.tableView.allowsSelection = false
        self.tableView.separatorStyle = .none

        dataSource = UITableViewDiffableDataSource<PostStatus, TableRow>(tableView: self.tableView) { (tableView, indexPath, tableRow) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.text = tableRow.contactName
            if cell.imageView?.image == nil {
                cell.imageView?.image = UIImage(systemName: "person.circle")
                cell.imageView?.tintColor = .systemGray
            }
            let showDoubleBlueCheck = tableRow.postStatus == .seen
            let checkmarkImage = UIImage(named: showDoubleBlueCheck ? "CheckmarkDouble" : "CheckmarkSingle")?.withRenderingMode(.alwaysTemplate)
            if let imageView = cell.accessoryView as? UIImageView {
                imageView.image = checkmarkImage
                imageView.sizeToFit()
            } else {
                cell.accessoryView = UIImageView(image: checkmarkImage)
            }
            cell.accessoryView?.tintColor = showDoubleBlueCheck ? .systemBlue : .systemGray
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.feedData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController?.delegate = self
        do {
            try fetchedResultsController?.performFetch()
            if let feedPost = fetchedResultsController?.fetchedObjects?.first {
                reloadData(from: feedPost)
            }
        }
        catch {
            fatalError("Failed to fetch feed post. \(error)")
        }
    }

    @objc(dismiss)
    private func closeAction() {
        self.dismiss(animated: true)
    }

    // MARK: Table View Support

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let feedPost = controller.fetchedObjects?.last as? FeedPost {
            reloadData(from: feedPost)
        }
    }

    private func reloadData(from feedPost: FeedPost) {
        var allContacts = AppContext.shared.contactStore.allRegisteredContacts(sorted: true)

        // Contacts that have seen the post go into the first section.
        var seenRows: [TableRow] = []
        if let seenReceipts = feedPost.info?.receipts {
            for (userId, receipt) in seenReceipts {
                var contactName: String?
                if let contactIndex = allContacts.firstIndex(where: { $0.userId == userId }) {
                    contactName = allContacts[contactIndex].fullName
                    allContacts.remove(at: contactIndex)
                }
                if contactName == nil {
                    contactName = AppContext.shared.contactStore.fullName(for: userId)
                }
                seenRows.append(TableRow(userId: userId, postStatus: .seen, contactName: contactName!, timestamp: receipt.seenDate!))
            }
        }
        seenRows.sort(by: { $0.timestamp < $1.timestamp })

        var addedUserIds = Set(seenRows.map(\.userId))

        // Hide self.
        addedUserIds.insert(AppContext.shared.userData.userId)

        // All other contacts go into "delivered" section.
        var deliveredRows: [TableRow] = []
        allContacts.forEach { (abContact) in
            if addedUserIds.insert(abContact.userId!).inserted {
                deliveredRows.append(TableRow(userId: abContact.userId!, postStatus: .delivered, contactName: abContact.fullName, timestamp: Date()))
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<PostStatus, TableRow>()
        snapshot.appendSections([ .seen, .delivered ])
        snapshot.appendItems(seenRows, toSection: .seen)
        snapshot.appendItems(deliveredRows, toSection: .delivered)
        dataSource?.apply(snapshot, animatingDifferences: self.viewIfLoaded?.window != nil)
    }

}
