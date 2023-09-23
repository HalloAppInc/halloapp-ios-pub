//
//  UserProfile+Convenience.swift
//  Core
//
//  Created by Tanveer on 9/12/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

extension UserProfile {

    public class func names(from ids: Set<UserID>, in context: NSManagedObjectContext) -> [UserID: String] {
        let ids = Array(ids)
        var map = [UserID: String]()

        context.performAndWait {
            map = UserProfile.find(with: ids, in: context)
                .reduce(into: [:]) {
                    $0[$1.id] = $1.name
                }
        }

        return map
    }

    public class func users(in privacyList: PrivacyListType, in context: NSManagedObjectContext) -> [UserProfile]? {
        // TODO: migrate away from all of the PrivacyList stuff
        let predicate: NSPredicate
        switch privacyList {
        case .all:
            predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
        case .whitelist:
            predicate = NSPredicate(format: "friendshipStatusValue == %d AND isFavorite == YES", UserProfile.FriendshipStatus.friends.rawValue)
        default:
            return nil
        }

        return find(predicate: predicate, in: context)
    }
}
