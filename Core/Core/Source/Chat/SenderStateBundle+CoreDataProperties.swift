//
//  SenderStateBundle+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 10/1/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension SenderStateBundle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SenderStateBundle> {
        return NSFetchRequest<SenderStateBundle>(entityName: "SenderStateBundle")
    }

    @NSManaged public var chainKey: Data
    @NSManaged public var currentChainIndex: Int32
    @NSManaged public var publicSignatureKey: Data
    @NSManaged public var userId: String
    @NSManaged public var groupSessionKeyBundle: GroupSessionKeyBundle
    @NSManaged public var homeSessionKeyBundle: HomeSessionKeyBundle
    @NSManaged public var messageKeys: Set<GroupMessageKey>?

}

// MARK: Generated accessors for messageKeys
extension SenderStateBundle {

    @objc(addMessageKeysObject:)
    @NSManaged public func addToMessageKeys(_ value: GroupMessageKey)

    @objc(removeMessageKeysObject:)
    @NSManaged public func removeFromMessageKeys(_ value: GroupMessageKey)

    @objc(addMessageKeys:)
    @NSManaged public func addToMessageKeys(_ values: NSSet)

    @objc(removeMessageKeys:)
    @NSManaged public func removeFromMessageKeys(_ values: NSSet)

}

extension SenderStateBundle : Identifiable {

}
