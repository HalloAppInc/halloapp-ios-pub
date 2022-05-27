//
//  CoreFeedData.swift
//  Core
//
//  Created by Murali Balusu on 5/5/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import SwiftProtobuf
import CoreData
import CocoaLumberjackSwift


// TODO: (murali@): reuse this logic in FeedData

public class CoreFeedData {
    private let service: CoreService
    private let mainDataStore: MainDataStore

    public init(service: CoreService, mainDataStore: MainDataStore) {
        self.mainDataStore = mainDataStore
        self.service = service
    }

    public func feedPost(with feedPostId: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> FeedPost? {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", feedPostId)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            return posts.first
        } catch {
            DDLogError("CoreFeedData/fetch-posts/error  [\(error)]")
            return nil
        }
    }

    public func feedComment(with feedPostCommentID: FeedPostCommentID, in managedObjectContext: NSManagedObjectContext) -> FeedPostComment? {
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", feedPostCommentID)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let comments = try managedObjectContext.fetch(fetchRequest)
            return comments.first
        } catch {
            DDLogError("CoreFeedData/fetch-comments/error  [\(error)]")
            return nil
        }
    }

    public func savePostData(postData: PostData, in groupID: GroupID?, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext({ context in

            if let existingPost = self.feedPost(with: postData.id, in: context) {
                // If status = .none for an existing post, we need to process the newly received post.
                if existingPost.status == .none {
                    DDLogInfo("CoreFeedData/savePostData/existing [\(existingPost.id)]/status is none/need to update")
                } else if existingPost.status == .rerequesting && postData.status == .received {
                    // If status = .rerequesting for an existing post.
                    // We check if we already used the unencrypted payload as fallback.
                    // If we already have content - then just update the status and return.
                    // If we dont have the content already and are still waiting, then we need to process the newly received post.
                    switch existingPost.postData.content {
                    case .waiting:
                        DDLogInfo("CoreFeedData/savePostData/existing [\(existingPost.id)]/content is waiting/need to update")
                    default:
                        DDLogInfo("CoreFeedData/savePostData/existing [\(existingPost.id)]/update status and return")
                        existingPost.status = .incoming
                        return
                    }
                } else {
                    DDLogError("CoreFeedData/savePostData/existing [\(existingPost.id)], ignoring")
                    return
                }
            }

            DDLogInfo("CoreFeedData/savePostData [\(postData.id)]")
            let feedPost: FeedPost
            if let existingPost = self.feedPost(with: postData.id, in: context) {
                feedPost = existingPost
            } else {
                feedPost = FeedPost(context: context)
            }

            feedPost.id = postData.id
            feedPost.userID = postData.userId
            feedPost.groupId = groupID
            feedPost.rawText = postData.text
            feedPost.timestamp = postData.timestamp
            feedPost.isMoment = postData.isMoment
            feedPost.lastUpdated = Date()
            feedPost.hasBeenProcessed = hasBeenProcessed

            // Status
            switch postData.content {
            case .album, .text, .voiceNote, .moment:
                if postData.status == .rerequesting {
                    feedPost.status = .rerequesting
                } else {
                    feedPost.status = .incoming
                }
            case .retracted:
                DDLogError("CoreFeedData/savePostData/incoming-retracted-post [\(postData.id)]")
                feedPost.status = .retracted
            case .unsupported(let data):
                feedPost.status = .unsupported
                feedPost.rawData = data
            case .waiting:
                feedPost.status = .rerequesting
                if postData.status != .rerequesting {
                    DDLogError("CoreFeedData/savePostData/invalid content [\(postData.id)] with status: \(postData.status)")
                }
            }

            // Mentions
            feedPost.mentions = postData.orderedMentions.map {
                MentionData(index: $0.index, userID: $0.userID, name: $0.name)
            }

            // Post Audience
            if let audience = postData.audience {
                let feedPostInfo = ContentPublishInfo(context: context)
                feedPostInfo.audienceType = audience.audienceType
                feedPostInfo.receipts = audience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPost.info = feedPostInfo
            }

            // Process link preview if present
            postData.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("CoreFeedData/savePostData/new/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: context)
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                linkPreviewData.previewImages.forEach { previewMedia in
                    let media = CommonMedia(context: context)
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                }
                linkPreview.post = feedPost
            }

            // Process post media
            for (index, media) in postData.orderedMedia.enumerated() {
                DDLogDebug("CoreFeedData/savePostData/new/add-media [\(media.url!)]")
                let feedMedia = CommonMedia(context: context)
                switch media.type {
                case .image:
                    feedMedia.type = .image
                case .video:
                    feedMedia.type = .video
                case .audio:
                    feedMedia.type = .audio
                }
                feedMedia.status = .none
                feedMedia.url = media.url
                feedMedia.size = media.size
                feedMedia.key = media.key
                feedMedia.order = Int16(index)
                feedMedia.sha256 = media.sha256
                feedMedia.post = feedPost
                feedMedia.blobVersion = media.blobVersion
                feedMedia.chunkSize = media.chunkSize
                feedMedia.blobSize = media.blobSize
            }
        }, completion: completion)
    }

    public func saveCommentData(commentData: CommentData, in groupID: GroupID?, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext({ context in

            if let existingComment = self.feedComment(with: commentData.id, in: context) {
                // If status = .none for an existing comment, we need to process the newly received comment.
                if existingComment.status == .none {
                    DDLogInfo("CoreFeedData/saveCommentData/existing [\(existingComment.id)]/status is none/need to update")
                } else if existingComment.status == .rerequesting && commentData.status == .received {
                    // If status = .rerequesting for an existing comment.
                    // We check if we already used the unencrypted payload as fallback.
                    // If we already have content - then just update the status and return.
                    // If we dont have the content already and are still waiting, then we need to process the newly received comment.
                    switch existingComment.commentData.content {
                    case .waiting:
                        DDLogInfo("CoreFeedData/saveCommentData/existing [\(existingComment.id)]/content is waiting/need to update")
                    default:
                        DDLogInfo("CoreFeedData/saveCommentData/existing [\(existingComment.id)]/update status and return")
                        existingComment.status = .incoming
                        return
                    }
                } else {
                    DDLogError("CoreFeedData/saveCommentData/existing [\(existingComment.id)], ignoring")
                    return
                }
            }

            DDLogInfo("CoreFeedData/saveCommentData [\(commentData.id)]")
            let feedComment: FeedPostComment
            if let existingComment = self.feedComment(with: commentData.id, in: context) {
                feedComment = existingComment
            } else {
                feedComment = FeedPostComment(context: context)
            }

            // Find comment's post.
            let feedPost: FeedPost
            if let post = self.feedPost(with: commentData.feedPostId, in: context) {
                DDLogInfo("CoreFeedData/saveCommentData/existing-post [\(commentData.feedPostId)]")
                feedPost = post
            } else if groupID != nil {
                // Create a post only for missing group posts.
                DDLogInfo("CoreFeedData/saveCommentData/missing-post [\(commentData.feedPostId)]/creating one")
                feedPost = FeedPost(context: context)
                feedPost.id = commentData.feedPostId
                feedPost.status = .rerequesting
                feedPost.userId = ""
                feedPost.timestamp = Date()
                feedPost.groupId = groupID
                feedPost.lastUpdated = Date()
            } else {
                DDLogError("CoreFeedData/saveCommentData/missing-post [\(commentData.feedPostId)]/skip comment")
                return
            }

             // Additional check: post's groupId must match groupId of the comment.
            guard feedPost.groupId == groupID else {
                DDLogError("CoreFeedData/saveCommentData/missing-post [\(commentData.feedPostId)]/skip comment")
                return
            }

            // Check if post has been retracted.
            guard !feedPost.isPostRetracted else {
                DDLogError("CoreFeedData/saveCommentData/missing-post [\(commentData.feedPostId)]/skip comment")
                return
            }

            // Find parent if necessary.
            var parentComment: FeedPostComment? = nil
            if let parentId = commentData.parentId, !parentId.isEmpty {
                parentComment = self.feedComment(with: parentId, in: context)
                if parentComment == nil {
                    DDLogInfo("CoreFeedData/saveCommentData/missing-parent/[\(commentData.id)] - [\(parentId)]/creating one")
                    parentComment = FeedPostComment(context: context)
                    parentComment?.id = parentId
                    parentComment?.post = feedPost
                    parentComment?.timestamp = Date()
                    parentComment?.userId = ""
                    parentComment?.rawText = ""
                    parentComment?.status = .rerequesting
                }
            }

            feedComment.id = commentData.id
            feedComment.userId = commentData.userId
            feedComment.parent = parentComment
            feedComment.post = feedPost
            feedComment.timestamp = commentData.timestamp
            feedComment.rawText = commentData.text
            feedComment.hasBeenProcessed = hasBeenProcessed

            // Status
            switch commentData.content {
            case .album, .text, .voiceNote:
                if commentData.status == .rerequesting {
                    feedComment.status = .rerequesting
                } else {
                    feedComment.status = .incoming
                }
            case .retracted:
                DDLogError("CoreFeedData/saveCommentData/incoming-retracted-comment [\(commentData.id)]")
                feedComment.status = .retracted
            case .unsupported(let data):
                feedComment.status = .unsupported
                feedComment.rawData = data
            case .waiting:
                feedComment.status = .rerequesting
                if commentData.status != .rerequesting {
                    DDLogError("CoreFeedData/saveCommentData/invalid content [\(commentData.id)] with status: \(commentData.status)")
                }
            }

            // Mentions
            feedComment.mentions = commentData.orderedMentions.map {
                MentionData(index: $0.index, userID: $0.userID, name: $0.name)
            }

            // Process link preview if present
            commentData.linkPreviewData.forEach { linkPreviewData in
                DDLogDebug("CoreFeedData/saveCommentData/new/add-link-preview [\(linkPreviewData.url)]")
                let linkPreview = CommonLinkPreview(context: context)
                linkPreview.id = PacketID.generate()
                linkPreview.url = linkPreviewData.url
                linkPreview.title = linkPreviewData.title
                linkPreview.desc = linkPreviewData.description
                // Set preview image if present
                linkPreviewData.previewImages.forEach { previewMedia in
                    let media = CommonMedia(context: context)
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                }
                linkPreview.comment = feedComment
            }

            // Process comment media
            for (index, media) in commentData.orderedMedia.enumerated() {
                DDLogDebug("CoreFeedData/saveCommentData/new/add-media [\(media.url!)]")
                let feedMedia = CommonMedia(context: context)
                switch media.type {
                case .image:
                    feedMedia.type = .image
                case .video:
                    feedMedia.type = .video
                case .audio:
                    feedMedia.type = .audio
                }
                feedMedia.status = .none
                feedMedia.url = media.url
                feedMedia.size = media.size
                feedMedia.key = media.key
                feedMedia.order = Int16(index)
                feedMedia.sha256 = media.sha256
                feedMedia.comment = feedComment
                feedMedia.blobVersion = media.blobVersion
                feedMedia.chunkSize = media.chunkSize
                feedMedia.blobSize = media.blobSize
            }

            feedPost.unreadCount += 1
        }, completion: completion)
    }
}