//
//  ChatQuotedMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import Core
import CoreData

public enum MediaDirectoryLegacy: String {
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

    var type: CommonMediaType {
        get {
            return CommonMediaType(rawValue: self.typeValue) ?? .image
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    var mediaDirectory: MediaDirectoryLegacy? {
        get {
            if let mediaDirString = mediaDir {
                return MediaDirectoryLegacy(rawValue: mediaDirString)
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
