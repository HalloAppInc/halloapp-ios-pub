//
//  Mentions.swift
//  HalloApp
//
//  Created by Garrett on 7/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CoreData

extension Mentions {
    public static func mentionableUsers(forPostID postID: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> [MentionableUser] {
        guard let post = MainAppContext.shared.feedData.feedPost(with: postID, in: managedObjectContext) else { return [] }

        if let groupID = post.groupId {
            return mentionableUsers(forGroupID: groupID, in: managedObjectContext)
        }

        var contactSet = Set<UserID>()

        if post.userId != MainAppContext.shared.userData.userId {
            // Allow mentioning poster
            contactSet.insert(post.userId)
        } else {
            // If user is the post owner: we can mention everyone in the post audience since they should be able to see our post.
            // Fallback to all friends if audience is nil.
            if let audience = post.audience {
                contactSet.formUnion(audience.userIds)
            } else {
                let predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
                let friends = UserProfile.find(predicate: predicate, in: managedObjectContext)

                contactSet.formUnion(friends.map { $0.id })
            }
        }

        // Allow mentioning every mention from the post
        contactSet.formUnion(post.mentions.map { $0.userID })

        // Allow mentioning everyone who has commented on the post
        contactSet.formUnion(post.comments?.map { $0.userId } ?? [])

        // Allow mentioning everyone who has been mentioned in a comment
        contactSet.formUnion(post.comments?.flatMap { $0.mentions.map { $0.userID } } ?? [])

        // Disallow self mentions
        contactSet.remove(MainAppContext.shared.userData.userId)

        let fullNames = UserProfile.names(from: contactSet, in: managedObjectContext)

        return fullNames
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }
    
    public static func mentionableUsers(forGroupID groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> [MentionableUser] {
        guard let members = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: managedObjectContext)?.members else { return [] }
        var contactSet = Set(members.map { $0.userID })
        contactSet.remove(MainAppContext.shared.userData.userId)
        let fullNames = UserProfile.names(from: contactSet, in: managedObjectContext)
        return fullNames
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }
}
