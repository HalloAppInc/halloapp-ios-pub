//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData
import UIKit

protocol NewChatViewControllerDelegate: AnyObject {
    func newChatViewController(_ newChatViewController: NewChatViewController, didSelect userId: UserID)
}

class NewChatTableViewController: ContactPickerViewController<ABContact> {

    // MARK: ContactPickerViewController

    override func configure(cell: ContactTableViewCell, with contact: ABContact) {
        cell.configure(with: contact)
    }

    // MARK: NewChatTableViewController

    fileprivate func didSelectContact(with userId: UserID) {
        // Subclasses to implement.
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let contact = dataSource.itemIdentifier(for: indexPath),
              let userId = contact.userId else
        {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        didSelectContact(with: userId)
    }

}

class NewChatViewController: NewChatTableViewController {

    weak var delegate: NewChatViewControllerDelegate?

    private var fetchedResultsController: NSFetchedResultsController<ABContact>!

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
        
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId != nil")
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest,
                                                                         managedObjectContext: AppContext.shared.contactStore.viewContext,
                                                                         sectionNameKeyPath: nil,
                                                                         cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            reloadContacts()
        } catch {
            fatalError("Failed to fetch contacts. \(error)")
        }
    }

    // MARK: ContactPickerViewController

    override func makeSearchResultsController() -> ContactPickerViewController<ABContact> {
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
        let uniqueContacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: allContacts)
        set(displayContacts: uniqueContacts, searchableContacts: allContacts)
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
}

extension ABContact: IndexableContact {
    var collationName: String {
        indexName ?? "#"
    }
}

extension ABContact: SearchableContact { }
