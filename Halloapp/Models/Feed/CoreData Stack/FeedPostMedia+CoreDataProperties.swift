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
import CoreData
import Foundation
import UIKit

extension FeedPostMedia {

    enum Status: Int16 {
        case none = 0
        case uploading = 1
        case uploaded = 2
        case uploadError = 3
        case downloading = 4
        case downloaded = 5
        case downloadError = 6
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostMedia> {
        return NSFetchRequest<FeedPostMedia>(entityName: "FeedPostMedia")
    }

    public var `type`: FeedMediaType {
        get {
            return FeedMediaType(rawValue: Int(self.typeValue))!
        }
        set {
            self.typeValue = Int16(newValue.rawValue)
        }
    }
    @NSManaged var typeValue: Int16
    @NSManaged public var relativeFilePath: String?
    @NSManaged public var url: URL?
    @NSManaged public var uploadUrl: URL?
    @NSManaged var post: FeedPost?
    @NSManaged var comment: FeedPostComment?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
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
            } else {
                DDLogError("FeedPostMedia/FeedPostMedia not associated with post or comment")
                return ""
            }
        }
    }
}


extension FeedPostMedia: QuotedMedia {
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
