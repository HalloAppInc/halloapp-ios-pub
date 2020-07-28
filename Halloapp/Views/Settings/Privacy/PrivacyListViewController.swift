//
//  PrivacyListViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class PrivacyListEntry: NSObject {
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

    var contacts: [PrivacyListEntry]

    init(contacts: [PrivacyListEntry]) {
        self.contacts = contacts
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(contacts:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.backgroundColor = .systemBackground
        self.tableView.register(PrivacyListTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
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

    override var contacts: [PrivacyListEntry] {
        didSet {
            if self.isViewLoaded {
                self.tableView.reloadData()
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

        let selectedContactIds = Set(privacyList.items.map({ $0.userId }))

        // Load all device contacts, making them unique and removing self.
        let selfUserId = MainAppContext.shared.userData.userId
        var uniqueUserIds = Set<UserID>()
        var contacts = [PrivacyListEntry]()
        for contact in MainAppContext.shared.contactStore.allRegisteredContacts(sorted: true) {
            guard let userId = contact.userId else { continue }
            guard !uniqueUserIds.contains(userId) else { continue }
            guard userId != selfUserId else { continue }

            contacts.append(PrivacyListEntry(contact: contact))
            
            uniqueUserIds.insert(contact.userId!)
        }
        // Load selection
        for entry in contacts {
            entry.isSelected = selectedContactIds.contains(entry.userId)
        }
        // Append contacts that aren't in user's address book (if any).
        contacts.append(contentsOf: selectedContactIds.subtracting(uniqueUserIds).map({ PrivacyListEntry(userId: $0, isSelected: true) }))
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
        self.navigationItem.searchController = searchController

        self.definesPresentationContext = true
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
        self.tableView.reloadData()
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

fileprivate class PrivacyListTableViewCell: UITableViewCell {

    var userId: UserID?

    private let checkMark: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "circle")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
        imageView.tintColor = .lavaOrange
        return imageView
    }()

    private let contactNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        return label
    }()

    private let phoneNumberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
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
        self.preservesSuperviewLayoutMargins = true
        self.selectionStyle = .none

        let vStack = UIStackView()
        vStack.spacing = 4
        vStack.axis = .vertical
        vStack.addArrangedSubview(contactNameLabel)
        vStack.addArrangedSubview(phoneNumberLabel)
        vStack.translatesAutoresizingMaskIntoConstraints = false

        self.contentView.addSubview(vStack)
        self.contentView.addSubview(checkMark)

        vStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        checkMark.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: vStack.trailingAnchor, multiplier: 1).isActive = true
        checkMark.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor).isActive = true
        checkMark.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }

    func configure(withListEntry listEntry: PrivacyListEntry) {
        contactNameLabel.text = listEntry.name ?? MainAppContext.shared.contactStore.fullName(for: listEntry.userId)
        phoneNumberLabel.text = listEntry.phoneNumber
    }

    private(set) var isContactSelected: Bool = false

    func setContact(selected: Bool, animated: Bool = false) {
        guard selected != isContactSelected else { return }

        isContactSelected = selected

        let image = isContactSelected ? UIImage(systemName: "checkmark.circle.fill") : UIImage(systemName: "circle")
        checkMark.image = image?.withRenderingMode(.alwaysTemplate)
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
