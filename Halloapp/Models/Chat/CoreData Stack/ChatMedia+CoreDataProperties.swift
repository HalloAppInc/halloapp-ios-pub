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
            return ChatMessageMediaType(rawValue: Int(self.typeValue)) ?? .image
        }
        set {
            self.typeValue = Int16(newValue.rawValue)
        }
    }
    
    @NSManaged var typeValue: Int16
    
    // for inbound messages, it will end with xxx.jpg
    // for outbound messages, it will end with xxx.processed.jpg (resized with compression)
    @NSManaged public var relativeFilePath: String?

    @NSManaged var url: URL?
    @NSManaged var uploadUrl: URL?
    @NSManaged var message: ChatMessage?
    @NSManaged var groupMessage: ChatGroupMessage?

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
    
    @NSManaged public var width: Float
    @NSManaged public var height: Float
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
    @NSManaged public var order: Int16
    
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

    var urlInfo: MediaURLInfo? {
        guard let uploadUrl = uploadUrl else {
            return nil
        }
        if let downloadUrl = url {
            return .getPut(downloadUrl, uploadUrl)
        } else {
            return .patch(uploadUrl)
        }
    }
}

extension ChatMedia: QuotedMedia {
    public var quotedMediaType: ChatQuoteMediaType {
        switch type {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        }
    }
}

