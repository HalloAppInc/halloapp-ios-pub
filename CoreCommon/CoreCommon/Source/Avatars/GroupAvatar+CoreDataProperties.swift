//
//  GroupAvatar+CoreDataProperties.swift
//  Core
//
//  Created by Tony Jiang on 9/24/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
//

import CoreData
import Foundation


extension GroupAvatar {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupAvatar> {
        return NSFetchRequest<GroupAvatar>(entityName: "GroupAvatar")
    }

    @NSManaged public var groupID: GroupID
    @NSManaged public var avatarID: String?
    @NSManaged public var relativeFilePath: String?

}

