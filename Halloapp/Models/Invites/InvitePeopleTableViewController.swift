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

        self.tableView.backgroundColor = .systemBackground
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let contact = contacts[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath)
        cell.textLabel?.text = contact.fullName
        cell.detailTextLabel?.text = contact.phoneNumber
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

        self.tableView.backgroundColor = .systemBackground

        self.dataSource = UITableViewDiffableDataSource<TableSection, ABContact>(tableView: self.tableView) { (tableView, indexPath, contact) in
            var cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier)
            if cell == nil {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: Constants.cellReuseIdentifier)
            }
            cell?.textLabel?.text = contact.fullName
            cell?.detailTextLabel?.text = contact.phoneNumber
            return cell
        }

        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.out.rawValue)
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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var contact: ABContact!
        if tableView == self.tableView {
            contact = dataSource.itemIdentifier(for: indexPath)
        } else {
            contact = resultsController.contacts[indexPath.row]
        }

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
        dataSource.apply(dataSourceSnapshot, animatingDifferences: self.viewIfLoaded?.window != nil)
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

fileprivate class InvitePeopleTableViewCell: UITableViewCell {

    enum CellState {
        case notSelected
        case selected
        case alreadyInvited
    }

    var state: CellState = .notSelected {
        didSet {
            if oldValue != state || self.accessoryView == nil {
                reloadAccessoryView()
            }
        }
    }

    private func setAccessoryImage(_ image: UIImage) {
        if let imageView = self.accessoryView as? UIImageView {
            imageView.image = image.withRenderingMode(.alwaysTemplate)
        } else {
            let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
            imageView.tintColor = .lavaOrange
            imageView.frame.size = CGSize(width: 28, height: 28)
            self.accessoryView = imageView
        }
    }

    private func setAccessoryText(_ text: String) {
        if let label = self.accessoryView as? UILabel {
            label.text = text
            label.sizeToFit()
        } else {
            let label = UILabel()
            label.text = text
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
            label.textColor = .lavaOrange
            label.sizeToFit()
            self.accessoryView = label
        }
    }

    private func reloadAccessoryView() {
        switch state {
        case .notSelected:
            setAccessoryImage(UIImage(systemName: "circle")!)

        case .selected:
            setAccessoryImage(UIImage(systemName: "checkmark.circle.fill")!)

        case .alreadyInvited:
            setAccessoryText("Invited")

        }
    }
}
