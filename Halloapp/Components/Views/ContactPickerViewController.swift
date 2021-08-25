//
//  ContactPickerViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

fileprivate let cellReuseIdentifier = "ContactCell"
fileprivate let sectionHeaderReuseIdentifier = "SectionHeaderView"

@objc protocol IndexableContact {
    var collationName: String { get }
}

@objc protocol SearchableContact {
    var searchTokens: [String] { get }
}

class ContactPickerViewController<ContactType>: UITableViewController, UISearchResultsUpdating where ContactType: IndexableContact, ContactType: SearchableContact, ContactType: Hashable {

    final class DataSource: UITableViewDiffableDataSource<String, ContactType> {

        private class ContactsSection {
            let title: String
            var contacts: [ContactType] = []

            init(title: String) {
                self.title = title
            }
        }

        fileprivate var isSectioningEnabled = true

        private let collation = UILocalizedIndexedCollation.current()

        private func contactSections(from contacts: [ContactType]) -> [ContactsSection] {
            let sectionTitles = collation.sectionTitles
            let sections = sectionTitles.map({ ContactsSection(title: $0) })

            for contact in contacts {
                let selector = #selector(getter: IndexableContact.collationName)
                let sectionIndex = collation.section(for: contact, collationStringSelector: selector)
                let contactsSection = sections[sectionIndex]
                contactsSection.contacts.append(contact)
            }
            return sections.filter({ !$0.contacts.isEmpty })
        }

        func reload(contacts: [ContactType], animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
            var dataSourceSnapshot = NSDiffableDataSourceSnapshot<String, ContactType>()
            if isSectioningEnabled {
                let sections = contactSections(from: contacts)
                dataSourceSnapshot.appendSections(sections.map { $0.title } )
                for section in sections {
                    dataSourceSnapshot.appendItems(section.contacts, toSection: section.title)
                }
            } else {
                let theOnlySection = ""
                dataSourceSnapshot.appendSections([ theOnlySection ])
                dataSourceSnapshot.appendItems(contacts, toSection: theOnlySection)
            }
            apply(dataSourceSnapshot, animatingDifferences: animatingDifferences)
        }

        func titleForSection(_ section: Int) -> String? {
            guard isSectioningEnabled else { return nil }
            return snapshot().sectionIdentifiers[section]
        }

        override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
            guard isSectioningEnabled else { return nil }
            return collation.sectionIndexTitles
        }

        override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
            return collation.section(forSectionIndexTitle: index)
        }
    }

    private(set) var dataSource: DataSource!

    var contacts: [ContactType] {
        get {
            return displayContacts
        }
    }
    private var displayContacts: [ContactType]
    private var searchableContacts: [ContactType]
    private(set) var searchController: UISearchController!

    init(displayContacts: [ContactType], searchableContacts: [ContactType]) {
        self.displayContacts = displayContacts
        self.searchableContacts = searchableContacts
        super.init(style: .plain)
        reloadDataSource()
    }

    public func set(displayContacts: [ContactType], searchableContacts: [ContactType]) {
        self.displayContacts = displayContacts
        self.searchableContacts = searchableContacts
        reloadDataSource()
    }
    
    func reloadDataSource() {
        if isViewLoaded {
            dataSource.reload(contacts: contacts, animatingDifferences: false)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(contacts:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.register(ContactTableViewSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: sectionHeaderReuseIdentifier)
        
        dataSource = DataSource(tableView: tableView, cellProvider: { [weak self] (tableView, indexPath, contact) -> UITableViewCell? in
            guard let self = self else { return nil }
            let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            self.configure(cell: cell, with: contact)
            return cell
        })
        dataSource.isSectioningEnabled = !Self.isSearchResultsController
        dataSource.reload(contacts: contacts, animatingDifferences: false)

        // Search Results Controller doesn't have search bar.
        if !Self.isSearchResultsController {
            let searchResultsController = makeSearchResultsController()
            searchController = UISearchController(searchResultsController: searchResultsController)
            searchController.searchResultsUpdater = self
            searchController.searchBar.autocapitalizationType = .none
            searchController.definesPresentationContext = true
            searchController.searchBar.searchTextField.placeholder = Localizations.labelSearch
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
        }
    }

    // MARK: Customization Points

    class var isSearchResultsController: Bool { false }

    func configure(cell: ContactTableViewCell, with contact: ContactType) {

    }

    func makeSearchResultsController() -> ContactPickerViewController<ContactType> {
        fatalError("Not implemented")
    }

    // MARK: UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        guard let resultsController = searchController.searchResultsController as? ContactPickerViewController else { return }

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
        let contacts = searchableContacts.filter { finalCompoundPredicate.evaluate(with: $0) }
        resultsController.set(displayContacts: contacts, searchableContacts: [])
    }

    // MARK: Section Headers

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard !Self.isSearchResultsController else {
            return 0
        }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !Self.isSearchResultsController else {
            return nil
        }
        guard let title = dataSource.titleForSection(section) else {
            return nil
        }

        var view: ContactTableViewSectionHeaderView! = tableView.dequeueReusableHeaderFooterView(withIdentifier: sectionHeaderReuseIdentifier) as? ContactTableViewSectionHeaderView
        if view == nil {
            view = ContactTableViewSectionHeaderView(reuseIdentifier: sectionHeaderReuseIdentifier)
        }
        view.titleLabel.text = title
        return view
    }
}

private class ContactTableViewSectionHeaderView: UITableViewHeaderFooterView {
    private(set) var titleLabel: UILabel!

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        layoutMargins.top = 16

        backgroundView = UIView()
        backgroundView?.backgroundColor = .feedBackground

        titleLabel = UILabel()
        titleLabel.font = .gothamFont(forTextStyle: .headline, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        titleLabel.constrainMargins(to: self)
    }
}
