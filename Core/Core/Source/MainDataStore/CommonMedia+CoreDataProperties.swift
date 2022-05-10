//
//  CommonMedia+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/22/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreData
import CoreGraphics

public enum CommonMediaType: Int16, Codable {
    case image = 0
    case video = 1
    case audio = 2
}

public enum MediaDirectory: Int16 {
    case media = 0
    case chatMedia = 1
    case shareExtensionMedia = 2
    case notificationExtensionMedia = 3
}

public extension CommonMedia {
    enum Status: Int16 {
        case none = 0
        case uploading = 1
        case uploaded = 2
        case uploadError = 3
        case downloading = 4
        case downloaded = 5
        case downloadError = 6
        case downloadFailure = 7
        case downloadedPartial = 8
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<CommonMedia> {
        return NSFetchRequest<CommonMedia>(entityName: "CommonMedia")
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
    @NSManaged var relativeFilePath: String?
    @NSManaged var url: URL?
    @NSManaged var uploadURL: URL?
    @NSManaged var post: FeedPost?
    @NSManaged var comment: FeedPostComment?
    @NSManaged var message: ChatMessage?
    @NSManaged var chatQuoted: ChatQuoted?
    @NSManaged var linkPreview: CommonLinkPreview?
    @NSManaged var previewData: Data?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    @NSManaged private var mediaDirectoryValue: Int16
    var mediaDirectory: MediaDirectory {
        get {
            return MediaDirectory(rawValue: mediaDirectoryValue) ?? .media
        }
        set {
            mediaDirectoryValue = newValue.rawValue
        }
    }
    @NSManaged var width: Float
    @NSManaged var height: Float

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
    @NSManaged var numTries: Int16

    @NSManaged private var blobVersionValue: Int16
    var blobVersion: BlobVersion {
        get {
            return BlobVersion(rawValue: Int(self.blobVersionValue))!
        }
        set {
            blobVersionValue = Int16(newValue.rawValue)
        }
    }
    @NSManaged var chunkSize: Int32
    @NSManaged var blobSize: Int64
    @NSManaged var chunkSet: Data?
}

extension CommonMedia: FeedMediaProtocol {
    public var id: String {
        get {
            if let feedPost = post {
                return "\(feedPost.id)-\(order)"
            } else if let feedComment = comment {
                return "\(feedComment.id)-\(order)"
            } else if let feeLinkPreview = linkPreview {
                return "\(feeLinkPreview.id)-\(order)"
            } else if let message = message {
                return "\(message.id)-\(order)"
            } else if let quoted = chatQuoted {
                return "\(quoted.message?.id ?? UUID().uuidString)-quoted-\(order)"
            } else {
                DDLogError("CommonMedia/id not associated with known entity")
                return ""
            }
        }
    }
}

public extension CommonMedia {
    // TODO: Remove and use `uploadURL` everywhere
    var uploadUrl: URL? {
        get { return uploadURL }
        set { uploadURL = newValue }
    }
}

public extension CommonMedia {

    // TODO: Remove these shims and use single status value everywhere

    var incomingStatus: IncomingStatus {
        get {
            switch status {
            case .none:
                return .none
            case .uploadError, .uploaded, .uploading:
                return .none
            case .downloaded, .downloadedPartial:
                return .downloaded
            case .downloading:
                return .pending
            case .downloadError, .downloadFailure:
                return .error
            }
        }
        set {
            switch newValue {
            case .downloaded:
                status = .downloaded
            case .pending:
                status = .downloading
            case .error:
                // Update state for error unless it was already in permanent failure state
                if status != .downloadFailure {
                    status = .downloadError
                }
            case .none:
                // Clear status only if it was related to incoming media (ignore for outgoing media)
                if [.downloaded, .downloading, .downloadError, .downloadFailure].contains(status) {
                    status = .none
                }
            }
        }
    }

    var outgoingStatus: OutgoingStatus {
        get {
            switch status {
            case .none:
                return .none
            case .downloadError, .downloadFailure, .downloaded, .downloading, .downloadedPartial:
                return .none
            case .uploaded:
                return .uploaded
            case .uploading:
                return .pending
            case .uploadError:
                return .error
            }
        }
        set {
            switch newValue {
            case .uploaded:
                status = .uploaded
            case .pending:
                status = .uploading
            case .error:
                status = .uploadError
            case .none:
                // Clear status only if it was related to outgoing media (ignore for incoming media)
                if [.uploaded, .uploading, .uploadError].contains(status) {
                    status = .none
                }
            }
        }
    }

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

    var contentOwnerID: String? {
        if let post = post {
            return post.id
        } else if let comment = comment {
            return comment.id
        } else if let message = message {
            return message.id
        } else if let linkPreview = linkPreview {
            return linkPreview.contentOwnerID
        }
        return nil
    }
}
