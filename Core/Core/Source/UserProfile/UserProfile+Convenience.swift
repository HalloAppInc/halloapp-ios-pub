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

    /// - Returns: An attributed string where mention placeholders have been replaced with contact names.
    ///            User IDs are retrievable via the .userMention attribute.
    public class func text(with mentions: [FeedMentionProtocol], collapsedText: String?, in context: NSManagedObjectContext) -> NSAttributedString? {
        guard let collapsedText else {
            return nil
        }

        let names = UserProfile.find(with: mentions.map { $0.userID }, in: context)
            .reduce(into: [:]) {
                $0[$1.id] = $1.name
            }

        return MentionText(collapsedText: collapsedText, mentionArray: mentions).expandedText { userID in
            names[userID] ?? Localizations.unknownContact
        }
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


    public class func allUserIDs(friendshipStatus: FriendshipStatus, in context: NSManagedObjectContext) -> Set<UserID> {
        let fetchRequest = NSFetchRequest<NSDictionary>()
        fetchRequest.entity = UserProfile.entity()
        fetchRequest.predicate = NSPredicate(format: "%K == %d", #keyPath(UserProfile.friendshipStatusValue), friendshipStatus.rawValue)
        fetchRequest.propertiesToFetch = [
            NSExpression(forKeyPath: \UserProfile.id).keyPath,
        ]
        fetchRequest.resultType = .dictionaryResultType

        return (try? Set(context.fetch(fetchRequest).compactMap { $0["id"] as? UserID })) ?? []
    }
}
