//
//  MessageKey+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 7/19/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension MessageKey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MessageKey> {
        return NSFetchRequest<MessageKey>(entityName: "MessageKey")
    }

    @NSManaged var ephemeralKeyId: Int32
    @NSManaged var chainIndex: Int32
    @NSManaged var key: Data
    @NSManaged var messageKeyBundle: MessageKeyBundle

}
