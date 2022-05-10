//
//  ChatMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation
import UIKit

extension ChatMedia {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatMedia> {
        return NSFetchRequest<ChatMedia>(entityName: "ChatMedia")
    }

    var `type`: CommonMediaType {
        get {
            return CommonMediaType(rawValue: self.typeValue) ?? .image
        }
        set {
            self.typeValue = newValue.rawValue
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
    
    var incomingStatus: CommonMedia.IncomingStatus {
        get {
            return CommonMedia.IncomingStatus(rawValue: self.incomingStatusValue)!
        }
        set {
            self.incomingStatusValue = newValue.rawValue
        }
    }
    
    var outgoingStatus: CommonMedia.OutgoingStatus {
        get {
            return CommonMedia.OutgoingStatus(rawValue: self.outgoingStatusValue)!
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
    
    @NSManaged private var blobVersionValue: Int16
    public var blobVersion: BlobVersion {
        get {
            return BlobVersion(rawValue: Int(self.blobVersionValue))!
        }
        set {
            blobVersionValue = Int16(newValue.rawValue)
        }
    }
    @NSManaged public var chunkSize: Int32
    @NSManaged public var blobSize: Int64
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
    public var quotedMediaType: CommonMediaType {
        return type
    }

    public var mediaDirectory: MediaDirectory {
        return .chatMedia
    }
}

