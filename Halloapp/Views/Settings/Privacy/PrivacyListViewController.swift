//
//  PrivacyListViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

private class PrivacyListTableRow: NSObject, IndexableContact {
    let userId: UserID
    let name: String?
    let indexName: String
    let phoneNumber: String?
    var isSelected: Bool = false
    @objc let searchTokens: [String]

    init(userId: UserID, name: String? = nil, indexName: String? = nil, phoneNumber: String? = nil, searchTokens: [String] = [], isSelected: Bool = false) {
        self.userId = userId
        self.name = name
        self.indexName = indexName ?? "#"
        self.phoneNumber = phoneNumber
        self.searchTokens = searchTokens
        self.isSelected = isSelected
    }

    convenience init(contact: ABContact) {
        self.init(userId: contact.userId!, name: contact.fullName, indexName: contact.indexName, phoneNumber: contact.phoneNumber, searchTokens: contact.searchTokens)
    }

    var collationName: String {
        indexName
    }
}

class PrivacyListTableViewController: UITableViewController {
    static private let cellReuseIdentifier = "ContactCell"

    fileprivate var contacts: [PrivacyListTableRow]
    class var showSections: Bool { true }
    fileprivate var dataSource: ContactsTableViewDataSource<PrivacyListTableRow>!

    fileprivate init(contacts: [PrivacyListTableRow]) {
        self.contacts = contacts
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(contacts:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        dataSource = ContactsTableViewDataSource<PrivacyListTableRow>(tableView: tableView, cellProvider: { (tableView, indexPath, contact) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.configure(with: contact)
            cell.setContact(selected: contact.isSelected)
            return cell
        })
        dataSource.isSectioningEnabled = Self.showSections
        dataSource.reload(contacts: contacts, animatingDifferences: false)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? ContactTableViewCell,
              let contact = dataSource.itemIdentifier(for: indexPath) else { return }
        contact.isSelected = !contact.isSelected
        cell.setContact(selected: contact.isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

private class PrivacyListSearchResultsViewController: PrivacyListTableViewController {

    override class var showSections: Bool { false }

    override fileprivate var contacts: [PrivacyListTableRow] {
        didSet {
            if isViewLoaded {
                dataSource.reload(contacts: contacts, animatingDifferences: false)
            }
        }
    }
}

class PrivacyListViewController: PrivacyListTableViewController {

    var dismissAction: (() -> ())?

    private let privacyList: PrivacyList
    private let privacySettings: PrivacySettings

    init(privacyList: PrivacyList, settings: PrivacySettings) {
        self.privacyList = privacyList
        self.privacySettings = settings

        let selectedContactIds = Set(privacyList.userIds)

        // Load all device contacts, making them unique and removing self.
        let selfUserId = MainAppContext.shared.userData.userId
        var uniqueUserIds = Set<UserID>()
        var contacts = [PrivacyListTableRow]()
        for contact in MainAppContext.shared.contactStore.allRegisteredContacts(sorted: true) {
            guard let userId = contact.userId else { continue }
            guard !uniqueUserIds.contains(userId) else { continue }
            guard userId != selfUserId else { continue }

            contacts.append(PrivacyListTableRow(contact: contact))
            
            uniqueUserIds.insert(contact.userId!)
        }
        // Load selection
        for entry in contacts {
            entry.isSelected = selectedContactIds.contains(entry.userId)
        }
        // Append contacts that aren't in user's address book (if any).
        contacts.append(contentsOf: selectedContactIds.subtracting(uniqueUserIds).map({ PrivacyListTableRow(userId: $0, isSelected: true) }))
        super.init(contacts: contacts)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = PrivacyList.name(forPrivacyListType: privacyList.type)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneAction))

        // Search
        let searchResultsController = PrivacyListSearchResultsViewController(contacts: [])
        let searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        navigationItem.searchController = searchController
    }

    /**
     Discard changes and dismiss picker.
     */
    @objc private func cancelAction() {
        if let dismissAction = dismissAction {
           dismissAction()
        }
    }

    /**
     Save changes and close picker.
     */
    @objc private func doneAction() {
        let selectedContactIds = contacts.filter({ $0.isSelected }).map({ $0.userId })
        privacySettings.update(privacyList: privacyList, with: selectedContactIds)

        if let dismissAction = dismissAction {
           dismissAction()
        }
    }
}

extension PrivacyListViewController: UISearchControllerDelegate {

    func willDismissSearchController(_ searchController: UISearchController) {
        tableView.reloadData()
    }
}

extension PrivacyListViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let resultsController = searchController.searchResultsController as? PrivacyListSearchResultsViewController else { return }

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
        resultsController.contacts = contacts.filter { finalCompoundPredicate.evaluate(with: $0) }
    }
}

private extension ContactTableViewCell {

    func configure(with contact: PrivacyListTableRow) {
        options.insert(.hasCheckmark)
        nameLabel.text = contact.name ?? MainAppContext.shared.contactStore.fullName(for: contact.userId)
        subtitleLabel.text = contact.phoneNumber
    }
}
