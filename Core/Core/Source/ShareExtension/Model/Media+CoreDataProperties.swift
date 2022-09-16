//
//  Media+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 7/16/20.
//
//

import CoreData
import UIKit


/*
 SharedMedia can be used to describe media for
 both SharedFeedPost and SharedChatMessage (coming soon)
 */
extension SharedMedia {

    public enum Status: Int16 {
        case none = 0
        case uploading = 1
        case uploaded = 2
        case error = 3
        case downloaded = 4
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedMedia> {
        return NSFetchRequest<SharedMedia>(entityName: "SharedMedia")
    }
    
    @NSManaged private var typeValue: Int16
    public var `type`: CommonMediaType {
        get {
            return CommonMediaType(rawValue: self.typeValue) ?? .image
        }
        set {
            typeValue = newValue.rawValue
        }
    }

    @NSManaged private var statusValue: Int16
    public var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }
    
    @NSManaged private var width: Float
    @NSManaged private var height: Float
    public var size: CGSize {
        get {
            let width = CGFloat(width)
            let height = CGFloat(height)
            return CGSize(width: width, height: height)
        }
        set {
            width = Float(newValue.width)
            height = Float(newValue.height)
        }
    }

    @NSManaged public var key: String
    @NSManaged public var order: Int16
    @NSManaged public var relativeFilePath: String?
    @NSManaged public var sha256: String
    @NSManaged public var url: URL?
    @NSManaged public var uploadUrl: URL?
    @NSManaged public var name: String?

    @NSManaged public var post: SharedFeedPost?
    @NSManaged public var message: SharedChatMessage?
    @NSManaged public var comment: SharedFeedComment?
    @NSManaged public var linkPreview: SharedFeedLinkPreview?

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

extension SharedMedia: FeedMediaProtocol {
    public var id: String {
        if let post = post {
            return "\(post.id)-\(order)"
        } else if let message = message {
            return "\(message.id)-\(order)"
        }
        return "\(UUID().uuidString)-\(order)"
    }
}

extension SharedMedia {
    public var contentOwnerID: String? {
        if let post = post {
            return post.id
        } else if let message = message {
            return message.id
        }
        return nil
    }
}

extension SharedMedia: ChatMediaProtocol {
    public var mediaType: CommonMediaType {
        return type
    }
}
