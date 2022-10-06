//
//  CoreFeedData.swift
//  Core
//
//  Created by Murali Balusu on 5/5/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import CoreData
import SwiftProtobuf
import Intents

// TODO: (murali@): reuse this logic in FeedData

public enum PostError: Error {
    case missingGroup
    case missingFeedAudience
    case inFlight
    case mediaUploadFailed
}

public enum MomentContext {
    case normal
    case unlock(FeedPost)
}

public struct PendingMomentInfo {

    public let isSelfieLeading: Bool
    public let locationString: String?
    public let unlockUserID: UserID?

    public init(isSelfieLeading: Bool, locationString: String?, unlockUserID: UserID?) {
        self.isSelfieLeading = isSelfieLeading
        self.locationString = locationString
        self.unlockUserID = unlockUserID
    }
}

open class CoreFeedData: NSObject {
    private let service: CoreService
    private let mainDataStore: MainDataStore
    private let chatData: CoreChatData
    private let contactStore: ContactStore
    private let privacySettings: PrivacySettings
    public let commonMediaUploader: CommonMediaUploader

    private var cancellables: Set<AnyCancellable> = []
    private var contentInFlight: Set<String> = []

    public init(service: CoreService,
                mainDataStore: MainDataStore,
                chatData: CoreChatData,
                contactStore: ContactStore,
                privacySettings: PrivacySettings,
                commonMediaUploader: CommonMediaUploader) {
        self.mainDataStore = mainDataStore
        self.service = service
        self.chatData = chatData
        self.contactStore = contactStore
        self.privacySettings = privacySettings
        self.commonMediaUploader = commonMediaUploader
        super.init()

        commonMediaUploader.postMediaStatusChangedPublisher
            .sink { [weak self] postID in self?.uploadPostIfMediaReady(postID: postID) }
            .store(in: &cancellables)

        commonMediaUploader.commentMediaStatusChangedPublisher
            .sink { [weak self] commentID in self?.uploadFeedCommentIfMediaReady(commentID: commentID) }
            .store(in: &cancellables)
    }

    /// Donates an intent to Siri for improved suggestions when sharing content.
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter chatGroup: The ID for the group the user is sharing to
    /// - Remark: This is different from the implementation in `FeedData.swift` because `MainAppContext` isn't available.
    public func addIntent(groupId: GroupID?) {
        guard let groupId = groupId,
              #available(iOS 14.0, *) else {
            return
        }
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            guard let group = AppContext.shared.coreChatData.chatGroup(groupId: groupId, in: managedObjectContext) else {
                return
            }
            let name = group.name
            let recipient = INSpeakableString(spokenPhrase: name)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: groupId, type: .group).description,
                                                        serviceName: nil,
                                                        sender: nil)

            let potentialUserAvatar = AppContext.shared.avatarStore.groupAvatarData(for: groupId).image

            guard let defaultAvatar = UIImage(named: "AvatarGroup") else { return }

            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)

            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)

            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }

    // MARK: - Post Creation

    public func post(text: MentionText,
                     media: [PendingMedia],
                     linkPreviewData: LinkPreviewData?,
                     linkPreviewMedia : PendingMedia?,
                     to destination: ShareDestination,
                     momentInfo: PendingMomentInfo? = nil,
                     didCreatePost: ((Result<(FeedPostID, [CommonMediaID]), Error>) -> Void)? = nil,
                     didBeginUpload: ((Result<FeedPostID, Error>) -> Void)? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in

            let postId: FeedPostID = PacketID.generate()

            // Create and save new FeedPost object.
            DDLogDebug("FeedData/new-post/create [\(postId)]")

            let timestamp = Date()

            let feedPost = FeedPost(context: managedObjectContext)
            feedPost.id = postId
            feedPost.userId = AppContext.shared.userData.userId
            if case .group(let groupID, _) = destination {
                feedPost.groupId = groupID
                if let group = self.chatData.chatGroup(groupId: groupID, in: managedObjectContext) {
                    feedPost.expiration = group.postExpirationDate(from: timestamp)
                } else {
                    DDLogError("FeedData/createTombstones/groupID: \(groupID) not found, setting default expiration...")
                    feedPost.expiration = timestamp.addingTimeInterval(ServerProperties.enableGroupExpiry ? TimeInterval(Int64.thirtyDays) : FeedPost.defaultExpiration)
                }
            } else {
                feedPost.expiration = timestamp.addingTimeInterval(FeedPost.defaultExpiration)
            }
            feedPost.rawText = text.collapsedText
            feedPost.status = .sending
            feedPost.timestamp = timestamp
            feedPost.lastUpdated = timestamp

            if let momentInfo {
                feedPost.isMoment = true
                feedPost.unlockedMomentUserID = momentInfo.unlockUserID
                feedPost.isMomentSelfieLeading = momentInfo.isSelfieLeading && media.count > 1
                feedPost.locationString = momentInfo.locationString
            }

            // Add mentions
            feedPost.mentions = text.mentionsArray.map {
                return MentionData(
                    index: $0.index,
                    userID: $0.userID,
                    name: self.contactStore.pushNames[$0.userID] ?? $0.name)
            }
            feedPost.mentions.filter { $0.name == "" }.forEach {
                DDLogError("FeedData/new-post/mention/\($0.userID) missing push name")
            }

            let shouldStreamFeedVideo = ServerProperties.streamingSendingEnabled || ChunkedMediaTestConstants.STREAMING_FEED_GROUP_IDS.contains(feedPost.groupId ?? "")

            var mediaIDs: [CommonMediaID] = []

            // Add post media.
            for (index, mediaItem) in media.enumerated() {
                DDLogDebug("FeedData/new-post/add-media [\(mediaItem.fileURL!)]")
                let feedMedia = CommonMedia(context: managedObjectContext)
                let mediaID = "\(feedPost.id)-\(index)"
                feedMedia.id = mediaID
                mediaIDs.append(mediaID)
                feedMedia.type = mediaItem.type
                feedMedia.status = .readyToUpload
                feedMedia.url = mediaItem.url
                feedMedia.size = mediaItem.size!
                feedMedia.key = ""
                feedMedia.sha256 = ""
                feedMedia.order = Int16(index)
                feedMedia.blobVersion = (mediaItem.type == .video && shouldStreamFeedVideo) ? .chunked : .default
                feedMedia.post = feedPost
                feedMedia.mediaDirectory = .commonMedia

                if let url = mediaItem.fileURL {
                    ImageServer.shared.attach(for: url, id: mediaID, index: index)
                }

                // Copying depends on all data fields being set, so do this last.
                do {
                    try CommonMedia.copyMedia(from: mediaItem, to: feedMedia)
                }
                catch {
                    DDLogError("FeedData/new-post/copy-media/error [\(error)]")
                }
            }

            // Add feed link preview if any
            var linkPreview: CommonLinkPreview?
            if let linkPreviewData = linkPreviewData {
                linkPreview = CommonLinkPreview(context: managedObjectContext)
                linkPreview?.id = PacketID.generate()
                linkPreview?.url = linkPreviewData.url
                linkPreview?.title = linkPreviewData.title
                linkPreview?.desc = linkPreviewData.description
                // Set preview image if present
                if let linkPreviewMedia = linkPreviewMedia {
                    let previewMedia = CommonMedia(context: managedObjectContext)
                    let linkPreviewMediaID = "\(linkPreview?.id ?? UUID().uuidString)-0"
                    previewMedia.id = linkPreviewMediaID
                    mediaIDs.append(linkPreviewMediaID)
                    previewMedia.type = linkPreviewMedia.type
                    previewMedia.status = .readyToUpload
                    previewMedia.url = linkPreviewMedia.url
                    previewMedia.size = linkPreviewMedia.size!
                    previewMedia.key = ""
                    previewMedia.sha256 = ""
                    previewMedia.order = 0
                    previewMedia.linkPreview = linkPreview
                    previewMedia.mediaDirectory = .commonMedia

                    // Copying depends on all data fields being set, so do this last.
                    do {
                        try CommonMedia.copyMedia(from: linkPreviewMedia, to: previewMedia)
                    }
                    catch {
                        DDLogError("FeedData/new-post/copy-likePreviewmedia/error [\(error)]")
                    }
                }
                linkPreview?.post = feedPost
            }

            switch destination {
            case .feed(let privacyListType):
                guard let postAudience = try? self.privacySettings.feedAudience(for: privacyListType) else {
                    let error = PostError.missingFeedAudience
                    didCreatePost?(.failure(error))
                    didBeginUpload?(.failure(error))
                    return
                }

                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                let receipts = postAudience.userIds.reduce(into: [UserID : Receipt]()) { (receipts, userId) in
                    receipts[userId] = Receipt()
                }
                feedPostInfo.receipts = receipts
                feedPostInfo.audienceType = postAudience.audienceType
                feedPost.info = feedPostInfo
            case .group(let groupId, _):
                guard let chatGroup = self.chatData.chatGroup(groupId: groupId, in: managedObjectContext) else {
                    let error = PostError.missingGroup
                    didCreatePost?(.failure(error))
                    didBeginUpload?(.failure(error))
                    return
                }
                let feedPostInfo = ContentPublishInfo(context: managedObjectContext)
                var receipts = [UserID : Receipt]()
                chatGroup.members?.forEach({ member in
                    receipts[member.userID] = Receipt()
                })
                feedPostInfo.receipts = receipts
                feedPostInfo.audienceType = .group
                feedPost.info = feedPostInfo
            case .contact:
                // ChatData is responsible for this case
                break
            }

            self.mainDataStore.save(managedObjectContext)

            didCreatePost?(.success((postId, mediaIDs)))

            self.beginMediaUploadAndSend(feedPost: feedPost, didBeginUpload: didBeginUpload)

            if feedPost.groupID != nil {
                self.chatData.updateThreadWithGroupFeed(postId, isInbound: false, using: managedObjectContext)
            }
        }
    }

    public func beginMediaUploadAndSend(feedPost: FeedPost, didBeginUpload: ((Result<FeedPostID, Error>) -> Void)? = nil) {
        let mediaToUpload = feedPost.allAssociatedMedia.filter { [.none, .readyToUpload, .processedForUpload, .uploading, .uploadError].contains($0.status) }
        if mediaToUpload.isEmpty {
            send(post: feedPost, completion: didBeginUpload)
        } else {
            var uploadedMediaCount = 0
            var failedMediaCount = 0
            let totalMediaCount = mediaToUpload.count
            let postID = feedPost.id
            // postMediaStatusChangedPublisher should trigger post upload once all media has been uploaded
            mediaToUpload.forEach { media in
                // Don't repeat in-progress requests
                guard media.status != .uploading else {
                    uploadedMediaCount += 1
                    if uploadedMediaCount + failedMediaCount == totalMediaCount {
                        if failedMediaCount == 0 {
                            didBeginUpload?(.success(postID))
                        } else {
                            didBeginUpload?(.failure(PostError.mediaUploadFailed))
                        }
                    }
                    return
                }
                commonMediaUploader.upload(mediaID: media.id) { result in
                    switch result {
                    case .success:
                        uploadedMediaCount += 1
                    case .failure:
                        failedMediaCount += 1
                    }

                    if uploadedMediaCount + failedMediaCount == totalMediaCount {
                        if failedMediaCount == 0 {
                            didBeginUpload?(.success(postID))
                        } else {
                            didBeginUpload?(.failure(PostError.mediaUploadFailed))
                        }
                    }
                }
            }
        }
    }

    private func uploadPostIfMediaReady(postID: FeedPostID) {
        let endBackgroundTask = AppContext.shared.startBackgroundTask(withName: "uploadPostIfmediaReady-\(postID)")
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let post = self.feedPost(with: postID, in: context) else {
                DDLogError("CoreFeedData/uploadPostIfMediaReady/Post not found with id \(postID)")
                endBackgroundTask()
                return
            }

            let media = post.allAssociatedMedia

            let uploadedMedia = media.filter { $0.status == .uploaded }
            let failedMedia = media.filter { $0.status == .uploadError }

            // Check if all media is uploaded
            guard media.count == uploadedMedia.count + failedMedia.count else {
                endBackgroundTask()
                return
            }

            if !failedMedia.isEmpty {
                DDLogInfo("CoreFeedData/uploadPostIfMediaReady/failed \(failedMedia.count)/\(media.count) uploads for \(postID), marking send error")
                post.status = .sendError
                self.mainDataStore.save(context)
                endBackgroundTask()
            } else {
                // Upload post
                DDLogInfo("CoreFeedData/uploadPostIfMediaReady/completed \(media.count) media uploads for \(postID)")
                self.send(post: post) { _ in
                    endBackgroundTask()
                }
            }

            let numPhotos = media.filter { $0.type == .image }.count
            let numVideos = media.filter { $0.type == .video }.count
            let totalUploadSize = media.reduce(0) { totalUploadSize, media in
                guard let encryptedFileURL = media.encryptedFileURL, let fileSize = try? encryptedFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    DDLogError("FeedData/uploadPostIfMediaReady/could not retreive fileSize for reporting for \(media.id)")
                    return totalUploadSize
                }
                return totalUploadSize + fileSize
            }

            AppContext.shared.eventMonitor.observe(
                .mediaUpload(
                    postID: post.id,
                    duration: max(Date().timeIntervalSince(post.timestamp), 0),
                    numPhotos: numPhotos,
                    numVideos: numVideos,
                    totalSize: totalUploadSize,
                    status: failedMedia.isEmpty ? .ok : .fail))
        }
    }

    public func send(post: FeedPost, completion: ((Result<FeedPostID, Error>) -> Void)? = nil) {
        let feed: Feed
        if let groupId = post.groupId {
            feed = .group(groupId)
        } else {
            guard let postAudience = post.audience else {
                DDLogError("FeedData/send-post/\(post.id) No audience set")
                post.status = .sendError
                self.mainDataStore.save(post.managedObjectContext!)
                completion?(.failure(PostError.missingFeedAudience))
                return
            }
            feed = .personal(postAudience)
        }

        let postId = post.id

        guard !contentInFlight.contains(postId) else {
            DDLogInfo("FeedData/send-post/postID: \(postId) already-in-flight")
            completion?(.failure(PostError.inFlight))
            return
        }
        DDLogInfo("FeedData/send-post/postID: \(postId) begin")
        contentInFlight.insert(postId)

        service.publishPost(post.postData, feed: feed) { result in
            switch result {
            case .success(let timestamp):
                DDLogInfo("FeedData/send-post/postID: \(postId) success")
                self.contentInFlight.remove(postId)
                self.updateFeedPost(with: postId) { (feedPost) in
                    feedPost.timestamp = timestamp
                    feedPost.status = .sent
                } performAfterSave: {
                    completion?(.success(postId))
                }
                self.addIntent(groupId: post.groupId)
            case .failure(let error):
                DDLogError("FeedData/send-post/postID: \(postId) error \(error)")
                self.contentInFlight.remove(postId)
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPost(with: postId) { (feedPost) in
                        feedPost.status = .sendError
                    } performAfterSave: {
                        completion?(.failure(error))
                    }
                }
            }
        }
    }

    public func uploadProgressPublisher(for post: FeedPost) -> AnyPublisher<Float, Never> {
        let media = post.allAssociatedMedia
        let mediaCount = media.count

        guard mediaCount > 0 else {
            return Just(Float(1)).eraseToAnyPublisher()
        }

        var overallProgressPublisher: AnyPublisher<Float, Never> = Just(0).eraseToAnyPublisher()

        for mediaItem in media {
            let mediaID = mediaItem.id
            let mediaItemProgressPublisher = mediaItem.statusPublisher
                .flatMap { [weak commonMediaUploader] status -> AnyPublisher<Float, Never> in
                    switch status {
                    case .uploaded:
                        return Just(Float(1)).eraseToAnyPublisher()
                    case .none, .readyToUpload, .uploadError:
                        let imageServerProgress: AnyPublisher<Float, Never> = ImageServer.shared.progress
                            .prepend(mediaID)
                            .filter { $0 == mediaID }
                            .map { _ -> Float in
                                let (processingCount, processingProgress) = ImageServer.shared.progress(for: mediaID)
                                return 0.5 * processingProgress * Float(processingCount) / Float(mediaCount) // Assume half of progress is for uploading
                            }
                            .eraseToAnyPublisher()
                        return imageServerProgress
                    case .processedForUpload, .uploading:
                        if let commonMediaUploader = commonMediaUploader {
                            return commonMediaUploader.progress(for: mediaID)
                                .prepend(0)
                                .map { $0 * 0.5 + 0.5 } // Assume half of progress is for processing, which is already complete
                                .eraseToAnyPublisher()
                        } else {
                            return Just(Float(0)).eraseToAnyPublisher()
                        }
                    case .downloaded, .downloadedPartial, .downloadFailure, .downloadError, .downloading:
                        // Should never get here...
                        return Just(Float(1)).eraseToAnyPublisher()
                    }
                }
            overallProgressPublisher = overallProgressPublisher
                .combineLatest(mediaItemProgressPublisher) { $0 + ($1 / Float(mediaCount)) }
                .eraseToAnyPublisher()
        }

        return overallProgressPublisher
    }

    // MARK: - Comment Creation

    private func uploadFeedCommentIfMediaReady(commentID: FeedPostCommentID) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let comment = self.feedComment(with: commentID, in: context) else {
                DDLogError("FeedData/uploadFeedCommentIfMediaReady/Comment not found with id \(commentID)")
                return
            }

            let media = comment.allAssociatedMedia

            let uploadedMedia = media.filter { $0.status == .uploaded }
            let failedMedia = media.filter { $0.status == .uploadError }

            // Check if all media is uploaded
            guard media.count == uploadedMedia.count + failedMedia.count else {
                return
            }

            if failedMedia.isEmpty {
                // Upload post
                self.send(comment: comment)
            } else {
                // Mark message as failed
                comment.status = .sendError
                self.mainDataStore.save(context)
            }
        }
    }

    public func send(comment: FeedPostComment) {
        DDLogInfo("FeedData/send-comment/commentID: \(comment.id)")
        let commentId = comment.id
        let groupId = comment.post.groupId
        let postId = comment.post.id

        guard !contentInFlight.contains(commentId) else {
            DDLogInfo("FeedData/send-comment/commentID: \(comment.id) already-in-flight")
            return
        }
        DDLogInfo("FeedData/send-comment/commentID: \(comment.id) begin")
        contentInFlight.insert(commentId)

        service.publishComment(comment.commentData, groupId: groupId) { result in
            switch result {
            case .success(let timestamp):
                DDLogInfo("FeedData/send-comment/commentID: \(commentId) success")
                self.contentInFlight.remove(commentId)
                self.updateFeedPostComment(with: commentId) { (feedComment) in
                    feedComment.timestamp = timestamp
                    feedComment.status = .sent

                    //MainAppContext.shared.endBackgroundTask(feedComment.id)
                }
                if groupId != nil {
                    var interestedPosts = AppContext.shared.userDefaults.value(forKey: AppContext.commentedGroupPostsKey) as? [FeedPostID] ?? []
                    interestedPosts.append(postId)
                    AppContext.shared.userDefaults.set(Array(Set(interestedPosts)), forKey: AppContext.commentedGroupPostsKey)
                    self.addIntent(groupId: groupId)
                }

            case .failure(let error):
                DDLogError("FeedData/send-comment/commentID: \(commentId) error \(error)")
                self.contentInFlight.remove(commentId)
                // TODO: Track this state more precisely. Even if this attempt was a definite failure, a previous attempt may have succeeded.
                if error.isKnownFailure {
                    self.updateFeedPostComment(with: commentId) { (feedComment) in
                        feedComment.status = .sendError
                        //MainAppContext.shared.endBackgroundTask(feedComment.id)
                    }
                }
            }
        }
    }

    // MARK: - FeedPost lookup and updates

    public func feedPosts(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> [FeedPost] {
        let fetchRequest = FeedPost.fetchRequest()

        var predicates: [NSPredicate] = []
        if let predicate = predicate {
            predicates.append(predicate)
        }
        if !archived {
            predicates.append(NSPredicate(format: "expiration >= now() || expiration == nil"))
        }
        if !predicates.isEmpty {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            return try managedObjectContext.fetch(fetchRequest)
        }
        catch {
            DDLogError("FeedData/fetch-posts/error  [\(error)]")
            return []
        }
    }

    public func feedPost(with id: FeedPostID, in managedObjectContext: NSManagedObjectContext, archived: Bool = false) -> FeedPost? {
        return self.feedPosts(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext, archived: archived).first
    }

    public func updateFeedPost(with id: FeedPostID, block: @escaping (FeedPost) -> (), performAfterSave: (() -> ())? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let feedPost = self.feedPost(with: id, in: managedObjectContext, archived: true) else {
                DDLogError("FeedData/update-post/missing-post [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-post [\(id)] - currentStatus: [\(feedPost.status)]")
            block(feedPost)
            DDLogVerbose("FeedData/update-post-afterBlock [\(id)] - currentStatus: [\(feedPost.status)]")
            if managedObjectContext.hasChanges {
                self.mainDataStore.save(managedObjectContext)
            }
        }
    }

    // MARK: - FeedPostComment Lookup and updates

    private func updateFeedPostComment(with id: FeedPostCommentID, block: @escaping (FeedPostComment) -> (), performAfterSave: (() -> ())? = nil) {
        mainDataStore.performSeriallyOnBackgroundContext { (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let comment = self.feedComment(with: id, in: managedObjectContext) else {
                DDLogError("FeedData/update-comment/missing-comment [\(id)]")
                return
            }
            DDLogVerbose("FeedData/update-comment [\(id)]")
            block(comment)
            if managedObjectContext.hasChanges {
                self.mainDataStore.save(managedObjectContext)
            }
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

    public func commonReaction(with id: String, in managedObjectContext: NSManagedObjectContext) -> CommonReaction? {
        return self.commonReactions(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    private func commonReactions(predicate: NSPredicate? = nil,
                                 sortDescriptors: [NSSortDescriptor]? = nil,
                                 limit: Int? = nil,
                                 in managedObjectContext: NSManagedObjectContext) -> [CommonReaction] {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let reactions = try managedObjectContext.fetch(fetchRequest)
            return reactions
        }
        catch {
            DDLogError("CoreFeedData/fetch-reactions/error  [\(error)]")
            fatalError("Failed to fetch reactions")
        }
    }

    public func savePostData(postData: PostData, in groupID: GroupID?, hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext({ context in

            if let existingPost = self.feedPost(with: postData.id, in: context) {
                DDLogInfo("CoreFeedData/savePostData/existing [\(existingPost.id)]/status: \(existingPost.status)")
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
            feedPost.expiration = postData.expiration
            feedPost.lastUpdated = Date()
            feedPost.hasBeenProcessed = hasBeenProcessed

            if case let .moment(content) = postData.content {
                feedPost.isMoment = true
                feedPost.unlockedMomentUserID = content.unlockUserID
                feedPost.isMomentSelfieLeading = content.selfieLeading
                feedPost.locationString = content.locationString
            }

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
                linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                    let media = CommonMedia(context: context)
                    media.id = "\(linkPreview.id)-\(index)"
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                    media.order = Int16(index)
                }
                linkPreview.post = feedPost
            }

            // Process post media
            for (index, media) in postData.orderedMedia.enumerated() {
                DDLogDebug("CoreFeedData/savePostData/new/add-media [\(media.url!)]")
                let feedMedia = CommonMedia(context: context)
                feedMedia.id = "\(feedPost.id)-\(index)"
                feedMedia.type = media.type
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

            // Find comment's post.
            let feedPost: FeedPost
            if let post = self.feedPost(with: commentData.feedPostId, in: context) {
                DDLogInfo("CoreFeedData/saveCommentData/existing-post [\(commentData.feedPostId)]")
                feedPost = post
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

            let feedComment: FeedPostComment
            if let existingComment = self.feedComment(with: commentData.id, in: context) {
                feedComment = existingComment
            } else {
                feedComment = FeedPostComment(context: context)
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
            case .album, .text, .voiceNote, .commentReaction:
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
                linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                    let media = CommonMedia(context: context)
                    media.id = "\(linkPreview.id)-\(index)"
                    media.type = previewMedia.type
                    media.status = .none
                    media.url = previewMedia.url
                    media.size = previewMedia.size
                    media.key = previewMedia.key
                    media.sha256 = previewMedia.sha256
                    media.linkPreview = linkPreview
                    media.order = Int16(index)
                }
                linkPreview.comment = feedComment
            }

            // Process comment media
            for (index, media) in commentData.orderedMedia.enumerated() {
                DDLogDebug("CoreFeedData/saveCommentData/new/add-media [\(media.url!)]")
                let feedMedia = CommonMedia(context: context)
                feedMedia.id = "\(feedComment.id)-\(index)"
                feedMedia.type = media.type
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

    public func saveReactionData(reaction xmppReaction: CommentData, in groupID: GroupID?, currentUserId: UserID,hasBeenProcessed: Bool, completion: @escaping ((Result<Void, Error>) -> Void)) {
        mainDataStore.saveSeriallyOnBackgroundContext({ managedObjectContext in
            let existingCommonReaction = self.commonReaction(with: xmppReaction.id, in: managedObjectContext)

            if let existingCommonReaction = existingCommonReaction {
                switch existingCommonReaction.incomingStatus {
                case .unsupported, .none, .rerequesting:
                    DDLogInfo("CoreFeedData/process/already-exists/updating [\(existingCommonReaction.incomingStatus)] [\(xmppReaction.id)]")
                    break
                case .error, .incoming, .retracted:
                    DDLogError("CoreFeedData/process/already-exists/error [\(existingCommonReaction.incomingStatus)] [\(xmppReaction.id)]")
                    return
                }
            }

            // Find reaction's post.
            let feedPost: FeedPost
            if let post = self.feedPost(with: xmppReaction.feedPostId, in: managedObjectContext) {
                DDLogInfo("CoreFeedData/process-reactions/existing-post [\(xmppReaction.feedPostId)]")
                feedPost = post
            } else {
                DDLogError("CoreFeedData/process-reactions/missing-post [\(xmppReaction.feedPostId)]/skip comment, ignored reaction: \(xmppReaction.id)")
                AppContext.shared.errorLogger?.logError(NSError(domain: "MissingPostForReaction", code: 1011))
                return
            }

            // Additional check: post's groupId must match groupId of the comment.
            guard feedPost.groupId == groupID else {
                DDLogError("CoreFeedData/process-reactions/incorrect-group-id post:[\(feedPost.groupId ?? "")] comment:[\(groupID ?? "")], ignored reaction: \(xmppReaction.id)")
                return
            }

            // Check if post has been retracted.
            guard !feedPost.isPostRetracted else {
                DDLogError("CoreFeedData/process-reactions/retracted-post [\(xmppReaction.feedPostId)], ignored reaction: \(xmppReaction.id)")
                return
            }

            // Check if parent comment exists
            guard let parentId = xmppReaction.parentId, let parentComment = self.feedComment(with: parentId, in: managedObjectContext) else {
                DDLogError("CoreFeedData/process-reactions/no-parent-comment for reaction [\(xmppReaction.id)], ignored reaction: \(xmppReaction.id)")
                // TODO: handle reactions that arrive before corresponding comment
                return
            }

            DDLogDebug("CoreFeedData/process-reactions [\(xmppReaction.id)]")
            let commonReaction: CommonReaction = {
                guard let existingCommonReaction = existingCommonReaction else {
                    // If a tombstone exists for this reaction, delete it
                    let existingTombstone = self.feedComment(with: xmppReaction.id, in: managedObjectContext)
                    if let existingTombstone = existingTombstone, existingTombstone.status == .rerequesting {
                        DDLogInfo("CoreFeedData/process-reactions/deleteTombstone [\(existingTombstone.id)]")
                        managedObjectContext.delete(existingTombstone)
                    }
                    DDLogDebug("CoreFeedData/process-reactions/new [\(xmppReaction.id)]")
                    return CommonReaction(context: managedObjectContext)
                }
                DDLogDebug("CoreFeedData/process-reactions/updating rerequested reaction [\(xmppReaction.id)]")
                return existingCommonReaction
            }()

            commonReaction.id = xmppReaction.id
            commonReaction.fromUserID = xmppReaction.userId
            switch xmppReaction.content {
            case .commentReaction(let emoji):
                commonReaction.emoji = emoji
            case .album, .text, .voiceNote, .unsupported, .retracted, .waiting:
                DDLogError("CoreFeedData/process-reaction content not reaction type")
            }
            commonReaction.comment = parentComment
            commonReaction.timestamp = xmppReaction.timestamp
            feedPost.lastUpdated = feedPost.lastUpdated.flatMap { max($0, commonReaction.timestamp) } ?? commonReaction.timestamp

            // Set status for each comment appropriately.
            switch xmppReaction.content {
            case .commentReaction:
                if commonReaction.fromUserID == currentUserId {
                    commonReaction.outgoingStatus = .sentOut
                } else {
                    // Set status to be rerequesting if necessary.
                    if xmppReaction.status == .rerequesting {
                        commonReaction.incomingStatus = .rerequesting
                    } else {
                        commonReaction.incomingStatus = .incoming
                    }
                }
            case .retracted:
                DDLogError("CoreFeedData/process-reactions/incoming-retracted-comment [\(xmppReaction.id)]")
                commonReaction.incomingStatus = .retracted
            case .unsupported(let data):
                commonReaction.incomingStatus = .unsupported
                feedPost.rawData = data
            case .waiting:
                commonReaction.incomingStatus = .rerequesting
                if xmppReaction.status != .rerequesting {
                    DDLogError("CoreFeedData/process-reactions/invalid content [\(xmppReaction.id)] with status: \(xmppReaction.status)")
                }
            case .text, .voiceNote, .album:
                DDLogError("CoreFeedData/process-reactions/processing comment as reaction [\(xmppReaction.id)] with status: \(xmppReaction.status)")
            }
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
        mainDataStore.saveSeriallyOnBackgroundContext{ [mainDataStore] managedObjectContext in
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

            case .commentReaction:
                guard let commentReaction = self.commonReaction(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find comment")
                    self.service.sendContentMissing(id: contentID, type: .groupCommentReaction, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                // Reactions have their own rerequest count.
                // TODO: avoid creating resendInfo.
                managedObjectContext.delete(resendInfo)
                commentReaction.resendAttempts += 1
                let rerequestCount = commentReaction.resendAttempts
                DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard rerequestCount <= 5 else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                    completion(.failure(.aborted))
                    return
                }

                guard let parentComment = commentReaction.comment else {
                    DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) /parentComment is missing")
                    completion(.failure(.aborted))
                    return
                }

                guard let groupId = parentComment.post.groupID else {
                    DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) /groupId is missing")
                    completion(.failure(.aborted))
                    return
                }

                // Handle rerequests for comment reactions based on status.
                switch commentReaction.outgoingStatus {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id)/userID: \(userID)/sending retract")
                    self.service.retractComment(commentReaction.id, postID: parentComment.post.id, in: groupId, to: userID, completion: completion)
                default:
                    let commentData = CommentData(id: commentReaction.id,
                                                  userId: commentReaction.fromUserID,
                                                  timestamp: commentReaction.timestamp,
                                                  feedPostId: parentComment.post.id,
                                                  parentId: parentComment.id,
                                                  content: .commentReaction(commentReaction.emoji),
                                                  status: .sent)
                    self.service.resendComment(commentData, groupId: groupId, rerequestCount: Int32(rerequestCount), to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/reactionID: \(commentReaction.id) error \(error)")
                        }
                        completion(result)
                    }
                }

            case .postReaction, .message, .unknown, .UNRECOGNIZED:
                //TODO: handle postReaction and commentReaction cases
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

            case .commentReaction:
                guard let commentReaction = self.commonReaction(with: contentID, in: managedObjectContext) else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/error could not find comment")
                    self.service.sendContentMissing(id: contentID, type: .homeCommentReaction, to: userID) { result in
                        completion(result)
                    }
                    return
                }

                // Reactions have their own rerequest count.
                // TODO: avoid creating resendInfo.
                managedObjectContext.delete(resendInfo)
                commentReaction.resendAttempts += 1
                let rerequestCount = commentReaction.resendAttempts
                DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) begin/userID: \(userID)/rerequestCount: \(rerequestCount)")
                guard rerequestCount <= 5 else {
                    DDLogError("FeedData/handleRerequest/\(contentID)/userID: \(userID)/rerequestCount: \(rerequestCount) - aborting")
                    completion(.failure(.aborted))
                    return
                }

                guard let parentComment = commentReaction.comment else {
                    DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id)/parentComment is missing")
                    completion(.failure(.aborted))
                    return
                }

                // Handle rerequests for comment reactions based on status.
                switch commentReaction.outgoingStatus {
                case .retracting, .retracted:
                    DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id)/userID: \(userID)/sending retract")
                    self.service.retractComment(commentReaction.id, postID: parentComment.post.id, in: nil, to: userID, completion: completion)
                default:
                    let commentData = CommentData(id: commentReaction.id,
                                                  userId: commentReaction.fromUserID,
                                                  timestamp: commentReaction.timestamp,
                                                  feedPostId: parentComment.post.id,
                                                  parentId: parentComment.id,
                                                  content: .commentReaction(commentReaction.emoji),
                                                  status: .sent)
                    self.service.resendComment(commentData, groupId: nil, rerequestCount: Int32(rerequestCount), to: userID) { result in
                        switch result {
                        case .success():
                            DDLogInfo("FeedData/handleRerequest/reactionID: \(commentReaction.id) success/userID: \(userID)/rerequestCount: \(rerequestCount)")
                            // TODO: murali@: update rerequestCount only on success.
                        case .failure(let error):
                            DDLogError("FeedData/handleRerequest/reactionID: \(commentReaction.id) error \(error)")
                        }
                        completion(result)
                    }
                }

            case .postReaction, .unknown, .UNRECOGNIZED:
                //TODO: handle postReaction cases
                completion(.failure(.aborted))
            }
        }
    }
}
