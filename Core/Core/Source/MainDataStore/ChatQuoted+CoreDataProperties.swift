//
//  ChatQuoted+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/31/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreData

public enum ChatQuoteType: Int16 {
    case feedpost = 0
    case message = 1
    case moment = 3
}

public extension ChatQuoted {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatQuoted> {
        return NSFetchRequest<ChatQuoted>(entityName: "ChatQuoted")
    }

    @NSManaged var typeValue: Int16
    @NSManaged var rawText: String?
    @NSManaged var userID: String?
    @NSManaged var media: Set<CommonMedia>?
    @NSManaged var message: ChatMessage?
    @NSManaged private var mentionsValue: Any?
    var mentions: [MentionData] {
        get { return mentionsValue as? [MentionData] ?? [] }
        set { mentionsValue = newValue }
    }
    // TODO: @NSManaged var groupMessage: ChatGroupMessage?

    var type: ChatQuoteType {
        get {
            return ChatQuoteType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    var orderedMedia: [CommonMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }

    var orderedMentions: [MentionData] {
        return mentions.sorted { $0.index < $1.index }
    }
}

// MARK: - Protocols

// Protocol for quoted media content in chats.
public protocol QuotedMedia {

    var quotedMediaType: CommonMediaType { get }

    var order: Int16 { get }

    var height: Float { get }

    var width: Float { get }

    var relativeFilePath: String? { get }

    var mediaDirectory: MediaDirectory { get }
}

// Protocol for quoted content in chats.
public protocol ChatQuotedProtocol {

    var type: ChatQuoteType { get }

    var userId: String { get }

    var quotedText: String? { get }

    var mentions: [MentionData] { get }

    var mediaList: [QuotedMedia] { get }
}

// MARK: - Extensions

extension CommonMedia: QuotedMedia {
    public var quotedMediaType: CommonMediaType {
        return type
    }
}

extension ChatMessage: ChatQuotedProtocol {
    public var quotedText: String? {
        return rawText
    }

    public var userId: String {
        return fromUserId
    }

    public var type: ChatQuoteType {
        return .message
    }

    public var mentions: [MentionData] {
        get { return mentionsValue as? [MentionData] ?? [] }
        set { mentionsValue = newValue }
    }

    public var mediaList: [QuotedMedia] {
        if let media = media {
            return Array(media)
        } else {
            return []
        }
    }
}

extension FeedPost: ChatQuotedProtocol {
    public var quotedText: String? {
        return rawText
    }

    public var type: ChatQuoteType {
        return isMoment ? .moment : .feedpost
    }

    public var mediaList: [QuotedMedia] {
        if let media = media {
            return Array(media)
        } else {
            return []
        }
    }
}
