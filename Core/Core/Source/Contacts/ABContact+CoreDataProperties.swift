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
        case unknown = 0
        case `in` = 1
        case `out` = 2
        case invalid = 3
    }

    @NSManaged var fullName: String?
    @NSManaged var givenName: String?
    @NSManaged var identifier: String?
    @NSManaged var normalizedPhoneNumber: NormalizedPhoneNumber?
    @NSManaged var phoneNumber: String?
    @NSManaged var searchTokenList: String?
    @NSManaged var sort: Int32
    @NSManaged var statusValue: Int16
    @NSManaged var userId: UserID?
    @NSManaged var phoneNumberHash: String?

    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
}
