//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CoreData
import UIKit

class CommentsViewController: UIViewController, NSFetchedResultsControllerDelegate {
    static private let cellReuseIdentifier = "CommentCell"

    private var item: FeedDataItem?
    private var dataSource: UITableViewDiffableDataSource<Int, FeedComments>?
    private var fetchedResultsController: NSFetchedResultsController<FeedComments>?

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.register(CommentsTableViewCell.self, forCellReuseIdentifier: CommentsViewController.cellReuseIdentifier)
        return tableView
    }()

    init(item: FeedDataItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        guard self.item != nil else { return }

        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: self.tableView.bounds.size.width, height: 200))
        headerView.commentView.updateWith(feedItem: self.item!)
        self.tableView.tableHeaderView = headerView

        self.dataSource = UITableViewDiffableDataSource<Int, FeedComments>(tableView: self.tableView) { tableView, indexPath, feedComments in
            let cell = tableView.dequeueReusableCell(withIdentifier: CommentsViewController.cellReuseIdentifier, for: indexPath) as! CommentsTableViewCell
            cell.update(with: feedComments)
            return cell
        }

        let fetchRequest = NSFetchRequest<FeedComments>(entityName: "FeedComments")
        fetchRequest.predicate = NSPredicate(format: "feedItemId = %@", self.item!.itemId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedComments.timestamp, ascending: true) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedComments>(fetchRequest: fetchRequest,
                                                     managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
                                                     sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
            self.updateData(animatingDifferences: false)
        } catch {
            return
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let feedItem = self.item {
            AppContext.shared.feedData.markFeedItemUnreadComments(feedItemId: feedItem.itemId)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let feedItem = self.item {
            AppContext.shared.feedData.markFeedItemUnreadComments(feedItemId: feedItem.itemId)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let headerView = self.tableView.tableHeaderView {
            let targetSize = CGSize(width: self.tableView.bounds.size.width, height: UIView.layoutFittingCompressedSize.height)
            let size = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            if size.height != headerView.bounds.size.height {
                headerView.frame.size.height = size.height
                self.tableView.tableHeaderView = headerView
            }
        }
    }

    // MARK: Data

    func updateData(animatingDifferences: Bool = true) {
        guard let allComments = self.fetchedResultsController?.fetchedObjects else { return }
        var results: [FeedComments] = []

        func findChildren(of commendID: String) {
            let children = allComments.filter{ $0.parentCommentId == commendID }
            for child in children {
                results.append(child)
                findChildren(of: child.commentId!)
            }
        }

        findChildren(of: "")

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, FeedComments>()
        diffableDataSourceSnapshot.appendSections([0])
        diffableDataSourceSnapshot.appendItems(results)
        self.dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.updateData()
    }
}


class CommentsTableHeaderView: UIView {
    lazy var commentView: CommentView = {
        let commentView = CommentView()
        commentView.isReplyButtonVisible = false
        return commentView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.preservesSuperviewLayoutMargins = true

        self.commentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.commentView)

        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor.separator
        self.addSubview(separatorView)

        let views = [ "content": self.commentView, "separator": separatorView]
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[content]|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[separator]|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[content][separator]|", options: [], metrics: nil, views: views))
        let separatorHeight = 1.0 / UIScreen.main.scale
        self.addConstraint(NSLayoutConstraint(item: separatorView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: separatorHeight))
    }
}


class CommentsTableViewCell: UITableViewCell {
    private lazy var commentView: CommentView = {
        CommentView()
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupTableViewCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTableViewCell()
    }

    private func setupTableViewCell() {
        self.selectionStyle = .none
        
        self.contentView.addSubview(self.commentView)
        self.commentView.translatesAutoresizingMaskIntoConstraints = false
        let views = [ "comment": self.commentView ]
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[comment]|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[comment]|", options: [], metrics: nil, views: views))
    }

    func update(with comment: FeedComments) {
        self.commentView.updateWith(commentItem: comment)
        self.commentView.isContentInset = !(comment.parentCommentId?.isEmpty ?? false)
    }
}
