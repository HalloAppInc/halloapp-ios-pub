//
//  Avatar+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 6/9/20.
//
//

import CoreCommon
import CoreData
import UIKit


extension Avatar {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Avatar> {
        return NSFetchRequest<Avatar>(entityName: "Avatar")
    }

    @NSManaged public var userId: UserID
    /*
     If avatarId is nil, it means the user does not have an avatar
     If avatarId is "", it means the user has one before but choose to remove it later
     */
    @NSManaged public var avatarId: String?
    @NSManaged public var relativeFilePath: String?
}
