//
//  ChatMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData
import UIKit

extension ChatMedia {

    enum Status: Int16 {
        case none = 0
        case uploading = 1
        case uploaded = 2
        case uploadError = 3
        case downloading = 4
        case downloaded = 5
        case downloadError = 6
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMedia> {
        return NSFetchRequest<ChatMedia>(entityName: "ChatMedia")
    }

    var `type`: ChatMessageMediaType {
        get {
            return ChatMessageMediaType(rawValue: Int(self.typeValue))!
        }
        set {
            self.typeValue = Int16(newValue.rawValue)
        }
    }
    
    @NSManaged var typeValue: Int16
    @NSManaged var relativeFilePath: String?
    @NSManaged var url: URL
    @NSManaged var message: ChatMessage
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
    
    @NSManaged private var width: Float
    @NSManaged private var height: Float
    var size: CGSize {
        get {
            return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
        }
        set {
            self.width = Float(newValue.width)
            self.height = Float(newValue.height)
        }
    }
    
    @NSManaged var key: String
    @NSManaged var sha256: String
    @NSManaged var order: Int16
    
}
