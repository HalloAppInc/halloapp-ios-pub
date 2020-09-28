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

    private struct ContactsSection {
        let title: String
        var contacts: [ABContact]
    }

    let collation = UILocalizedIndexedCollation.current()

    private func contactSections(from contacts: [ABContact]) -> [ContactsSection] {
        let sectionTitles = collation.sectionTitles

        var sections: [ContactsSection] = []

        var currentSectionIndex = -1
        var currentSectionContacts: [ABContact] = []

        for contact in contacts {
            let indexName = contact.indexName ?? "#"

            // Don't ever allow repeating sections - once you get to "#" there's no coming back.
            let sectionIndex = max(currentSectionIndex, collation.section(for: indexName, collationStringSelector: Selector("self")))

            // Section title changed - wrap all accumulated contacts into a section.
            if sectionIndex != currentSectionIndex {
                if !currentSectionContacts.isEmpty {
                    let sectionTitle = sectionTitles[currentSectionIndex]
                    let section = ContactsSection(title: sectionTitle, contacts: currentSectionContacts)
                    sections.append(section)
                }

                currentSectionIndex = sectionIndex
                currentSectionContacts = []
            }

            currentSectionContacts.append(contact)
        }

        // Last section.
        if !currentSectionContacts.isEmpty {
            let sectionTitle = sectionTitles[currentSectionIndex]
            let section = ContactsSection(title: sectionTitle, contacts: currentSectionContacts)
            sections.append(section)
        }
        return sections
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

