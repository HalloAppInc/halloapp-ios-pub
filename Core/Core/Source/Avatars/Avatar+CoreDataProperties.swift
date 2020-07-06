//
//  Avatar+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 6/9/20.
//
//

import CoreData
import UIKit


extension Avatar {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Avatar> {
        return NSFetchRequest<Avatar>(entityName: "Avatar")
    }

    @NSManaged public var userId: UserID
    @NSManaged public var avatarId: String? // If avatar id is nil, it means the user removed their avatar
    @NSManaged public var relativeFilePath: String?
}
