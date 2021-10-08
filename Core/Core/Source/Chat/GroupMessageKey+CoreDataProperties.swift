//
//  GroupMessageKey+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 10/1/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension GroupMessageKey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupMessageKey> {
        return NSFetchRequest<GroupMessageKey>(entityName: "GroupMessageKey")
    }

    @NSManaged public var chainIndex: Int32
    @NSManaged public var messageKey: Data
    @NSManaged public var senderStateBundle: SenderStateBundle

}

extension GroupMessageKey : Identifiable {

}
