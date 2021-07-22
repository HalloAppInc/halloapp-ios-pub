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
    case audio = 2
}

public enum MediaDirectory: String {
    case media
    case chatMedia
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
    @NSManaged public var previewData: Data?
    @NSManaged public var mediaDir: String?

    var type: ChatQuoteMediaType {
        get {
            return ChatQuoteMediaType(rawValue: self.typeValue) ?? .image
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    var mediaDirectory: MediaDirectory? {
        get {
            if let mediaDirString = mediaDir {
                return MediaDirectory(rawValue: mediaDirString)
            }
            return nil
        }
        set {
            if let value = newValue {
                mediaDir = value.rawValue
            }
        }
    }

    var mediaUrl: URL {
        get {
            switch mediaDirectory {
            case .chatMedia:
                return MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath ?? "", isDirectory: false)
            case .media:
                return MainAppContext.mediaDirectoryURL.appendingPathComponent(relativeFilePath ?? "", isDirectory: false)
            case .none:
                return MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath ?? "", isDirectory: false)
            }
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
