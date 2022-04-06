//
//  Mentions.swift
//  HalloApp
//
//  Created by Garrett on 7/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon

extension Mentions {
    public static func mentionableUsers(forPostID postID: FeedPostID) -> [MentionableUser] {
        guard let post = MainAppContext.shared.feedData.feedPost(with: postID) else { return [] }

        if let groupID = post.groupId {
            return mentionableUsers(forGroupID: groupID)
        }

        var contactSet = Set<UserID>()

        if post.userId != MainAppContext.shared.userData.userId {
            // Allow mentioning poster
            contactSet.insert(post.userId)
        } else {
            // If user is the post owner: we can mention everyone in the post audience since they should be able to see our post.
            // Fallback to all contacts if audience is nil.
            if let audience = post.audience {
                contactSet.formUnion(audience.userIds)
            } else {
                contactSet.formUnion(MainAppContext.shared.contactStore.allRegisteredContactIDs())
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

        let fullNames = MainAppContext.shared.contactStore.fullNames(forUserIds: contactSet)

        return fullNames
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }
    
    public static func mentionableUsers(forGroupID groupID: GroupID) -> [MentionableUser] {
        guard let members = MainAppContext.shared.chatData.chatGroup(groupId: groupID)?.members else { return [] }
        var contactSet = Set(members.map { $0.userID })
        contactSet.remove(MainAppContext.shared.userData.userId)
        let fullNames = MainAppContext.shared.contactStore.fullNames(forUserIds: contactSet)
        return fullNames
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }
}
