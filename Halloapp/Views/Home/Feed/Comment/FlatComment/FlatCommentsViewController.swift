//
//  FlatCommentsViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 11/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Core
import CoreData
import UIKit

private extension Localizations {

    static var titleComments: String {
        NSLocalizedString("title.comments", value: "Comments", comment: "Title for the Comments screen.")
    }
}

class FlatCommentsViewController: UIViewController, UICollectionViewDelegate, NSFetchedResultsControllerDelegate {
    typealias CommentDataSource = UICollectionViewDiffableDataSource<String, FeedPostComment>
    typealias CommentSnapshot = NSDiffableDataSourceSnapshot<String, FeedPostComment>
    static private let messageViewCellReuseIdentifier = "MessageViewCell"

    private var feedPostId: FeedPostID {
        didSet {
            // TODO Remove this if not needed for mentions
        }
    }

    private var feedPost: FeedPost?

    private lazy var dataSource: CommentDataSource = {
        let dataSource = CommentDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, comment) -> UICollectionViewCell? in
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier,
                    for: indexPath)
                if let itemCell = cell as? MessageViewCell {
                    itemCell.configureWithComment(comment: comment)
                }
                return cell
            })
        // Setup comment header view
        dataSource.supplementaryViewProvider = { [weak self] ( view, kind, index) in
            if kind == MessageTimeHeaderView.elementKind {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageTimeHeaderView.elementKind, for: index)
                if let messageTimeHeaderView = headerView as? MessageTimeHeaderView, let self = self, let feedPost = self.feedPost, let sections = self.fetchedResultsController?.sections{
                    let section = sections[index.section ]
                    messageTimeHeaderView.configure(headerText: section.name)
                    return messageTimeHeaderView
                } else {
                    // TODO(@dini) add post loading here
                    DDLogInfo("FlatCommentsViewController/configureHeader/header info not available")
                    return headerView
                }
            } else {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageCommentHeaderView.elementKind, for: index)
                if let messageCommentHeaderView = headerView as? MessageCommentHeaderView, let self = self, let feedPost = self.feedPost {
                    messageCommentHeaderView.configure(withPost: feedPost)
                    messageCommentHeaderView.delegate = self
                    return messageCommentHeaderView
                } else {
                    // TODO(@dini) add post loading here
                    DDLogInfo("FlatCommentsViewController/configureHeader/header info not available")
                    return headerView
                }
            }
        }
        return dataSource
    }()

    private var fetchedResultsController: NSFetchedResultsController<FeedPostComment>?

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.primaryBg
        collectionView.allowsSelection = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.register(MessageViewCell.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier)
        collectionView.register(MessageCommentHeaderView.self, forSupplementaryViewOfKind: MessageCommentHeaderView.elementKind, withReuseIdentifier: MessageCommentHeaderView.elementKind)
        collectionView.register(MessageTimeHeaderView.self, forSupplementaryViewOfKind: MessageTimeHeaderView.elementKind, withReuseIdentifier: MessageTimeHeaderView.elementKind)
        collectionView.delegate = self
        return collectionView
    }()

    init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        self.feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = Localizations.titleComments
        view.backgroundColor = UIColor.primaryBg
        view.addSubview(collectionView)
        collectionView.constrainMargins([.top, .leading, .bottom, .trailing], to: view)
        if let feedPost = feedPost {
            configureUI(with: feedPost)
        }
    }
    
    private func configureUI(with feedPost: FeedPost) {
        // Setup the diffable data source so it can be used for first fetch of data
        collectionView.dataSource = dataSource
        initFetchedResultsController()
        // Initiate download of media that were not yet downloaded. TODO Ask if this is needed
        if let comments = fetchedResultsController?.fetchedObjects {
            MainAppContext.shared.feedData.downloadMedia(in: comments)
        }
    }
    
    private func initFetchedResultsController() {
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<FeedPostComment>(
            fetchRequest: fetchRequest,
            managedObjectContext: MainAppContext.shared.feedData.viewContext,
            sectionNameKeyPath: "headerTime",
            cacheName: nil
        )
        fetchedResultsController?.delegate = self
        // The diffable data source should handle the first fetch
        do {
            DDLogError("FlatCommentsViewController/configureUI/fetching comments for post \(feedPostId)")
            try fetchedResultsController?.performFetch()
        } catch {
            DDLogError("FlatCommentsViewController/configureUI/failed to fetch comments for post \(feedPostId)")
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var snapshot = CommentSnapshot()
        if let sections = fetchedResultsController?.sections {
            snapshot.appendSections(sections.map { $0.name } )
            for section in sections {
                if let comments = section.objects as? [FeedPostComment] {

                    print("Nandini section name : \(section.name) ||| comments count : \(comments.count) ")
                    snapshot.appendItems(comments, toSection: section.name)
                }

            }
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let sectionHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionHeaderSize, elementKind: MessageTimeHeaderView.elementKind, alignment: .top)
        sectionHeader.pinToVisibleBounds = true

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [sectionHeader]

        // Setup the comment view header with post information as the global header of the collection view.
        let layoutHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(55))
        let layoutHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: layoutHeaderSize, elementKind: MessageCommentHeaderView.elementKind, alignment: .top)
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.boundarySupplementaryItems = [layoutHeader]

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration = layoutConfig
        return layout
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            showUserFeed(for: feedPost.userId)
        }
    }
    
    @objc private func showGroupFeed(groupId: GroupID) {
        guard let feedPost = self.feedPost, let groupId = feedPost.groupId else { return }
        guard MainAppContext.shared.chatData.chatGroup(groupId: groupId) != nil else { return }
        let vc = GroupFeedViewController(groupId: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }
}

extension FlatCommentsViewController: MessageCommentHeaderViewDelegate {

    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapGroupWithID groupId: GroupID) {
        showGroupFeed(groupId: groupId)
    }

    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapProfilePictureUserId userId: UserID) {
        showUserFeed(for: userId)
    }

    func messageCommentHeaderView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        guard let media = MainAppContext.shared.feedData.media(postID: feedPostId) else { return }

        var canSavePost = false

        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            canSavePost = post.canSaveMedia
        }

        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view
        present(controller, animated: true)
    }
}

extension FlatCommentsViewController: MessageViewDelegate {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int) {
        var canSavePost = false
        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            canSavePost = post.canSaveMedia
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: feedPostCommentID) else { return }
        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view
        present(controller, animated: true)
    }
}

extension FeedPostComment {
    @objc var headerTime: String { get {
        return timestamp.chatTimestamp(Date())
    }}
}
