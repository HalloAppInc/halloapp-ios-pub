//
//  PostDashboardViewController.swift
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
        case sent = 1
        case placeholder = 2
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

private extension Localizations {

    static var viewedBy: String {
        NSLocalizedString("mypost.viewed.by", value: "Viewed by", comment: "Your Post screen: title for group of contacts who has seen your post.")
    }

    static var sentTo: String {
        NSLocalizedString("mypost.sent.to", value: "Sent to", comment: "Your Post screen: title for group of contacts who has not yet seen your post.")
    }

    static var actionViewProfile: String {
        NSLocalizedString("mypost.action.view.profile", value: "View Profile", comment: "One of the contact actions in My Post screen.")
    }

    static var actionMessage: String {
        NSLocalizedString("mypost.action.message", value: "Message", comment: "One of the contact actions in My Post screen. Verb.")
    }

    static var actionHideMyPosts: String {
        NSLocalizedString("mypost.action.hide.my.posts", value: "Hide My Posts", comment: "One of the contact actions in My Post screen.")
    }

    static func hideMyPostsConfirmation(contactName: String) -> String {
        let format = NSLocalizedString("mypost.hide.posts.confirmation",
                                       value: "Are you sure you want to hide all your future posts from %@? You can always change this later.",
                                       comment: "Confirmation when hiding posts from a certain contact. Parameter is contact's full name.")
        return String.localizedStringWithFormat(format, contactName)
    }

    static var postNotYetViewedByAnyone: String {
        NSLocalizedString("mypost.not.viewed.yet", value: "No one has viewed your post yet",
                          comment: "Placeholder text displayed in My Post Info screen when no one has seen the post yet.")
    }
}

protocol PostDashboardViewControllerDelegate: AnyObject {
    func postDashboardViewController(_ controller: PostDashboardViewController, didRequestPerformAction action: PostDashboardViewController.UserAction)
}

class PostDashboardViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    enum UserAction {
        case profile(UserID)
        case message(UserID)
        case blacklist(UserID)
    }

    private struct Constants {
        static let cellReuseIdentifier = "contact-cell"
        static let placeholderCellReuseIdentifier = "placeholder-cell"
        static let headerReuseIdentifier = "header"
    }

    let feedPostId: FeedPostID
    private let isGroupPost: Bool

    private var dataSource: PostReceiptsDataSource!
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>!

    weak var delegate: PostDashboardViewControllerDelegate?

    required init(feedPostId: FeedPostID, isGroupPost: Bool) {
        self.feedPostId = feedPostId
        self.isGroupPost = isGroupPost
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("title.your.post", value: "Your Post", comment: "Title for the screen with information about who saw your post.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarTrashBinWithLid"), style: .plain, target: self, action: #selector(retractPostAction))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.placeholderCellReuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: Constants.headerReuseIdentifier)
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        dataSource = PostReceiptsDataSource(tableView: tableView) { (tableView, indexPath, receipt) in
            if receipt.type == .placeholder {
                let cell = tableView.dequeueReusableCell(withIdentifier: Constants.placeholderCellReuseIdentifier, for: indexPath)
                cell.selectionStyle = .none
                cell.textLabel?.textAlignment = .center
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.text = Localizations.postNotYetViewedByAnyone
                return cell
            }
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
        let deletePostConfirmationPrompt = NSLocalizedString("your.post.deletepost.confirmation", value: "Delete this post? This action cannot be undone.", comment: "Post deletion confirmation. Displayed as action sheet title.")
        let deletePostButtonTitle = NSLocalizedString("your.post.deletepost.button", value: "Delete Post", comment: "Title for the button that confirms intent to delete your own post.")
        let actionSheet = UIAlertController(title: nil, message: deletePostConfirmationPrompt, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: deletePostButtonTitle, style: .destructive) { _ in
            self.reallyRetractPost()
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
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
            return Localizations.viewedBy

        case .sent:
            return Localizations.sentTo

        default:
            return nil
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
        let postAudience: Set<UserID>

        // Only use userIds from receipts if privacy list was actually saved into feedPost.info.
        if let receiptUserIds = feedPost.info?.receipts?.keys, feedPost.info?.audienceType != nil {
            postAudience = Set(receiptUserIds)
        } else {
            // If there is no post info - then use the group info for group feed posts.
            if let groupId = feedPost.groupId {
                if let groupMembers = MainAppContext.shared.chatData.chatGroup(groupId: groupId)?.members {
                    postAudience = Set(groupMembers.map({ $0.userId }))
                } else {
                    postAudience = []
                }
            } else {
                postAudience = Set(MainAppContext.shared.contactStore.allInNetworkContactIDs())
            }
        }

        var seenReceipts = MainAppContext.shared.feedData.seenReceipts(for: feedPost)
        if seenReceipts.isEmpty {
            seenReceipts.append(FeedPostReceipt(userId: "", type: .placeholder, contactName: nil, phoneNumber: nil, timestamp: Date()))
        }

        // Filter out usedIds in "Seen by" section from "Sent to" section.
        var userIdsInSeenBySection = Set(seenReceipts.map(\.userId))
        userIdsInSeenBySection.insert(AppContext.shared.userData.userId)

        // All other contacts go into "Sent to" section.
        let sentReceipts = MainAppContext.shared.feedData.sentReceipts(from: postAudience.subtracting(userIdsInSeenBySection))

        var snapshot = NSDiffableDataSourceSnapshot<FeedPostReceipt.ReceiptType, FeedPostReceipt>()
        snapshot.appendSections([ .seen ])
        snapshot.appendItems(seenReceipts, toSection: .seen)
        if !sentReceipts.isEmpty {
            snapshot.appendSections([ .sent ])
            snapshot.appendItems(sentReceipts, toSection: .sent)
        }
        dataSource?.apply(snapshot, animatingDifferences: viewIfLoaded?.window != nil)
    }

    // MARK: Contact Actions

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let receipt = dataSource.itemIdentifier(for: indexPath), receipt.type != .placeholder,
              let delegate = delegate else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        let contactName = MainAppContext.shared.contactStore.fullName(for: receipt.userId)
        let isUserAContact = MainAppContext.shared.contactStore.isContactInAddressBook(userId: receipt.userId)

        let actionSheet = UIAlertController(title: contactName, message: nil, preferredStyle: .actionSheet)
        // View Profile
        actionSheet.addAction(UIAlertAction(title: Localizations.actionViewProfile, style: .default, handler: { (_) in
            delegate.postDashboardViewController(self, didRequestPerformAction: .profile(receipt.userId))
        }))
        // Message
        if isUserAContact {
            actionSheet.addAction(UIAlertAction(title: Localizations.actionMessage, style: .default, handler: { (_) in
                delegate.postDashboardViewController(self, didRequestPerformAction: .message(receipt.userId))
            }))
        }
        // Hide from Contact
        // This options isn't shown for group feed posts to avoid confusion:
        // blacklisted contacts still able to see user's posts in the group.
        if !isGroupPost {
            actionSheet.addAction(UIAlertAction(title: Localizations.actionHideMyPosts, style: .destructive, handler: { (_) in
                self.promptToAddToBlacklist(userId: receipt.userId, contactName: contactName)
            }))
        }
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true) {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    private func promptToAddToBlacklist(userId: UserID, contactName: String) {
        let actionSheet = UIAlertController(title: Localizations.hideMyPostsConfirmation(contactName: contactName), message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.actionHideMyPosts, style: .destructive, handler: { (_) in
            self.delegate?.postDashboardViewController(self, didRequestPerformAction: .blacklist(userId))
        }))
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true, completion: nil)
    }

}
