//
//  FeedPostSeenByViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreData
import UIKit

class FeedPostSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    fileprivate enum TableSection: Int {
        case seen = 0
        case delivered = 1
    }

    fileprivate struct TableRow: Hashable {
        let userId: UserID
        let contactName: String?
        let timestamp: Date
    }

    static let cellReuseIdentifier = "contact-cell"

    private let feedPostId: FeedPostID

    private var dataSource: UITableViewDiffableDataSource<TableSection, TableRow>?
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

        dataSource = UITableViewDiffableDataSource<TableSection, TableRow>(tableView: self.tableView) { (tableView, indexPath, tableRow) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.text = tableRow.contactName
            if cell.imageView?.image == nil {
                cell.imageView?.image = UIImage(systemName: "person.circle")
                cell.imageView?.tintColor = .systemGray
            }
            if cell.accessoryView == nil {
                cell.accessoryView = UIImageView(image: UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate))
            }
            cell.accessoryView?.tintColor = indexPath.section == TableSection.seen.rawValue ? .systemBlue : .systemGray
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
                seenRows.append(TableRow(userId: userId, contactName: contactName!, timestamp: receipt.seenDate!))
            }
        }
        seenRows.sort(by: { $0.timestamp < $1.timestamp })

        // All other contacts go into "delivered" section.
        let deliveredRows = allContacts.map { TableRow(userId: $0.userId!, contactName: $0.fullName, timestamp: Date()) }

        var snapshot = NSDiffableDataSourceSnapshot<TableSection, TableRow>()
        snapshot.appendSections([ .seen, .delivered ])
        snapshot.appendItems(seenRows, toSection: .seen)
        snapshot.appendItems(deliveredRows, toSection: .delivered)
        dataSource?.apply(snapshot, animatingDifferences: self.viewIfLoaded?.window != nil)
    }

}
