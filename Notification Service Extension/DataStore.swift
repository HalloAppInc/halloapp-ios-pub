//
//  DataStore.swift
//  Notification Service Extension
//
//  Created by Igor Solomennikov on 9/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData

class DataStore: NotificationServiceExtensionDataStore {

    func save(protoPost: Clients_Post, notificationMetadata: NotificationMetadata) -> SharedFeedPost {
        let managedObjectContext = persistentContainer.viewContext

        let userId = notificationMetadata.fromId
        let postId = notificationMetadata.feedPostId!

        DDLogInfo("DataStore/post/\(postId)/create")

        let feedPost = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedPost", into: managedObjectContext) as! SharedFeedPost
        feedPost.id = postId
        feedPost.userId = userId
        feedPost.groupId = notificationMetadata.groupId
        feedPost.text = protoPost.text.isEmpty ? nil : protoPost.text
        feedPost.status = .received
        feedPost.timestamp = notificationMetadata.timestamp ?? Date()

        // Add mentions
        var mentions: Set<SharedFeedMention> = []
        for protoMention in protoPost.mentions {
            let mention = NSEntityDescription.insertNewObject(forEntityName: "SharedFeedMention", into: managedObjectContext) as! SharedFeedMention
            mention.index = Int(protoMention.index)
            mention.userID = protoMention.userID
            mention.name = protoMention.name
            mentions.insert(mention)
        }
        feedPost.mentions = mentions

        // Add media
        var postMedia: Set<SharedMedia> = []
        for (index, protoMedia) in protoPost.media.enumerated() {
            guard let mediaType: FeedMediaType = {
                switch protoMedia.type {
                case .image: return .image
                case .video: return .video
                default: return nil
                }}() else { continue }

            guard let url = URL(string: protoMedia.downloadURL) else { continue }

            let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
            guard width > 0 && height > 0 else { continue }

            let media = NSEntityDescription.insertNewObject(forEntityName: "SharedMedia", into: managedObjectContext) as! SharedMedia
            media.type = mediaType
            media.status = .none
            media.url = url
            media.size = CGSize(width: width, height: height)
            media.key = protoMedia.encryptionKey.base64EncodedString()
            media.sha256 = protoMedia.plaintextHash.base64EncodedString()
            media.order = Int16(index)
            postMedia.insert(media)
        }
        feedPost.media = postMedia

        save(managedObjectContext)

        return feedPost
    }

    func sharedMediaObject(forObjectId objectId: NSManagedObjectID) throws -> SharedMedia? {
        return try persistentContainer.viewContext.existingObject(with: objectId) as? SharedMedia
    }
}
