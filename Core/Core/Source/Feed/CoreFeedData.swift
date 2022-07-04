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

    public func resetMomentPromptTimestamp() {
        DDLogInfo("FeedData/resetMomentPromptTimestamp")
        AppContext.shared.userDefaults.set(Double.zero, forKey: "momentPrompt")
    }

    public func feedPost(with feedPostId: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> FeedPost? {
        return feedPosts(predicate: NSPredicate(format: "id == %@", feedPostId), in: managedObjectContext).first
    }

    public func feedPosts(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true)],
                          in managedObjectContext: NSManagedObjectContext) -> [FeedPost] {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let posts = try managedObjectContext.fetch(fetchRequest)
            return posts
        } catch {
            DDLogError("CoreFeedData/fetch-posts/error  [\(error)]")
            return []
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

    public func deleteMedia(mediaItem: CommonMedia) {
        let managedObjectContext = mediaItem.managedObjectContext

        if let relativeFilePath = mediaItem.relativeFilePath,
           mediaItem.mediaDirectory == .commonMedia {
            let fileURL = AppContext.commonMediaStoreURL.appendingPathComponent(relativeFilePath, isDirectory: false)
            let encryptedURL = AppContext.commonMediaStoreURL.appendingPathComponent(relativeFilePath.appending(".enc"), isDirectory: false)
            // Remove encrypted file.
            do {
                if FileManager.default.fileExists(atPath: encryptedURL.path) {
                    try FileManager.default.removeItem(at: encryptedURL)
                    DDLogInfo("FeedData/deleteMedia-encrypted/deleting [\(encryptedURL)]")
                }
            }
            catch {
                DDLogError("FeedData/deleteMedia-encrypted/error [\(error)]")
            }
            // Remove actual file.
            do {
                try FileManager.default.removeItem(at: fileURL)
                DDLogInfo("FeedData/deleteMedia/deleting [\(fileURL)]")
            }
            catch {
                DDLogError("FeedData/deleteMedia/error [\(error)]")
            }
        }
        managedObjectContext?.delete(mediaItem)
    }

    public func notifications(with predicate: NSPredicate, in managedObjectContext: NSManagedObjectContext) -> [ FeedActivity ] {
        let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
        fetchRequest.predicate = predicate
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            return results
        }
        catch {
            DDLogError("FeedData/notifications/mark-read-all/error [\(error)]")
            return []
        }
    }

    public func notifications(for postId: FeedPostID, commentId: FeedPostCommentID? = nil, in managedObjectContext: NSManagedObjectContext) -> [FeedActivity] {
        let postIdPredicate = NSPredicate(format: "postID = %@", postId)
        if let commentID = commentId {
            let commentIdPredicate = NSPredicate(format: "commentID = %@", commentID)
            return self.notifications(with: NSCompoundPredicate(andPredicateWithSubpredicates: [ postIdPredicate, commentIdPredicate ]), in: managedObjectContext)
        } else {
            return self.notifications(with: postIdPredicate, in: managedObjectContext)
        }
    }

    public func handleGroupFeedHistoryRerequest(for contentID: String, from userID: UserID, ack: (() -> Void)?) {
        handleGroupFeedHistoryRerequest(for: contentID, from: userID) { result in
            switch result {
            case .failure(let error):
                if error.canAck {
                    ack?()
                }
            case .success:
                ack?()
            }
        }
    }

    public func handleGroupFeedHistoryRerequest(for contentID: String, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.performSeriallyOnBackgroundContext{ [mainDataStore] managedObjectContext in
            let resendInfo = mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("FeedData/didRerequestGroupFeedHistory/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")

            guard rerequestCount <= 5 else {
                DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                completion(.failure(.aborted))
                return
            }

            guard let content = mainDataStore.groupHistoryInfo(for: contentID, in: managedObjectContext) else {
                DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID)/error could not find groupHistoryInfo")
                self.service.sendContentMissing(id: contentID, type: .groupHistory, to: userID) { _ in
                    completion(.failure(.aborted))
                }
                return
            }

            resendInfo.groupHistoryInfo = content
            self.service.sendGroupFeedHistoryPayload(id: contentID, groupID: content.groupId, payload: content.payload, to: userID, rerequestCount: rerequestCount) { result in
                switch result {
                case .success():
                    DDLogInfo("FeedData/didRerequestGroupFeedHistory/\(contentID) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                case .failure(let error):
                    DDLogError("FeedData/didRerequestGroupFeedHistory/\(contentID) error \(error)")
                }
                completion(result)
            }
        }
    }

    public func handleRerequest(for contentID: String, contentType: GroupFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?) {
        handleRerequest(for: contentID, contentType: contentType, from: userID) { result in
            switch result {
            case .failure(let error):
                if error.canAck {
                    ack?()
                }
            case .success:
                ack?()
            }
        }
    }

    public func handleRerequest(for contentID: String, contentType: GroupFeedRerequestContentType,
                                from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [mainDataStore] managedObjectContext in
            let resendInfo = mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
            guard rerequestCount <= 5 else {
                DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                completion(.failure(.aborted))
                return
            }

            switch contentType {
            case .historyResend:
                guard let content = mainDataStore.groupHistoryInfo(for: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find groupHistoryInfo")
                    self.service.sendContentMissing(id: contentID, type: .unknown, to: userID) { result in
                        completion(result)
                    }
                    return
                }
                resendInfo.groupHistoryInfo = content
                self.service.resendHistoryResendPayload(id: contentID, groupID: content.groupId, payload: content.payload, to: userID, rerequestCount: rerequestCount) { result in
                    switch result {
                    case .success():
                        DDLogInfo("FeedData/handleRerequest/\(contentID) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                        // TODO: murali@: update rerequestCount only on success.
                    case .failure(let error):
                        DDLogError("FeedData/handleRerequest/\(contentID) error \(error)")
                    }
                    completion(result)
                }

            case .post:
                guard let post = self.feedPost(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find post")
                    self.service.sendContentMissing(id: contentID, type: .groupFeedPost, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                DDLogInfo("FeedData/handleRerequest/postID: \(post.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard let groupId = post.groupId else {
                    DDLogInfo("FeedData/handleRerequest/postID: \(post.id) /groupId is missing")
                    completion(.failure(.aborted))
                    return
                }
                let feed: Feed = .group(groupId)
                resendInfo.post = post

                // Handle rerequests for posts based on status.
                switch post.status {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/postID: \(post.id)/userID: \(userID)/sending retract")
                    self.service.retractPost(post.id, in: groupId, to: userID, completion: completion)
                default:
                    self.service.resendPost(post.postData, feed: feed, rerequestCount: rerequestCount, to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/postID: \(post.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/postID: \(post.id) error \(error)")
                        }
                        completion(result)
                    }
                }

            case .comment:
                guard let comment = self.feedComment(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find comment")
                    self.service.sendContentMissing(id: contentID, type: .groupFeedComment, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                resendInfo.comment = comment

                guard let groupId = comment.post.groupId else {
                    DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) /groupId is missing")
                    completion(.failure(.aborted))
                    return
                }
                // Handle rerequests for comments based on status.
                switch comment.status {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id)/userID: \(userID)/sending retract")
                    self.service.retractComment(comment.id, postID: comment.post.id, in: groupId, to: userID, completion: completion)
                default:
                    self.service.resendComment(comment.commentData, groupId: groupId, rerequestCount: rerequestCount, to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/commentID: \(comment.id) error \(error)")
                        }
                        completion(result)
                    }
                }
            case .unknown, .UNRECOGNIZED:
                completion(.failure(.aborted))
            }
        }
    }

    public func handleRerequest(for contentID: String, contentType: HomeFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?) {
        handleRerequest(for: contentID, contentType: contentType, from: userID) { result in
            switch result {
            case .failure(let error):
                if error.canAck {
                    ack?()
                }
            case .success:
                ack?()
            }
        }
    }

    public func handleRerequest(for contentID: String, contentType: HomeFeedRerequestContentType,
                                from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        mainDataStore.saveSeriallyOnBackgroundContext { [mainDataStore] managedObjectContext in
            let resendInfo = mainDataStore.fetchContentResendInfo(for: contentID, userID: userID, in: managedObjectContext)
            resendInfo.retryCount += 1
            // retryCount indicates number of times content has been rerequested until now: increment and use it when sending.
            let rerequestCount = resendInfo.retryCount
            DDLogInfo("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount)")
            guard rerequestCount <= 5 else {
                DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                completion(.failure(.aborted))
                return
            }

            switch contentType {
            case .post:
                guard let post = self.feedPost(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find post")
                    self.service.sendContentMissing(id: contentID, type: .homeFeedPost, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                DDLogInfo("FeedData/handleRerequest/postID: \(post.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard let audience = post.audience else {
                    DDLogInfo("FeedData/handleRerequest/postID: \(post.id) /audience is missing")
                    completion(.failure(.aborted))
                    return
                }
                // Dont send audience when responding to rerequests.
                let feed: Feed = .personal(FeedAudience(audienceType: audience.audienceType, userIds: Set<UserID>()))
                resendInfo.post = post

                // Handle rerequests for posts based on status.
                switch post.status {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/postID: \(post.id)/userID: \(userID)/sending retract")
                    self.service.retractPost(post.id, in: nil, to: userID, completion: completion)
                default:
                    self.service.resendPost(post.postData, feed: feed, rerequestCount: rerequestCount, to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/postID: \(post.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/postID: \(post.id) error \(error)")
                        }
                        completion(result)
                    }
                }

            case .comment:
                guard let comment = self.feedComment(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find comment")
                    self.service.sendContentMissing(id: contentID, type: .homeFeedComment, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                resendInfo.comment = comment

                let groupId = comment.post.groupId

                // Handle rerequests for comments based on status.
                switch comment.status {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id)/userID: \(userID)/sending retract")
                    self.service.retractComment(comment.id, postID: comment.post.id, in: groupId, to: userID, completion: completion)
                default:
                    self.service.resendComment(comment.commentData, groupId: groupId, rerequestCount: rerequestCount, to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/commentID: \(comment.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/commentID: \(comment.id) error \(error)")
                        }
                        completion(result)
                    }
                }
            case .unknown, .UNRECOGNIZED:
                completion(.failure(.aborted))
            }
        }
    }
}
