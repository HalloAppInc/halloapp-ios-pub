//
//  PrivacyListViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class PrivacyListTableRow: NSObject {
    let userId: UserID
    let name: String?
    let phoneNumber: String?
    var isSelected: Bool = false
    @objc let searchTokens: [String]

    init(userId: UserID, name: String? = nil, phoneNumber: String? = nil, searchTokens: [String] = [], isSelected: Bool = false) {
        self.userId = userId
        self.name = name
        self.phoneNumber = phoneNumber
        self.searchTokens = searchTokens
        self.isSelected = isSelected
    }

    convenience init(contact: ABContact) {
        self.init(userId: contact.userId!, name: contact.fullName, phoneNumber: contact.phoneNumber, searchTokens: contact.searchTokens)
    }
}

class PrivacyListTableViewController: UITableViewController {
    static private let cellReuseIdentifier = "ContactCell"

    var contacts: [PrivacyListTableRow]

    init(contacts: [PrivacyListTableRow]) {
        self.contacts = contacts
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(contacts:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(PrivacyListTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! PrivacyListTableViewCell
        let listEntry = contacts[indexPath.row]
        cell.configure(withListEntry: listEntry)
        cell.setContact(selected: listEntry.isSelected)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? PrivacyListTableViewCell else { return }
        let listEntry = contacts[indexPath.row]
        listEntry.isSelected = !listEntry.isSelected
        cell.setContact(selected: listEntry.isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }

}

class PrivacyListSearchResultsViewController: PrivacyListTableViewController {

    override var contacts: [PrivacyListTableRow] {
        didSet {
            if isViewLoaded {
                tableView.reloadData()
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
    @objc
    private func cancelAction() {
        if let dismissAction = dismissAction {
           dismissAction()
        }
    }

    /**
     Save changes and close picker.
     */
    @objc
    private func doneAction() {
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

fileprivate class PrivacyListTableViewCell: ContactTableViewCell {

    private static var checkmarkUnchecked: UIImage {
        get { UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate) }
    }

    private static var checkmarkChecked: UIImage {
        get { UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate) }
    }

    private let checkMark: UIImageView = {
        let imageView = UIImageView(image: PrivacyListTableViewCell.checkmarkUnchecked)
        imageView.tintColor = .lavaOrange
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        selectionStyle = .none
    }

    func configure(withListEntry listEntry: PrivacyListTableRow) {
        accessoryView = checkMark
        nameLabel.text = listEntry.name ?? MainAppContext.shared.contactStore.fullName(for: listEntry.userId)
        subtitleLabel.text = listEntry.phoneNumber
    }

    var userId: UserID?
    private(set) var isContactSelected: Bool = false

    func setContact(selected: Bool, animated: Bool = false) {
        isContactSelected = selected
        checkMark.image = isContactSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked
        if animated {
            checkMark.layer.add({
                let transition = CATransition()
                transition.duration = 0.2
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                transition.type = .fade
                return transition
            }(), forKey: nil)
        }
    }

}
