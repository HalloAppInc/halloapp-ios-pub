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

        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
    }
}

fileprivate class PostReceiptsDataSource: UITableViewDiffableDataSource<Section, Row> {

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

    let feedPostId: FeedPostID
    private let isGroupPost: Bool
    private var showAllContacts: Bool = false
    private var initialNumContactsToShow: Int = 12

    private struct Constants {
        static let cellReuseIdentifier = "contactCell"
        static let placeholderCellReuseIdentifier = "placeholderCell"
        static let actionCellReuseIdentifier = "rowActionCell"
        static let headerReuseIdentifier = "header"
    }

    private var dataSource: PostReceiptsDataSource!
    private var fetchedResultsController: NSFetchedResultsController<FeedPost>!

    weak var delegate: PostDashboardViewControllerDelegate?

    required init(feedPostId: FeedPostID, isGroupPost: Bool) {
        self.feedPostId = feedPostId
        self.isGroupPost = isGroupPost
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("title.your.post", value: "Seen By", comment: "Title for the screen with information about who saw your post.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.placeholderCellReuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        tableView.register(ActionTableViewCell.self, forCellReuseIdentifier: Constants.actionCellReuseIdentifier)
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        dataSource = PostReceiptsDataSource(tableView: tableView) { (tableView, indexPath, row) in
            if indexPath.section == 0 {
                switch row {
                case .contactRow(let contactRow):
                    switch contactRow {
                    case .contact(let receipt):
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
                    case .more:
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: Constants.actionCellReuseIdentifier, for: indexPath) as? ActionTableViewCell else { break }
                        guard let image = UIImage(systemName: "chevron.down")?.withRenderingMode(.alwaysTemplate) else { break }
                        cell.configure(icon: image, label: Localizations.buttonMore)
                        cell.imageBgColor = .clear
                        return cell
                    }
                default:
                    break
                }

                return UITableViewCell()
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: Constants.actionCellReuseIdentifier, for: indexPath) as! ActionTableViewCell
                switch row.actionRow {
                case .privacy:
                    if let image = UIImage(named: "settingsPrivacy")?.withRenderingMode(.alwaysTemplate) {
                        cell.color = .primaryBlue
                        cell.imageBgColor = .clear
                        cell.configure(icon: image, label: Localizations.myPostRowManagePrivacy)
                    }
                    return cell
                case .invite:
                    if let image = UIImage(named: "settingsInvite")?.withRenderingMode(.alwaysTemplate) {
                        cell.color = .primaryBlue
                        cell.imageBgColor = .clear
                        cell.configure(icon: image, label: Localizations.myPostRowInvite)
                    }
                case .none: return cell
                }
                return cell
            }
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

    // MARK: Table View Support

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let feedPost = controller.fetchedObjects?.last as? FeedPost {
            reloadData(from: feedPost)
        }
    }

    private func showAllContactsTapped() {
        showAllContacts = true
        if let feedPost = fetchedResultsController.fetchedObjects?.first {
            reloadData(from: feedPost)
        }
    }

    private func reloadData(from feedPost: FeedPost) {
        var seenReceipts = MainAppContext.shared.feedData.seenReceipts(for: feedPost)
        if seenReceipts.isEmpty {
            seenReceipts.append(FeedPostReceipt(userId: "", type: .placeholder, contactName: nil, phoneNumber: nil, timestamp: Date()))
        }

        var allContactRowContacts = [ContactRow]()
        allContactRowContacts.append(contentsOf: seenReceipts.map { ContactRow.contact($0) })

        var allContactRows = [Row]()
        allContactRows.append(contentsOf: allContactRowContacts.map { Row.contactRow($0) })

        var contactRows = [Row]()

        if !showAllContacts && (allContactRows.count > initialNumContactsToShow) {
            contactRows = Array(allContactRows.prefix(initialNumContactsToShow - 2)) // show 10
            contactRows.append(Row.contactRow(ContactRow.more))
        } else {
            contactRows = Array(allContactRows)
        }

        var actionRows = [Row]()
        actionRows.append(Row.actionRow(.privacy))
        actionRows.append(Row.actionRow(.invite))

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .contacts ])
        snapshot.appendItems(contactRows, toSection: .contacts)

        if !isGroupPost {
            snapshot.appendSections([ .actions ])
            snapshot.appendItems(actionRows, toSection: .actions)
        }

        dataSource?.defaultRowAnimation = .fade
        dataSource?.apply(snapshot, animatingDifferences: viewIfLoaded?.window != nil)
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        let footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 40))

        let label = UILabel(frame: CGRect(x: 10, y: 0, width: view.frame.size.width - 20, height: 40))
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.myPostDisappearTimeLabel
        footerView.addSubview(label)
        return footerView
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 50
    }

    // MARK: Contact Actions

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath), let delegate = delegate else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        if indexPath.section == 0 {

            switch row {
            case .contactRow(let contactRow):
                switch contactRow {
                case .contact(let receipt):
                    guard receipt.type != .placeholder else { break }
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
                case .more:
                    tableView.deselectRow(at: indexPath, animated: false)
                    showAllContactsTapped()
                }
            default:
                break
            }
        } else {
            switch row.actionRow {
            case .privacy:
                let viewController = PrivacyViewController()
                viewController.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(viewController, animated: true)
            case .invite:
                guard ContactStore.contactsAccessAuthorized else {
                    let inviteVC = InvitePermissionDeniedViewController()
                    present(UINavigationController(rootViewController: inviteVC), animated: true)
                    return
                }
                InviteManager.shared.requestInvitesIfNecessary()
                let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
                present(UINavigationController(rootViewController: inviteVC), animated: true)
            default:
                break
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
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

fileprivate enum Section {
    case contacts
    case actions
}

fileprivate enum Row: Hashable, Equatable {
    case contactRow(ContactRow)
    case actionRow(ActionRow)

    var contactRow: ContactRow? {
        switch self {
        case .contactRow(let contactRow): return contactRow
        case .actionRow: return nil
        }
    }

    var actionRow: ActionRow? {
        switch self {
        case .contactRow: return nil
        case .actionRow(let actionRow): return actionRow
        }
    }
}

fileprivate enum ContactRow: Hashable, Equatable {
    case contact(FeedPostReceipt)
    case more

    var contact: FeedPostReceipt? {
        switch self {
        case .contact(let feedPostReceipt): return feedPostReceipt
        case .more: return nil
        }
    }
}

fileprivate enum ActionRow {
    case privacy
    case invite
}

private extension Localizations {

    static var myPostDisappearTimeLabel: String {
        NSLocalizedString("mypost.disappear.time.label", value: "Your posts will disappear after 30 days.", comment: "Message displayed to say when posts will disappear")
    }

    static var myPostRowManagePrivacy: String {
        NSLocalizedString("mypost.row.manage.privacy", value: "Manage Privacy", comment: "Your Post screen: label for the row that opens the privacy screen")
    }

    static var myPostRowInvite: String {
        NSLocalizedString("mypost.row.invite.to.halloapp", value: "Invite To Halloapp", comment: "Your Post screen: label for the row that opens the invite screen")
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
