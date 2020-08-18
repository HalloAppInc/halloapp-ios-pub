//
//  ChatMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation
import UIKit

extension ChatMedia {
    
    enum IncomingStatus: Int16 {
        case none = 0
        case pending = 1
        case downloaded = 2
        case error = 3
    }
    
    enum OutgoingStatus: Int16 {
        case none = 0
        case pending = 1
        case uploaded = 2
        case error = 3
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
    @NSManaged var url: URL?
    @NSManaged var uploadUrl: URL?
    @NSManaged var message: ChatMessage
    @NSManaged private var incomingStatusValue: Int16
    @NSManaged private var outgoingStatusValue: Int16
    @NSManaged var numTries: Int16
    
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

extension ChatMedia: MediaUploadable {
    var index: Int {
        Int(order)
    }

    var encryptedFilePath: String? {
        guard let filePath = relativeFilePath else {
            return nil
        }
        return filePath.appending(".enc")
    }
}
