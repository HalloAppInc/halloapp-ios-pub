//
//  PrivacyListViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

final class PrivacyListTableRow: NSObject, IndexableContact, SearchableContact {
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

private extension ContactTableViewCell {

    func configure(with contact: PrivacyListTableRow) {
        options.insert(.hasCheckmark)
        nameLabel.text = contact.name ?? MainAppContext.shared.contactStore.fullName(for: contact.userId)
        subtitleLabel.text = contact.phoneNumber
    }
}

class PrivacyListTableViewController: ContactPickerViewController<PrivacyListTableRow> {

    // MARK: ContactPickerViewController

    override func configure(cell: ContactTableViewCell, with contact: PrivacyListTableRow) {
        cell.configure(with: contact)
        cell.setContact(selected: contact.isSelected)
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? ContactTableViewCell,
              let contact = dataSource.itemIdentifier(for: indexPath) else { return }
        contact.isSelected = !contact.isSelected
        cell.setContact(selected: contact.isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
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
        for contact in MainAppContext.shared.contactStore.allInNetworkContacts(sorted: true) {
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
        let unknownUserIds = selectedContactIds.subtracting(uniqueUserIds)
        let namesForUnknownContacts = MainAppContext.shared.contactStore.fullNames(forUserIds: unknownUserIds)
        contacts.append(contentsOf: unknownUserIds.map({ PrivacyListTableRow(userId: $0, name: namesForUnknownContacts[$0] ?? "Unknown Contact", isSelected: true) }))
        super.init(contacts: contacts)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(privacyList:settings:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = PrivacyList.name(forPrivacyListType: privacyList.type)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneAction))
        navigationItem.searchController?.delegate = self
    }

    override func makeSearchResultsController() -> ContactPickerViewController<PrivacyListTableRow> {
        return PrivacyListSearchResultsViewController(contacts: [])
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
        // Reload to reflect selection changes made while in search mode.
        tableView.reloadData()
    }
}

private class PrivacyListSearchResultsViewController: PrivacyListTableViewController {

    override class var isSearchResultsController: Bool { true }
}
