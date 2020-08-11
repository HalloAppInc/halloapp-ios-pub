//
//  UserKeyBundle+CoreDataProperties.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension UserKeyBundle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserKeyBundle> {
        return NSFetchRequest<UserKeyBundle>(entityName: "UserKeyBundle")
    }

    @NSManaged public var identityPrivateEdKey: Data
    @NSManaged public var identityPublicEdKey: Data
    @NSManaged public var identityPrivateKey: Data
    @NSManaged public var identityPublicKey: Data
    @NSManaged public var oneTimePreKeysCounter: Int32
    @NSManaged public var signedPreKeys: Set<SignedPreKey>
    @NSManaged public var oneTimePreKeys: Set<OneTimePreKey>?
}

// MARK: Generated accessors for oneTimePreKeys
extension UserKeyBundle {

    @objc(addOneTimePreKeysObject:)
    @NSManaged public func addToOneTimePreKeys(_ value: OneTimePreKey)

    @objc(removeOneTimePreKeysObject:)
    @NSManaged public func removeFromOneTimePreKeys(_ value: OneTimePreKey)

    @objc(addOneTimePreKeys:)
    @NSManaged public func addToOneTimePreKeys(_ values: NSSet)

    @objc(removeOneTimePreKeys:)
    @NSManaged public func removeFromOneTimePreKeys(_ values: NSSet)

}

// MARK: Generated accessors for signedPreKeys
extension UserKeyBundle {

    @objc(addSignedPreKeysObject:)
    @NSManaged public func addToSignedPreKeys(_ value: SignedPreKey)

    @objc(removeSignedPreKeysObject:)
    @NSManaged public func removeFromSignedPreKeys(_ value: SignedPreKey)

    @objc(addSignedPreKeys:)
    @NSManaged public func addToSignedPreKeys(_ values: NSSet)

    @objc(removeSignedPreKeys:)
    @NSManaged public func removeFromSignedPreKeys(_ values: NSSet)

}
