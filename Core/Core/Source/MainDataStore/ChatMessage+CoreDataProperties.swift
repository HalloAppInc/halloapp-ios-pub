//
//  ChatMessage+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/31/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public typealias ChatMessageID = String
public typealias ChatGroupMessageID = String
public typealias ChatLinkPreviewID = String

public extension ChatMessage {

    enum IncomingStatus: Int16 {
        case none = 0
        case haveSeen = 1
        case sentSeenReceipt = 2
        case error = 3
        case retracted = 4
        case rerequesting = 5
        case unsupported = 6
        case played = 7
        case sentPlayedReceipt = 8
    }

    enum OutgoingStatus: Int16 {
        case none = 0
        case pending = 1        // initial state, only recorded in the database
        case sentOut = 2        // got ACK from server, timestamp is from server
        case delivered = 3      // other user have gotten the message
        case seen = 4           // other user have seen the message
        case error = 5
        case retracting = 6     // marked for deletion but no server ack yet
        case retracted = 7      // deleted messages
        case played = 8         // other user have played the message, only for voice notes
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }

    @NSManaged var id: ChatMessageID
    @NSManaged var fromUserID: String
    @NSManaged var toUserID: String?
    @NSManaged var toGroupID: String?
    @NSManaged var rawText: String?
    @NSManaged var media: Set<CommonMedia>?

    @NSManaged var feedPostID: String?
    @NSManaged var feedPostMediaIndex: Int32

    @NSManaged var chatReplyMessageID: String?
    @NSManaged var chatReplyMessageSenderID: UserID?
    @NSManaged var chatReplyMessageMediaIndex: Int32
    @NSManaged var forwardCount: Int32

    @NSManaged var quoted: ChatQuoted?

    @NSManaged var incomingStatusValue: Int16
    @NSManaged var outgoingStatusValue: Int16
    @NSManaged var resendAttempts: Int16

    @NSManaged var retractID: String?

    @NSManaged var serialID: Int32
    // TODO: we should switch this timestamp to be in milliseconds.
    @NSManaged var timestamp: Date?
    @NSManaged var serverTimestamp: Date?

    @NSManaged var cellHeight: Int16

    @NSManaged var rawData: Data?

    @NSManaged var linkPreviews: Set<CommonLinkPreview>?

    @NSManaged var reactions: Set<CommonReaction>?
    
    @NSManaged var location: CommonLocation?
    
    @NSManaged var hasBeenProcessed: Bool

    var incomingStatus: IncomingStatus {
        get {
            return IncomingStatus(rawValue: self.incomingStatusValue)!
        }
        set {
            self.incomingStatusValue = newValue.rawValue
        }
    }

    var outgoingStatus: OutgoingStatus {
        get {
            return OutgoingStatus(rawValue: self.outgoingStatusValue)!
        }
        set {
            self.outgoingStatusValue = newValue.rawValue
        }
    }

    var orderedMedia: [CommonMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }

    var chatMessageRecipient: ChatMessageRecipient {
        get {
            if let toUserId = self.toUserId { return .oneToOneChat(toUserId) }
            if let toGroupId = self.toGroupId { return .groupChat(toGroupId) }
            fatalError("toUserId and toGroupId not set for chat message")
        }
        set{
            switch newValue {
            case .oneToOneChat(let userId):
                self.toUserId = userId
            case .groupChat(let groupId):
                self.toGroupId = groupId
            }
        }
    }

    var linkPreviewData: [LinkPreviewProtocol] {
        get {
            var linkPreviewData = [LinkPreviewData]()
            linkPreviews?.forEach { linkPreview in
                // Check for link preview media
                var mediaData = [FeedMediaData]()
                if let linkPreviewMedia = linkPreview.media, !linkPreviewMedia.isEmpty {
                    mediaData = linkPreviewMedia
                        .map {
                            // @TODO Unify Media Objects. Github issue: 1502
                            FeedMediaData(id: "", url: $0.url , type: $0.type , size: $0.size, key: $0.key, sha256: $0.sha256, blobVersion: .default, chunkSize: 0, blobSize: 0)
                        }
                }
                if let linkPreview = LinkPreviewData(id: linkPreview.id, url: linkPreview.url, title: linkPreview.title ?? "", description: linkPreview.desc ?? "", previewImages: mediaData) {
                    linkPreviewData.append(linkPreview)
                }
            }
            return linkPreviewData
        }
    }
    
    var sortedReactionsList: [CommonReaction] {
        get {
            guard let reactions = self.reactions else { return [] }
            return reactions.sorted { $0.timestamp > $1.timestamp }
        }
    }

    var allAssociatedMedia: [CommonMedia] {
        var allMedia: [CommonMedia] = []

        if let media = media {
            allMedia += media.sorted { $0.order < $1.order }
        }

        if let quotedMedia = quoted?.media {
            allMedia += quotedMedia.sorted { $0.order < $1.order }
        }

        linkPreviews?.forEach { linkPreview in
            if let linkPreviewMedia = linkPreview.media {
                allMedia += linkPreviewMedia
            }
        }

        return allMedia
    }
}

public extension ChatMessage {

    // TODO: Remove these and use `...ID` everywhere

    var fromUserId: String {
        get { return fromUserID }
        set { fromUserID = newValue }
    }
    var toUserId: String? {
        get { return toUserID }
        set { toUserID = newValue }
    }
    var toGroupId: String? {
        get { return toGroupID }
        set { toGroupID = newValue }
    }
    var feedPostId: String? {
        get { return feedPostID }
        set { feedPostID = newValue }
    }
}
