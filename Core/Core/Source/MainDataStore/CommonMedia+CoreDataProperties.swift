//
//  CommonMedia+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/22/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreData
import CoreGraphics

public typealias CommonMediaID = String

public enum CommonMediaType: Int16, Codable {
    case image = 0
    case video = 1
    case audio = 2
    case document = 3
}

public enum MediaDirectory: Int16 {
    case media = 0
    case chatMedia = 1
    case shareExtensionMedia = 2
    case notificationExtensionMedia = 3
    case commonMedia = 4

    var url: URL {
        switch self {
        case .chatMedia:
            return AppContext.chatMediaDirectoryURL
        case .media:
            return AppContext.mediaDirectoryURL
        case .shareExtensionMedia:
            return ShareExtensionDataStore.dataDirectoryURL
        case .notificationExtensionMedia:
            return NotificationServiceExtensionDataStore.dataDirectoryURL
        case .commonMedia:
            return AppContext.commonMediaStoreURL
        }
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        return url.appendingPathComponent(relativePath, isDirectory: false)
    }

    func relativePath(forFileURL fileURL: URL) -> String? {
        let fullPath = fileURL.path
        let mediaDirectoryPath = url.path
        if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
            return String(fullPath.suffix(from: range.upperBound))
        }
        return nil
    }
}

public extension CommonMedia {
    enum Status: Int16 {
        case none = 0
        case readyToUpload = 1
        case uploaded = 2
        case uploadError = 3
        case downloading = 4
        case downloaded = 5
        case downloadError = 6
        case downloadFailure = 7
        case downloadedPartial = 8
        case processedForUpload = 9
        case uploading = 10
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
    @NSManaged var id: CommonMediaID
    @NSManaged var typeValue: Int16
    @NSManaged var relativeFilePath: String?
    @NSManaged var name: String?
    @NSManaged var fileSize: Int64
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

extension CommonMedia {

    public var mediaURL: URL? {
        guard let relativeFilePath = relativeFilePath else { return nil }
        return mediaDirectory.fileURL(forRelativePath: relativeFilePath)
    }

    public var mediaDirectoryURL: URL {
        return mediaDirectory.url
    }

    public var encryptedFileURL: URL? {
        guard let filePath = relativeFilePath else {
            return nil
        }
        // All media will now be written only to the common media directory.
        // This file can be accessed by the extensions as well - so they wont have access to other directories.
        let mediaDirectoryURL: URL? = {
            switch mediaDirectory {
            case .commonMedia:
                return AppContext.commonMediaStoreURL
            default:
                return nil
            }
        }()
        return mediaDirectoryURL?.appendingPathComponent(filePath.appending(".enc"), isDirectory: false)
    }

    public var urlInfo: MediaURLInfo? {
        get {
            if let uploadURL = uploadURL {
                if let downloadURL = url {
                    return .getPut(downloadURL, uploadURL)
                } else {
                    return .patch(uploadURL)
                }
            } else {
                if let downloadURL = url {
                    return .download(downloadURL)
                } else {
                    return nil
                }
            }
        }
        set {
            switch newValue {
            case .getPut(let getURL, let putURL):
                url = getURL
                uploadURL = putURL
            case .patch(let patchURL):
                url = nil
                uploadURL = patchURL
            case .download(let downloadURL):
                url = downloadURL
                uploadURL = nil
            case .none:
                url = nil
                uploadURL = nil
            }
        }
    }

    var statusPublisher: AnyPublisher<Status, Never> {
        return publisher(for: \.statusValue)
            .compactMap { Status(rawValue: $0) }
            .eraseToAnyPublisher()
    }
}

public extension CommonMedia {
    // TODO: Remove and use `uploadURL` everywhere
    var uploadUrl: URL? {
        get { return uploadURL }
        set { uploadURL = newValue }
    }
}

extension CommonMedia: FeedMediaProtocol {

}

public extension CommonMedia {

    // TODO: Remove these shims and use single status value everywhere

    var incomingStatus: IncomingStatus {
        get {
            switch status {
            case .none:
                return .none
            case .uploadError, .uploaded, .readyToUpload, .processedForUpload, .uploading:
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
            case .readyToUpload, .processedForUpload, .uploading:
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
                status = .readyToUpload
            case .error:
                status = .uploadError
            case .none:
                // Clear status only if it was related to outgoing media (ignore for incoming media)
                if [.uploaded, .readyToUpload, .uploadError].contains(status) {
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

// MARK: - Copy URLs

extension CommonMedia {

    public static func copyMedia(from pendingMedia: PendingMedia, to commonMedia: CommonMedia) throws {
        guard let sourceURL = pendingMedia.fileURL else {
            DDLogError("CommonMedia/copyMedia/sourceURL is nil/pendingMedia: \(pendingMedia)")
            return
        }
        try copyMedia(at: sourceURL, encryptedFileURL: pendingMedia.encryptedFileUrl, fileExtension: fileExtension(forMediaType: pendingMedia.type), to: commonMedia)
    }

    public static func copyMedia(at sourceURL: URL, encryptedFileURL: URL?, fileExtension: String, to commonMedia: CommonMedia) throws {
        // Set destination string based on the content id.
        let mediaFilename = commonMedia.id

        // Copy unencrypted file
        let destinationFileURL = fileURL(forMediaFilename: mediaFilename).appendingPathExtension(fileExtension)
        try FileManager.default.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: sourceURL, to: destinationFileURL)

        // Copy encrypted file if any - same path and file name, with added "enc" file extension.
        if let encryptedFileURL = encryptedFileURL {
            let encryptedDestinationURL = destinationFileURL.appendingPathExtension("enc")
            try FileManager.default.copyItem(at: encryptedFileURL, to: encryptedDestinationURL)
        }
        let mediaDirectory = MediaDirectory.commonMedia
        commonMedia.mediaDirectory = mediaDirectory
        commonMedia.relativeFilePath = mediaDirectory.relativePath(forFileURL: destinationFileURL)
        DDLogInfo("FeedDownloadManager/copyMedia/from: \(sourceURL)/to: \(destinationFileURL)")
    }

    public static func fileURL(forMediaFilename mediaFilename: String) -> URL {
        var first: String?, second: String?
        for ch in mediaFilename.unicodeScalars {
            guard CharacterSet.alphanumerics.contains(ch) else { continue }
            if first == nil {
                first = String(ch).uppercased()
                continue
            }
            if second == nil {
                second = String(ch).uppercased()
                break
            }
        }
        return AppContext.commonMediaStoreURL
                .appendingPathComponent(first!, isDirectory: true)
                .appendingPathComponent(second!, isDirectory: true)
                .appendingPathComponent(mediaFilename, isDirectory: false)
    }

    public static func fileExtension(forMediaType mediaType: CommonMediaType) -> String {
        switch mediaType {
        case .image:
            return "jpg"
        case .video:
            return "mp4"
        case .audio:
            return "aac"
        case .document:
            DDLogWarn("CommonMedia/fileExtension/warn [no extension available for document media type]")
            return ""
        }
    }
}
