//
//  OneTimePreKey+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 7/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension OneTimePreKey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OneTimePreKey> {
        return NSFetchRequest<OneTimePreKey>(entityName: "OneTimePreKey")
    }

    @NSManaged public var id: Int32
    @NSManaged public var privateKey: Data
    @NSManaged public var publicKey: Data
    @NSManaged public var userKeyBundle: UserKeyBundle

}
