//
//  InvitePeopleTableViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

private extension ContactTableViewCell {

    func configure(with contact: ABContact) {
        options.remove(.hasImage)

        let isUserAlready = contact.status == .in
        selectionStyle = isUserAlready ? .none : .default
        nameLabel.text = contact.fullName
        nameLabel.textColor = isUserAlready ? .secondaryLabel : .label
        subtitleLabel.text = isUserAlready ? "Already a HalloApp user" : contact.phoneNumber
    }
}

extension ABContact: IndexableContact {
    var collationName: String {
        indexName ?? "#"
    }
}

extension ABContact: SearchableContact { }

class InvitePeopleTableViewController: ContactPickerViewController<ABContact> {

    fileprivate let didSelectContact: (ABContact) -> ()

    fileprivate init(didSelectContact: @escaping (ABContact) -> ()) {
        self.didSelectContact = didSelectContact
        super.init(contacts: [])
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(didSelectContact:)")
    }

    // MARK: ContactPickerViewController

    override func configure(cell: ContactTableViewCell, with contact: ABContact) {
        cell.configure(with: contact)
    }

    // MARK: UITableViewDelegate

    private func contactForIndexPath(_ indexPath: IndexPath, in tableView: UITableView) -> ABContact? {
        return dataSource.itemIdentifier(for: indexPath)
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let contact = contactForIndexPath(indexPath, in: tableView), contact.status != .in else {
            return nil
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let contact = contactForIndexPath(indexPath, in: tableView) else { return }

        didSelectContact(contact)
        DispatchQueue.main.async {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

}

class InvitePeopleViewController: InvitePeopleTableViewController {

    private var fetchedResultsController: NSFetchedResultsController<ABContact>!

    override init(didSelectContact: @escaping (ABContact) -> ()) {
        super.init(didSelectContact: didSelectContact)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(didSelectContact:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "statusValue == %d OR statusValue == %d", ABContact.Status.out.rawValue, ABContact.Status.in.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest,
                                                                         managedObjectContext: MainAppContext.shared.contactStore.viewContext,
                                                                         sectionNameKeyPath: nil,
                                                                         cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            reloadContacts()
        }
        catch {
            fatalError("Failed to fetch contacts. \(error)")
        }
    }

    override func makeSearchResultsController() -> ContactPickerViewController<ABContact> {
        return InvitePeopleSearchResultsController(didSelectContact: didSelectContact)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if !Self.isSearchResultsController, let parent = parent {
            parent.navigationItem.searchController = searchController
        }
    }

    private func reloadContacts() {
        contacts = fetchedResultsController.fetchedObjects ?? []
    }

}

extension InvitePeopleViewController: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadContacts()
    }
}

private class InvitePeopleSearchResultsController: InvitePeopleTableViewController {

    override class var isSearchResultsController: Bool { true }
}
