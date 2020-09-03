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

fileprivate struct Constants {
    static let cellReuseIdentifier = "inviteContactCell"
}

private extension ContactTableViewCell {

    func configure(withContact contact: ABContact) {
        options.remove(.hasImage)

        let isUserAlready = contact.status == .in
        selectionStyle = isUserAlready ? .none : .default
        nameLabel.text = contact.fullName
        nameLabel.textColor = isUserAlready ? .secondaryLabel : .label
        subtitleLabel.text = isUserAlready ? "Already a HalloApp user" : contact.phoneNumber
    }
}

fileprivate class InvitePeopleResultsController: UITableViewController {
    var contacts: [ABContact] = [] {
        didSet {
            if self.isViewLoaded {
                self.tableView.reloadData()
            }
        }
    }

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let contact = contacts[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
        cell.configure(withContact: contact)
        return cell
    }
}

class InvitePeopleTableViewController: UITableViewController {

    private enum TableSection {
        case main
    }

    private let inviteManager = InviteManager.shared
    private var dataSource: UITableViewDiffableDataSource<TableSection, ABContact>!
    private var fetchedResultsController: NSFetchedResultsController<ABContact>!
    private let didSelectContact: (ABContact) -> ()

    private var searchController: UISearchController!
    private var resultsController: InvitePeopleResultsController!

    init(didSelectContact: @escaping (ABContact) -> ()) {
        self.didSelectContact = didSelectContact
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)

        dataSource = UITableViewDiffableDataSource<TableSection, ABContact>(tableView: tableView) { (tableView, indexPath, contact) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.configure(withContact: contact)
            return cell
        }

        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "statusValue == %d OR statusValue == %d", ABContact.Status.out.rawValue, ABContact.Status.in.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.contactStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController?.delegate = self
        do {
            try fetchedResultsController?.performFetch()
            updateSnapshot()
        }
        catch {
            fatalError("Failed to fetch contacts. \(error)")
        }

        resultsController = InvitePeopleResultsController()
        resultsController.tableView.delegate = self
        searchController = UISearchController(searchResultsController: resultsController)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let parent = parent {
            parent.navigationItem.searchController = searchController
        }
    }

}

extension InvitePeopleTableViewController {

    private func contactForIndexPath(_ indexPath: IndexPath, in tableView: UITableView) -> ABContact {
        if tableView == self.tableView {
            return dataSource.itemIdentifier(for: indexPath)!
        } else {
            return resultsController.contacts[indexPath.row]
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let contact = contactForIndexPath(indexPath, in: tableView)
        guard contact.status != .in else {
            return nil
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let contact = contactForIndexPath(indexPath, in: tableView)
        self.didSelectContact(contact)
        DispatchQueue.main.async {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
}

extension InvitePeopleTableViewController: NSFetchedResultsControllerDelegate {

    private func updateSnapshot() {
        var dataSourceSnapshot = NSDiffableDataSourceSnapshot<TableSection, ABContact>()
        dataSourceSnapshot.appendSections([.main])
        dataSourceSnapshot.appendItems(fetchedResultsController.fetchedObjects ?? [])
        dataSource.apply(dataSourceSnapshot, animatingDifferences: viewIfLoaded?.window != nil)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateSnapshot()
    }
}

extension InvitePeopleTableViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let resultsController = searchController.searchResultsController as? InvitePeopleResultsController else { return }
        guard let allContacts = fetchedResultsController.fetchedObjects else { return }

        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
        let searchItems = strippedString.components(separatedBy: " ")

        let andPredicates: [NSPredicate] = searchItems.map { (searchString) in
            NSComparisonPredicate(leftExpression: NSExpression(forKeyPath: "searchTokens"),
                                  rightExpression: NSExpression(forConstantValue: searchString),
                                  modifier: .any,
                                  type: .contains,
                                  options: [.caseInsensitive, .diacriticInsensitive])
        }

        let finalCompoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        resultsController.contacts = allContacts.filter { finalCompoundPredicate.evaluate(with: $0) }
    }
}
