//
//  FeedDownloadManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import CocoaLumberjackSwift

extension FeedDownloadManager {

    func copyMedia(from pendingMedia: PendingMedia, to feedPostMedia: CommonMedia) throws {
        guard let sourceURL = pendingMedia.fileURL else {
            DDLogError("FeedDownloadManager/copyMedia/sourceURL is nil/pendingMedia: \(pendingMedia)")
            return
        }

        // Set destination string based on the content id.
        let mediaFilename: String
        if let postID = feedPostMedia.post?.id {
            mediaFilename = "\(postID)-\(feedPostMedia.index)"
        } else if let commentID = feedPostMedia.comment?.id {
            mediaFilename = "\(commentID)-\(feedPostMedia.index)"
        } else if let linkPreviewID = feedPostMedia.linkPreview?.id {
            mediaFilename = "\(linkPreviewID)-\(feedPostMedia.index)"
        } else {
            mediaFilename = UUID().uuidString
        }

        // Copy unencrypted file.
        let destinationFileURL = self.fileURL(forMediaFilename: mediaFilename).appendingPathExtension(CommonMedia.fileExtension(forMediaType: pendingMedia.type))
        try FileManager.default.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: sourceURL, to: destinationFileURL)

        // Copy encrypted file if any - same path and file name, with added "enc" file extension.
        if let encryptedFileUrl = pendingMedia.encryptedFileUrl {
            let encryptedDestinationUrl = destinationFileURL.appendingPathExtension("enc")
            try FileManager.default.copyItem(at: encryptedFileUrl, to: encryptedDestinationUrl)
        }
        feedPostMedia.relativeFilePath = self.relativePath(from: destinationFileURL)
        DDLogInfo("FeedDownloadManager/copyMedia/from: \(sourceURL)/to: \(destinationFileURL)")
    }

}
