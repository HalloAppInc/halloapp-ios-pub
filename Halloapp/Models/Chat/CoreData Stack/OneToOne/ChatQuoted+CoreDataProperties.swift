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


extension ChatQuoted {
    enum ChatQuoteType: Int16 {
        case feedpost = 0
        case message = 1
    }
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatQuoted> {
        return NSFetchRequest<ChatQuoted>(entityName: "ChatQuoted")
    }

    @NSManaged var typeValue: Int16
    @NSManaged var text: String?
    @NSManaged var userId: String?
    @NSManaged var media: Set<ChatQuotedMedia>?
    @NSManaged var message: ChatMessage
    
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
