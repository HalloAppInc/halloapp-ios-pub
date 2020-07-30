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

struct SeenByUser {
    let userId: UserID
    let postStatus: PostStatus
    let contactName: String?
    let timestamp: Date
}

extension SeenByUser : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(postStatus)
        hasher.combine(contactName)
    }
}

extension SeenByUser : Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.postStatus == rhs.postStatus && lhs.userId == rhs.userId && lhs.contactName == rhs.contactName
    }
}

class FeedPostSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    static let cellReuseIdentifier = "contact-cell"

    private let feedPostId: FeedPostID

    private var dataSource: UITableViewDiffableDataSource<PostStatus, SeenByUser>?
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
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        self.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        self.tableView.allowsSelection = false
        self.tableView.separatorStyle = .none

        dataSource = UITableViewDiffableDataSource<PostStatus, SeenByUser>(tableView: self.tableView) { (tableView, indexPath, tableRow) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            
            cell.configureForSeenBy(with: tableRow.userId, name: tableRow.contactName!, status: tableRow.postStatus, using: MainAppContext.shared.avatarStore)

            return cell
        }

        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
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
        let allContacts = AppContext.shared.contactStore.allRegisteredContacts(sorted: true)
        let seenRows: [SeenByUser] = MainAppContext.shared.feedData.seenByUsers(for: feedPost)

        var addedUserIds = Set(seenRows.map(\.userId))

        // Hide self.
        addedUserIds.insert(AppContext.shared.userData.userId)

        // All other contacts go into "delivered" section.
        var deliveredRows: [SeenByUser] = []
        allContacts.forEach { (abContact) in
            if addedUserIds.insert(abContact.userId!).inserted {
                deliveredRows.append(SeenByUser(userId: abContact.userId!, postStatus: .delivered, contactName: abContact.fullName, timestamp: Date()))
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<PostStatus, SeenByUser>()
        snapshot.appendSections([ .seen, .delivered ])
        snapshot.appendItems(seenRows, toSection: .seen)
        snapshot.appendItems(deliveredRows, toSection: .delivered)
        dataSource?.apply(snapshot, animatingDifferences: self.viewIfLoaded?.window != nil)
    }

}
