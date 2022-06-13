//
//  ABContact+CoreDataProperties.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

public extension ABContact {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ABContact> {
        return NSFetchRequest<ABContact>(entityName: "ABContact")
    }

    typealias NormalizedPhoneNumber = String

    // Raw values are persisted as ABContact.statusValue. Do not change.
    enum Status: Int16 {
        case unknown = 0    // indicates contact is new and unprocessed yet.
        case `in` = 1       // deprecated value - no longer used.
        case `out` = 2      // deprecated value - no longer used.
        case invalid = 3    // indicates contact is invalid.
        case processed = 4  // indicates contact has been processed and sent to the server.
    }

    @NSManaged var fullName: String?
    @NSManaged var givenName: String?
    @NSManaged var indexName: String?
    @NSManaged var identifier: String?
    @NSManaged var normalizedPhoneNumber: NormalizedPhoneNumber?
    @NSManaged var phoneNumber: String?
    @NSManaged var searchTokenList: String?
    @NSManaged var sort: Int32
    @NSManaged var statusValue: Int16
    @NSManaged var userId: UserID?
    @NSManaged var phoneNumberHash: String?
    @NSManaged var numPotentialContacts: Int64
    @NSManaged var hideInSuggestedInvites: Bool

    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    @objc var searchTokens: [String] {
        get {
            searchTokenList?.components(separatedBy: " ") ?? []
        }
    }

    static func contactsWithUniquePhoneNumbers(allContacts: [ABContact]) -> [ABContact] {
        var uniqueContacts: [ABContact] = []
        var contactIdentifiers = Set<String>()
        for contact in allContacts {
            guard let _ = contact.identifier,
                  let phoneNumber = contact.normalizedPhoneNumber else
            {
                uniqueContacts.append(contact)
                continue
            }
            let normalizedId = "\(phoneNumber)"
            guard !contactIdentifiers.contains(normalizedId) else {
                continue
            }
            uniqueContacts.append(contact)
            contactIdentifiers.insert(normalizedId)
        }
        return uniqueContacts
    }
    
    static func contactsRemovingOtherPhoneNumbersFromJoinedContacts(allContacts: [ABContact]) -> [ABContact] {
        let joinedIdentifiers = Set<String?>(
            allContacts.lazy.compactMap { (contact: ABContact) -> String? in
                if let identifier = contact.identifier, contact.userId != nil {
                    return identifier
                } else {
                    return nil
                }
            }
        )
        return allContacts.filter {
            !joinedIdentifiers.contains($0.identifier) || $0.userId != nil
        }
    }
}
