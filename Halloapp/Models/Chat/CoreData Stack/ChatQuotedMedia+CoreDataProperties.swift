//
//  ChatQuotedMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

public enum ChatQuoteMediaType: Int16 {
    case image = 0
    case video = 1
}

extension ChatQuotedMedia {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatQuotedMedia> {
        return NSFetchRequest<ChatQuotedMedia>(entityName: "ChatQuotedMedia")
    }

    @NSManaged public var typeValue: Int16
    @NSManaged public var relativeFilePath: String?
    @NSManaged public var order: Int16
    @NSManaged public var height: Float
    @NSManaged public var width: Float
    @NSManaged public var quoted: ChatQuoted?

    var type: ChatQuoteMediaType {
        get {
            return ChatQuoteMediaType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    
}

// Protocol for quoted media content in chats.
public protocol QuotedMedia {

    var quotedMediaType: ChatQuoteMediaType { get }

    var order: Int16 { get }

    var height: Float { get }

    var width: Float { get }

    var relativeFilePath: String? { get }

}
