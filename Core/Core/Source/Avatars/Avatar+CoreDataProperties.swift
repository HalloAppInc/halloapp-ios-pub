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

    @NSManaged public var userId: UserID?
    @NSManaged public var avatarId: String?
    @NSManaged public var relativeFilePath: String?
    @NSManaged public var statusValue: Int16
    
    /*
     The status of the avatar for a specific user.
     It will be finalized when we start to handle avatars for other users.
     unknown: Have not checked the avatar for this user yet
     checked: Checked the avatar for this user, and the user has one
     empty: Checked the avatar for this user, does not have an avatar
     */
    enum Status: Int16 {
        case unknown = 0
        case checked = 1
        case empty = 2
    }
    
    var statue: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
}
