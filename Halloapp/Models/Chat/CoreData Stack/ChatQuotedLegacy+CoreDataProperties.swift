//
//  ChatQuoted+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation



extension ChatQuotedLegacy {

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

// Protocol for quoted content in chats.
public protocol ChatQuotedProtocol {
    // TODO(murali@): why have separate media types everywhere - just share one.
    var type: ChatQuoteType { get }

    var userId: String { get }

    var quotedText: String? { get }

    var mentions: [MentionData] { get }

    var mediaList: [QuotedMedia] { get }

}
