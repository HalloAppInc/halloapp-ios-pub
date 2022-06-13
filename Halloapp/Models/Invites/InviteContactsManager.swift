//
//  InviteContactsManager.swift
//  HalloApp
//
//  Created by Garrett on 3/25/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CoreData
import Foundation

final class InviteContactsManager: NSObject {

    enum Sort {
        case name, numPotentialContacts
    }

    var contactsChanged: (() -> Void)?
    var hideInvitedAndHidden: Bool
    
    init(hideInvitedAndHidden: Bool = false, sort: Sort = .name) {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        var predicates: [NSPredicate] = []
        predicates.append(NSPredicate(format: "normalizedPhoneNumber != nil"))

        if hideInvitedAndHidden {
            // Contacts with non-nil `userId` are preserved to filter out other phone numbers from joined contacts later
            predicates.append(NSPredicate(format: "hideInSuggestedInvites == false"))
        }
        
        predicates.append(NSPredicate(format: "userId == nil OR userId != %@", MainAppContext.shared.userData.userId))

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        switch sort {
        case .name:
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        case .numPotentialContacts:
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.numPotentialContacts, ascending: false) ]
        }

        self.hideInvitedAndHidden = hideInvitedAndHidden
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

    func contacts(searchString: String? = nil) -> [InviteContact] {
        guard let searchString = searchString else {
            let uniqueContacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: fetchedResultsController.fetchedObjects ?? [])
            var result = ABContact.contactsRemovingOtherPhoneNumbersFromJoinedContacts(allContacts: uniqueContacts)
            if hideInvitedAndHidden {
                result.removeAll { $0.userId != nil }
            }
            return result.compactMap { InviteContact(from: $0) }
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

    private var _randomSelection: [InviteContact]?

    var randomSelection: [InviteContact] {
        if let randomSelection = _randomSelection {
            return randomSelection
        } else {
            // take a random 20 of the top 50 contacts, determined by sort
            let randomSelection = Array(contacts()
                .filter { !$0.fullName.localizedCaseInsensitiveContains(Localizations.contactSpamName) && ($0.friendCount ?? 0) > 0 }
                .prefix(50)
                .shuffled()
                .prefix(10))
            _randomSelection = randomSelection
            return randomSelection
        }
    }
}

extension InviteContactsManager: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let randomSelection = _randomSelection {
            let validNormalizedPhoneNumbers = Set(fetchedResultsController.fetchedObjects?.compactMap { $0.normalizedPhoneNumber } ?? [])

            _randomSelection = randomSelection.filter {
                validNormalizedPhoneNumbers.contains($0.normalizedPhoneNumber)
            }
        }

        contactsChanged?()
    }
}

struct InviteContact: Hashable, Equatable {
    var fullName: String
    var givenName: String?
    var normalizedPhoneNumber: String
    var friendCount: Int?
    var userID: UserID?
    var formattedPhoneNumber: String
    var identifier: String?
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
        self.friendCount = fullName.localizedCaseInsensitiveContains(Localizations.contactSpamName) ? 0 : Int(abContact.numPotentialContacts)
        self.identifier = abContact.identifier
    }
}

extension Localizations {

    static var contactSpamName: String {
        NSLocalizedString("invitemanager.spam",
                          value: "spam",
                          comment: "Contacts including this in their name are excluded from the invite carousel")
    }
}
