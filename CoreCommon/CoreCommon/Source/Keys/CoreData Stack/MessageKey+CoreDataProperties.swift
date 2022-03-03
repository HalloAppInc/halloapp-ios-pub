//
//  MessageKey+CoreDataProperties.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension MessageKey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MessageKey> {
        return NSFetchRequest<MessageKey>(entityName: "MessageKey")
    }

    @NSManaged public var ephemeralKeyId: Int32
    @NSManaged public var chainIndex: Int32
    @NSManaged public var key: Data
    @NSManaged public var attribute: NSObject?
    @NSManaged public var messageKeyBundle: MessageKeyBundle

}
