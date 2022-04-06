//
//  FeedPostMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData
import Foundation
import UIKit

extension FeedPostMedia {

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostMedia> {
        return NSFetchRequest<FeedPostMedia>(entityName: "FeedPostMedia")
    }

    public var `type`: CommonMediaType {
        get {
            return CommonMediaType(rawValue: self.typeValue) ?? .image
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    @NSManaged var typeValue: Int16
    @NSManaged public var relativeFilePath: String?
    @NSManaged public var url: URL?
    @NSManaged public var uploadUrl: URL?
    @NSManaged var post: FeedPost?
    @NSManaged var comment: FeedPostComment?
    @NSManaged var linkPreview: FeedLinkPreview?
    @NSManaged private var statusValue: Int16
    var status: CommonMedia.Status {
        get {
            return CommonMedia.Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    @NSManaged public var width: Float
    @NSManaged public var height: Float
    public var size: CGSize {
        get {
            return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
        }
        set {
            self.width = Float(newValue.width)
            self.height = Float(newValue.height)
        }
    }

    @NSManaged public var key: String
    @NSManaged public var sha256: String
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

extension FeedPostMedia: MediaUploadable {

    var encryptedFilePath: String? {
        guard let filePath = relativeFilePath else {
            return nil
        }
        return filePath.appending(".enc")
    }

    var index: Int {
        get { Int(order) }
    }

    var urlInfo: MediaURLInfo? {
        if let uploadUrl = uploadUrl {
            if let downloadUrl = url {
                return .getPut(downloadUrl, uploadUrl)
            } else {
                return .patch(uploadUrl)
            }
        } else {
            if let downloadUrl = url {
                return .download(downloadUrl)
            } else {
                return nil
            }
        }
    }
}

extension FeedPostMedia: FeedMediaProtocol {
    public var id: String {
        get {
            if let feedPost = post {
                return "\(feedPost.id)-\(order)"
            } else if let feedComment = comment {
                return "\(feedComment.id)-\(order)"
            } else if let feeLinkPreview = linkPreview {
                return "\(feeLinkPreview.id)-\(order)"
            } else {
                DDLogError("FeedPostMedia/FeedPostMedia not associated with post or comment")
                return ""
            }
        }
    }
}


extension FeedPostMedia: QuotedMedia {
    public var quotedMediaType: CommonMediaType {
        return type
    }
}
