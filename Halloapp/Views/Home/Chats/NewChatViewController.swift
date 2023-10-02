//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData
import UIKit

extension UserProfile: IndexableContact, SearchableContact {

    var collationName: String {
        name
    }

    var searchTokens: [String] {
        searchItems
    }
}

protocol NewChatViewControllerDelegate: AnyObject {
    func newChatViewController(_ newChatViewController: NewChatViewController, didSelect userId: UserID)
    func newChatViewController(_ newChatViewController: NewChatViewController, didSelectGroup groupId: GroupID)
}

class NewChatTableViewController: ContactPickerViewController<UserProfile> {

    // MARK: ContactPickerViewController

    override func configure(cell: ContactTableViewCell, with contact: UserProfile) {
        cell.configure(with: contact)
    }

    // MARK: NewChatTableViewController

    fileprivate func didSelectContact(with userId: UserID) {
        // Subclasses to implement.
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let contact = dataSource.itemIdentifier(for: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        didSelectContact(with: contact.id)
    }

}

class NewChatViewController: NewChatTableViewController {

    weak var delegate: NewChatViewControllerDelegate?

    private var fetchedResultsController: NSFetchedResultsController<UserProfile>!

    init(delegate: NewChatViewControllerDelegate) {
        self.delegate = delegate
        super.init(displayContacts: [], searchableContacts: [])
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(delegate:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        DDLogInfo("NewChatViewController/viewDidLoad")

        navigationItem.title = Localizations.titleChatNewMessage
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))

        tableView.backgroundColor = .feedBackground
        
        let fetchRequest = UserProfile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \UserProfile.name, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                              managedObjectContext: AppContext.shared.mainDataStore.viewContext,
                                                              sectionNameKeyPath: nil,
                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            reloadContacts()
        } catch {
            fatalError("Failed to fetch contacts. \(error)")
        }
        if ServerProperties.enableGroupChat {
            let newGroupChatHeaderView = NewGroupChatHeaderView()
            newGroupChatHeaderView.delegate = self
            tableView.tableHeaderView = newGroupChatHeaderView
        }
    }

    private func openNewChatGroup() {
        navigationController?.pushViewController(CreateGroupViewController(groupType: GroupType.groupChat, completion: didCreateNewGroup(_:)), animated: true)
    }

    private func didCreateNewGroup(_ groupId: GroupID) {
        Analytics.log(event: .createGroup, properties: [.groupType: "chat"])
        dismiss(animated: false)
        delegate?.newChatViewController(self, didSelectGroup: groupId)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateHeaderViewHeight(for: tableView.tableHeaderView)
    }

    func updateHeaderViewHeight(for header: UIView?) {
        guard let header = header else { return }
        header.frame.size.height = header.systemLayoutSizeFitting(CGSize(width: view.bounds.width, height: 0)).height
    }
    // MARK: ContactPickerViewController

    override func makeSearchResultsController() -> ContactPickerViewController<UserProfile> {
        return NewChatSearchResultsController(delegate: self)
    }

    // MARK: Appearance

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("NewChatViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("NewChatViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }

    private func reloadContacts() {
        let allContacts = fetchedResultsController.fetchedObjects ?? []
        set(displayContacts: allContacts, searchableContacts: allContacts)
    }

    // MARK: NewChatTableViewController

    override func didSelectContact(with userId: UserID) {
        delegate?.newChatViewController(self, didSelect: userId)
    }
}

extension NewChatViewController: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadContacts()
    }
}

extension NewChatViewController: NewChatSearchResultsControllerDelegate {

    fileprivate func newChatSearchResultsController(_ controller: NewChatSearchResultsController, didSelect userId: UserID) {
        if searchController.isActive {
            searchController.dismiss(animated: false) {
                self.didSelectContact(with: userId)
            }
        } else {
            didSelectContact(with: userId)
        }
    }
}

extension NewChatViewController: NewGroupChatHeaderViewDelegate {
    func newGroupChatHeaderView(_ newGroupChatHeaderView: NewGroupChatHeaderView) {
        openNewChatGroup()
    }
}

private protocol NewChatSearchResultsControllerDelegate: AnyObject {

    func newChatSearchResultsController(_ controller: NewChatSearchResultsController, didSelect userId: UserID)
}

private class NewChatSearchResultsController: NewChatTableViewController {

    weak var delegate: NewChatSearchResultsControllerDelegate?

    init(delegate: NewChatSearchResultsControllerDelegate) {
        self.delegate = delegate
        super.init(displayContacts: [], searchableContacts: [])
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(delegate:)")
    }

    // MARK: ContactPickerViewController

    override class var isSearchResultsController: Bool { true }

    // MARK: NewChatTableViewController

    override func didSelectContact(with userId: UserID) {
        delegate?.newChatSearchResultsController(self, didSelect: userId)
    }
}

private extension ContactTableViewCell {

    func configure(with abContact: ABContact) {
        nameLabel.text = abContact.fullName
        subtitleLabel.text = abContact.phoneNumber
        if let userId = abContact.userId {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }

    func configure(with profile: UserProfile) {
        nameLabel.text = profile.name
        subtitleLabel.text = profile.username

        contactImage.configure(with: profile.id, using: MainAppContext.shared.avatarStore)
    }
}

extension ABContact: IndexableContact {
    var collationName: String {
        indexName ?? "#"
    }
}

extension ABContact: SearchableContact { }
