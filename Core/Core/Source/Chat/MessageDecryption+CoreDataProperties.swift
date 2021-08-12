//
//  MessageDecryption+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 8/11/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CoreData
import Foundation

extension MessageDecryption {

    @nonobjc class func fetchRequest() -> NSFetchRequest<MessageDecryption> {
        return NSFetchRequest<MessageDecryption>(entityName: "MessageDecryption")
    }

    @NSManaged public var messageID: String
    @NSManaged public var timeReceived: Date?
    @NSManaged public var userAgentSender: String?
    @NSManaged public var userAgentReceiver: String?
    @NSManaged public var hasBeenReported: Bool
    @NSManaged public var decryptionResult: String?
    @NSManaged public var rerequestCount: Int32
    @NSManaged public var timeDecrypted: Date?
    @NSManaged public var isSilent: Bool
}
