//
//  ChatQuoted+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

public enum ChatQuoteType: Int16 {
    case feedpost = 0
    case message = 1
}


extension ChatQuoted {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatQuoted> {
        return NSFetchRequest<ChatQuoted>(entityName: "ChatQuoted")
    }

    @NSManaged var typeValue: Int16
    @NSManaged var text: String?
    @NSManaged var userId: String?
    @NSManaged var media: Set<ChatQuotedMedia>?
    @NSManaged var mentions: Set<ChatMention>?
    @NSManaged var message: ChatMessage?
    @NSManaged var groupMessage: ChatGroupMessage?
    
    var type: ChatQuoteType {
        get {
            return ChatQuoteType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    public var orderedMedia: [ChatQuotedMedia] {
        get {
            guard let media = self.media else { return [] }
            return media.sorted { $0.order < $1.order }
        }
    }

    public var orderedMentions: [ChatMention] {
        get {
            guard let mentions = self.mentions else { return [] }
            return mentions.sorted { $0.index < $1.index }
        }
    }
    
}

// MARK: Generated accessors for media
extension ChatQuoted {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: ChatQuotedMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: ChatQuotedMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

// Protocol for quoted content in chats.
public protocol ChatQuotedProtocol {
    // TODO(murali@): why have separate media types everywhere - just share one.
    var type: ChatQuoteType { get }

    var userId: String { get }

    var text: String? { get }

    var mentions: Set<FeedMention>? { get }

    var mediaList: [QuotedMedia] { get }

}
