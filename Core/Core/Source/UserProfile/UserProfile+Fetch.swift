//
//  UserProfile+Fetch.swift
//  Core
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData
import CocoaLumberjackSwift

extension UserProfile {

    public class func find(with userID: UserID, in context: NSManagedObjectContext) -> UserProfile? {
        findFirst(predicate: NSPredicate(format: "id = %@", userID), in: context)
    }

    public class func find(with userIDs: [UserID], in context: NSManagedObjectContext) -> [UserProfile] {
        find(predicate: NSPredicate(format: "id in %@", userIDs), in: context)
    }

    public class func findOrCreate(with userID: UserID, in context: NSManagedObjectContext) -> UserProfile {
        let userProfile: UserProfile

        if let profile = find(with: userID, in: context) {
            userProfile = profile
        } else {
            let profile = UserProfile(context: context)
            profile.id = userID
            userProfile = profile
        }

        return userProfile
    }

    public class func findOrCreate(with userIDs: [UserID], in context: NSManagedObjectContext) -> [UserProfile] {
        var profiles = find(with: userIDs, in: context)

        if profiles.count != userIDs.count {
            let existingProfileIDs = profiles.reduce(into: Set<UserID>()) { $0.insert($1.id) }

            for userID in userIDs where !existingProfileIDs.contains(userID) {
                let profile = UserProfile(context: context)
                profile.id = userID
                profiles.append(profile)
            }
        }

        return profiles
    }

    public class func find(predicate: NSPredicate, in context: NSManagedObjectContext) -> [UserProfile] {
        let request = UserProfile.fetchRequest()
        request.predicate = predicate

        do {
            return try context.fetch(request)
        } catch {
            DDLogError("UserProfileData/userProfiles/failed to fetch profile with predicate \(predicate): \(error)")
            return []
        }
    }

    public class func findFirst(predicate: NSPredicate, in context: NSManagedObjectContext) -> UserProfile? {
        let request = UserProfile.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            DDLogError("UserProfileData/userProfiles/failed to fetch profile with predicate \(predicate): \(error)")
            return nil
        }
    }
}
