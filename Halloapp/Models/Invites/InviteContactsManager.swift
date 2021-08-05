//
//  InviteContactsManager.swift
//  HalloApp
//
//  Created by Garrett on 3/25/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreData
import Foundation

final class InviteContactsManager: NSObject {

    override init() {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber != nil && (userId == nil OR userId != %@)", MainAppContext.shared.userData.userId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ABContact>(
            fetchRequest: fetchRequest,
            managedObjectContext: MainAppContext.shared.contactStore.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        super.init()
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
        }
        catch {
            fatalError("Failed to fetch contacts. \(error)")
        }
    }

    let fetchedResultsController: NSFetchedResultsController<ABContact>

    func contacts(searchString: String?) -> [InviteContact] {
        guard let searchString = searchString else {
            let uniqueContacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: fetchedResultsController.fetchedObjects ?? [])
            return uniqueContacts.compactMap { InviteContact(from: $0) }
        }

        let searchItems = searchString
            .trimmingCharacters(in: CharacterSet.whitespaces)
            .components(separatedBy: " ")

        let andPredicates: [NSPredicate] = searchItems.map { (searchString) in
            NSComparisonPredicate(leftExpression: NSExpression(forKeyPath: "searchTokens"),
                                  rightExpression: NSExpression(forConstantValue: searchString),
                                  modifier: .any,
                                  type: .contains,
                                  options: [.caseInsensitive, .diacriticInsensitive])
        }

        let finalCompoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        let filteredContacts = (fetchedResultsController.fetchedObjects ?? [])
            .filter { finalCompoundPredicate.evaluate(with: $0) }
            .compactMap { InviteContact(from: $0) }

        // Return uniqued contacts
        var set = Set<InviteContact>()
        return filteredContacts.reduce([]) { output, contact in
            guard !set.contains(contact) else { return output }
            set.insert(contact)
            return output + [contact]
        }
    }
}

extension InviteContactsManager: NSFetchedResultsControllerDelegate {
}

struct InviteContact: Hashable, Equatable {
    var fullName: String
    var givenName: String?
    var normalizedPhoneNumber: String
    var friendCount: Int?
    var userID: UserID?
    var formattedPhoneNumber: String
}

extension InviteContact {
    init?(from abContact: ABContact) {
        guard let fullName = abContact.fullName, let number = abContact.normalizedPhoneNumber else {
            return nil
        }
        self.fullName = fullName
        self.givenName = abContact.givenName
        self.normalizedPhoneNumber = number
        self.formattedPhoneNumber = abContact.phoneNumber ?? "+\(number)".formattedPhoneNumber
        self.userID = abContact.userId
        self.friendCount = Int(abContact.numPotentialContacts)
    }
}
