//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CoreData
import UIKit

class NotificationsViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    private static let cellReuseIdentifier = "NotificationsTableViewCell"

    private var dataSource: UITableViewDiffableDataSourceReference?
    private var fetchedResultsController: NSFetchedResultsController<FeedNotification>?

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = "Notifications"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))

        self.tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationsViewController.cellReuseIdentifier)
        self.tableView.separatorStyle = .none

        self.dataSource = UITableViewDiffableDataSourceReference(tableView: self.tableView) { tableView, indexPath, objectID in
            let cell = tableView.dequeueReusableCell(withIdentifier: NotificationsViewController.cellReuseIdentifier, for: indexPath) as! NotificationTableViewCell
            cell.selectionStyle = .none
            if let notification = try? AppContext.shared.feedData.viewContext.existingObject(with: objectID as! NSManagedObjectID) as? FeedNotification {
                cell.configure(with: notification)
            }
            return cell
        }

        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedNotification>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.feedData.viewContext,
                                                         sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
        } catch {
            return
        }

    }

    // MARK: Fetched Results Controller

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        self.dataSource?.applySnapshot(snapshot, animatingDifferences: true)
    }

    // MARK: UI Actions

    @objc(cancelAction)
    private func cancelAction() {
        self.dismiss(animated: true)
    }
}

fileprivate class NotificationTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private lazy var contactImage: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        return imageView
    }()

    private lazy var notificationTextLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var mediaPreview: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 8
        imageView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        return imageView
    }()

    private func setupView() {
        let hStack = UIStackView(arrangedSubviews: [ self.contactImage, self.notificationTextLabel, self.mediaPreview ])
        hStack.axis = .horizontal
        hStack.spacing = 8
        hStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    func configure(with notification: FeedNotification) {
        self.notificationTextLabel.attributedText = notification.formattedText
        self.mediaPreview.image = notification.image
    }
}
