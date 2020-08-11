//
//  MessageKeyBundle+CoreDataProperties.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension MessageKeyBundle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MessageKeyBundle> {
        return NSFetchRequest<MessageKeyBundle>(entityName: "MessageKeyBundle")
    }

    @NSManaged public var userId: String
    @NSManaged public var inboundIdentityPublicEdKey: Data?
     
    @NSManaged public var inboundSignedPrePublicKey: Data?
    
    @NSManaged public var inboundEphemeralPublicKey: Data?
    @NSManaged public var inboundEphemeralKeyId: Int32
    @NSManaged public var inboundChainKey: Data
    @NSManaged public var inboundPreviousChainLength: Int32
    @NSManaged public var inboundChainIndex: Int32
    
    @NSManaged public var rootKey: Data
    
    @NSManaged public var outboundEphemeralPrivateKey: Data
    @NSManaged public var outboundEphemeralPublicKey: Data
    @NSManaged public var outboundEphemeralKeyId: Int32
    @NSManaged public var outboundChainKey: Data
    @NSManaged public var outboundPreviousChainLength: Int32
    @NSManaged public var outboundChainIndex: Int32
    
    @NSManaged public var outboundIdentityPublicEdKey: Data?
    @NSManaged public var outboundOneTimePreKeyId: Int32
    
    @NSManaged public var messageKeys: Set<MessageKey>?

}

// MARK: Generated accessors for messageKeys
extension MessageKeyBundle {

    @objc(addMessageKeysObject:)
    @NSManaged public func addToMessageKeys(_ value: MessageKey)

    @objc(removeMessageKeysObject:)
    @NSManaged public func removeFromMessageKeys(_ value: MessageKey)

    @objc(addMessageKeys:)
    @NSManaged public func addToMessageKeys(_ values: NSSet)

    @objc(removeMessageKeys:)
    @NSManaged public func removeFromMessageKeys(_ values: NSSet)

}
