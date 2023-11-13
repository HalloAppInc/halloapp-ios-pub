//
//  UserProfile+Updates.swift
//  Core
//
//  Created by Tanveer on 9/13/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreData
import CoreCommon
import CocoaLumberjackSwift

extension UserProfile {

    public func update(with serverProfile: Server_HalloappUserProfile) {
        id = String(serverProfile.uid)

        if serverProfile.username != username {
            username = serverProfile.username
        }

        if serverProfile.name != name {
            name = serverProfile.name
        }

        if serverProfile.avatarID != avatarID {
            avatarID = serverProfile.avatarID
            AppContext.shared.avatarStore.addAvatar(id: serverProfile.avatarID, for: id)
        }

        let serverStatus = serverProfile.status.userProfileFriendshipStatus
        if serverStatus != friendshipStatus {
            friendshipStatus = serverStatus
        }

        if serverProfile.blocked != isBlocked {
            isBlocked = serverProfile.blocked
        }

        let serverLinks = serverProfile.links.map { ProfileLink(serverLink: $0) }
        if serverLinks != links {
            links = serverLinks
        }
    }

    public class func updateNames(with mapping: [UserID: String]) {
        guard !mapping.isEmpty else {
            return
        }

        AppContext.shared.mainDataStore.saveSeriallyOnBackgroundContext { context in
            findOrCreate(with: Array(mapping.keys), in: context)
                .forEach { profile in
                    profile.name = mapping[profile.id] ?? profile.name
                }
        }
    }
}

// MARK: - Removing content

extension UserProfile {

    public struct ContentRemovalOptions: OptionSet {
        public let rawValue: Int16

        fileprivate static let feedPosts = Self(rawValue: 1 << 0)
        fileprivate static let allPosts = Self(rawValue: 1 << 1)
        fileprivate static let comments = Self(rawValue: 1 << 2)
        fileprivate static let friendActivity = Self(rawValue: 1 << 3)

        public static let unfriended: Self = [.feedPosts, .friendActivity]
        public static let blocked: Self = [.allPosts, .comments, .friendActivity]
        public static let deletedAccount: Self = [.allPosts, .comments, .friendActivity]

        public init(rawValue: Int16) {
            self.rawValue = rawValue
        }
    }

    public class func removeContent(for userID: UserID, in context: NSManagedObjectContext, options: ContentRemovalOptions) {
        guard let user = UserProfile.find(with: userID, in: context) else {
            DDLogInfo("UserProfile/remove-content/user not found")
            return
        }

        if options.contains(.comments) {
            removeComments(for: user, in: context)
        }
        if options.contains(.allPosts) {
            removePosts(for: user, includeGroups: true, in: context)
        } else if options.contains(.feedPosts) {
            removePosts(for: user, includeGroups: false, in: context)
        }
        if options.contains(.friendActivity) {
            removeFriendActivity(for: userID, in: context)
        }
    }

    private class func removeComments(for user: UserProfile, in context: NSManagedObjectContext) {
        DDLogInfo("UserProfile/removeComments [\(user.id)]")

        let comments = user.posts
            .flatMap { post in
                post.comments.flatMap { $0 } ?? []
            }

        remove(comments, in: context)
    }

    private class func removePosts(for user: UserProfile, includeGroups: Bool, in context: NSManagedObjectContext) {
        DDLogInfo("UserProfile/removeFeedPosts [\(user.id)]")
        let posts = includeGroups ? user.posts : user.posts.filter { $0.groupID == nil }

        for post in posts {
            if let comments = post.comments {
                remove(Array(comments), in: context)
            }

            post.allAssociatedMedia.forEach { AppContext.shared.coreFeedData.deleteMedia(mediaItem: $0) }
            post.linkPreviews?.forEach { context.delete($0) }
            post.contentResendInfo?.forEach { context.delete($0) }
            post.reactions?.forEach { context.delete($0) }

            if let info = post.info {
                context.delete(info)
            }

            context.delete(post)
        }
    }

    private class func remove(_ comments: [FeedPostComment], in context: NSManagedObjectContext) {
        for comment in comments {
            comment.allAssociatedMedia.forEach { AppContext.shared.coreFeedData.deleteMedia(mediaItem: $0) }
            comment.linkPreviews?.forEach { context.delete($0) }
            comment.reactions?.forEach { context.delete($0) }
            comment.contentResendInfo?.forEach { context.delete($0) }

            context.delete(comment)
        }
    }

    private class func removeFriendActivity(for userID: UserID, in context: NSManagedObjectContext) {
        DDLogInfo("UserProfile/removeFriendActivity [\(userID)]")
        guard let activity = FriendActivity.find(with: userID, in: context) else {
            return
        }

        context.delete(activity)
    }
}
