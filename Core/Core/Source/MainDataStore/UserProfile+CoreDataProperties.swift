//
//  UserProfile+CoreDataProperties.swift
//  Core
//
//  Created by Tanveer on 8/1/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension UserProfile {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfile> {
        return NSFetchRequest<UserProfile>(entityName: "UserProfile")
    }

    @NSManaged public var avatarID: String?
    @NSManaged public var friendshipStatusValue: Int16
    @NSManaged public var id: String
    @NSManaged public var isBlocked: Bool
    @NSManaged public var name: String
    @NSManaged public var username: String
}

extension UserProfile: Identifiable {

}
