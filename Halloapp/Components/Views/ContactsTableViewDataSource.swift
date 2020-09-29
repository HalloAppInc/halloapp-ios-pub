//
//  ContactsTableViewDataSource.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/24/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

@objc protocol IndexableContact {
    var collationName: String { get }
}

class ContactsTableViewDataSource<ItemIdentifierType>: UITableViewDiffableDataSource<String, ItemIdentifierType> where ItemIdentifierType: IndexableContact, ItemIdentifierType: Hashable {

    private class ContactsSection {
        let title: String
        var contacts: [ItemIdentifierType] = []

        init(title: String) {
            self.title = title
        }
    }

    var isSectioningEnabled = true
    let collation = UILocalizedIndexedCollation.current()

    private func contactSections(from contacts: [ItemIdentifierType]) -> [ContactsSection] {
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

    func reload(contacts: [ItemIdentifierType], animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        var dataSourceSnapshot = NSDiffableDataSourceSnapshot<String, ItemIdentifierType>()
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

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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

