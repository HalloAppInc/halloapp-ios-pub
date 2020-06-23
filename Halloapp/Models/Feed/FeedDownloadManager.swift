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
        let destinationFileURL = self.fileURL(forMediaFilename: mediaFilename).appendingPathExtension(Self.fileExtension(forMediaType: pendingMedia.type))
        try FileManager.default.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: pendingMedia.fileURL!, to: destinationFileURL)
        feedPostMedia.relativeFilePath = self.relativePath(from: destinationFileURL)
    }

}
