//
//  ContactsTableViewDataSource.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/24/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class ContactsTableViewDataSource: UITableViewDiffableDataSource<String, ABContact> {

    private class ContactsSection {
        let title: String
        var contacts: [ABContact] = []

        init(title: String) {
            self.title = title
        }
    }

    let collation = UILocalizedIndexedCollation.current()

    private func contactSections(from contacts: [ABContact]) -> [ContactsSection] {
        let sectionTitles = collation.sectionTitles
        let sections = sectionTitles.map({ ContactsSection(title: $0) })

        for contact in contacts {
            let indexName = contact.indexName ?? "#"
            let sectionIndex = collation.section(for: indexName, collationStringSelector: Selector("self"))
            let contactsSection = sections[sectionIndex]
            contactsSection.contacts.append(contact)
        }
        return sections.filter({ !$0.contacts.isEmpty })
    }

    func reload(contacts: [ABContact], animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        let sections = contactSections(from: contacts)
        var dataSourceSnapshot = NSDiffableDataSourceSnapshot<String, ABContact>()
        dataSourceSnapshot.appendSections(sections.map { $0.title } )
        for section in sections {
            dataSourceSnapshot.appendItems(section.contacts, toSection: section.title)
        }
        apply(dataSourceSnapshot, animatingDifferences: animatingDifferences)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return snapshot().sectionIdentifiers[section]
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return collation.sectionIndexTitles
    }

    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return collation.section(forSectionIndexTitle: index)
    }
}

