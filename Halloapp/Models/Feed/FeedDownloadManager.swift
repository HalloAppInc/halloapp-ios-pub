//
//  FeedDownloadManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation

extension FeedDownloadManager {

    func copyMedia(from pendingMedia: PendingMedia, to feedPostMedia: FeedPostMedia) throws {
        assert(pendingMedia.fileURL != nil)
        let mediaFilename = UUID().uuidString

        // Copy unencrypted file.
        let destinationFileURL = self.fileURL(forMediaFilename: mediaFilename).appendingPathExtension(Self.fileExtension(forMediaType: pendingMedia.type))
        try FileManager.default.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: pendingMedia.fileURL!, to: destinationFileURL)

        // Copy encrypted file if any - same path and file name, with added "enc" file extension.
        if let encryptedFileUrl = pendingMedia.encryptedFileUrl {
            let encryptedDestinationUrl = destinationFileURL.appendingPathExtension("enc")
            try FileManager.default.copyItem(at: encryptedFileUrl, to: encryptedDestinationUrl)
        }
        feedPostMedia.relativeFilePath = self.relativePath(from: destinationFileURL)
    }

}
