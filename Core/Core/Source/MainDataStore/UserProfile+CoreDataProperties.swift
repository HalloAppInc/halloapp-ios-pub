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
import CoreCommon

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
    @NSManaged public var isFavorite: Bool

    @NSManaged public var posts: Set<FeedPost>
    @NSManaged public var comments: Set<FeedPostComment>
    @NSManaged public var messages: Set<ChatMessage>
}

extension UserProfile: Identifiable {

}

extension UserProfile {

    public var displayName: String {
        guard id != AppContext.shared.userData.userId else {
            return Localizations.meCapitalized
        }

        return name
    }
}
