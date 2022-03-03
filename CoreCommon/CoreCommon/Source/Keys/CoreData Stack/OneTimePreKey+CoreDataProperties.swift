//
//  OneTimePreKey+CoreDataProperties.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
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
