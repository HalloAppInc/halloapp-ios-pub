//
//  FeedMedia.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class FeedMedia: Identifiable, ObservableObject, Hashable {
    static let imageLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    var id: String

    var feedPostId: FeedPostID
    var order: Int = 0
    var type: FeedMediaType
    var size: CGSize
    private var status: FeedPostMedia.Status

    /**
     This property exposes to SwiftUI whether media is ready to be displayed or not.

     Media is available when:
     Images: image was downloaded, saved to a file and then loaded from file.
     Videos: video was dowbloaded and saved to a file.
     */
    @Published var isMediaAvailable: Bool = false

    var image: UIImage?
    private var isImageLoaded: Bool = false

    /**
     Setting this for images will trigger loading of an image on a background queue.
     */
    var fileURL: URL? {
        didSet {
            switch type {
            case .image:
                guard self.image == nil else { return }
                // TODO: investigate if loading is only necessary for some objects.
                if (fileURL != nil) {
                    isImageLoaded = false
                    self.loadImage()
                } else {
                    isMediaAvailable = false
                }
            case .video:
                isMediaAvailable = fileURL != nil
            }
        }
    }

    var displayAspectRatio: CGFloat {
        get {
            return max(self.size.width/self.size.height, 4/5)
        }
    }

    func loadImage() {
        guard !self.isImageLoaded else {
            return
        }
        guard self.type == .image else { return }
        guard let path = self.fileURL?.path else {
            return
        }

        DDLogDebug("FeedMedia/image/load [\(path)]")
        FeedMedia.imageLoadingQueue.async {
            let image = UIImage(contentsOfFile: path)
            DispatchQueue.main.async {
                self.image = image
                self.isImageLoaded = true
                self.isMediaAvailable = true
            }
        }
    }

    init(_ feedPostMedia: FeedPostMedia) {
        feedPostId = feedPostMedia.post.id
        order = Int(feedPostMedia.order)
        type = feedPostMedia.type
        size = feedPostMedia.size
        if let relativePath = feedPostMedia.relativeFilePath {
            fileURL = AppContext.mediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }
        if type == .video {
            isMediaAvailable = fileURL != nil
        }
        id = "\(feedPostId)-\(order)"
        status = feedPostMedia.status
    }

    func reload(from feedPostMedia: FeedPostMedia) {
        assert(feedPostMedia.order == self.order)
        assert(feedPostMedia.post.id == self.feedPostId)
        assert(feedPostMedia.type == self.type)
        assert(feedPostMedia.size == self.size)
        guard feedPostMedia.status != self.status else { return }
        // Media was downloaded
        if self.fileURL == nil && feedPostMedia.relativeFilePath != nil {
            self.fileURL = AppContext.mediaDirectoryURL.appendingPathComponent(feedPostMedia.relativeFilePath!, isDirectory: false)
        }

        // TODO: other kinds of updates possible?

        self.status = feedPostMedia.status
    }

    init(_ media: PendingMedia, feedPostId: FeedPostID) {
        self.id = "\(feedPostId)-\(media.order)"
        self.status = .none
        self.feedPostId = feedPostId
        self.order = media.order
        self.type = media.type
        self.image = media.image
        self.size = media.size!
        self.fileURL = media.fileURL ?? media.videoURL
        self.isMediaAvailable = true
    }
    
    static func == (lhs: FeedMedia, rhs: FeedMedia) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}


class PendingMedia {
    var order: Int = 0
    var type: FeedMediaType
    var url: URL?
    var size: CGSize?
    var key: String?
    var sha256: String?
    var image: UIImage?
    var videoURL: URL?
    var fileURL: URL?

    init(type: FeedMediaType) {
        self.type = type
    }
}
