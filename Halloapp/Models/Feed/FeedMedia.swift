//
//  FeedMedia.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import Foundation

class FeedMedia: Identifiable, Hashable {
    private static let imageLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    let id: String
    let feedPostId: FeedPostID
    let order: Int
    let type: FeedMediaType
    let size: CGSize
    private var status: FeedPostMedia.Status

    private(set) var isMediaAvailable: Bool = false

    private(set) var image: UIImage?
    private var isImageLoaded: Bool = false

    let imageDidBecomeAvailable = PassthroughSubject<UIImage, Never>()
    let videoDidBecomeAvailable = PassthroughSubject<URL, Never>()

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
                if fileURL != nil {
                    videoDidBecomeAvailable.send(fileURL!)
                }
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

        DDLogVerbose("FeedMedia/image/load [\(path)]")
        FeedMedia.imageLoadingQueue.async {
            let image = UIImage(contentsOfFile: path)
            DispatchQueue.main.async {
                self.image = image
                self.isImageLoaded = true
                self.isMediaAvailable = true
                if image != nil {
                    self.imageDidBecomeAvailable.send(image!)
                }
            }
        }
    }

    init(_ feedPostMedia: FeedPostMedia) {
        feedPostId = feedPostMedia.post.id
        order = Int(feedPostMedia.order)
        type = feedPostMedia.type
        size = feedPostMedia.size
        if let relativePath = feedPostMedia.relativeFilePath {
            fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
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
            self.fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(feedPostMedia.relativeFilePath!, isDirectory: false)
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
    var error: Error?

    init(type: FeedMediaType) {
        self.type = type
    }
}

extension XMPPFeedMedia {

    init(feedMedia: PendingMedia) {
        self.init(url: feedMedia.url!, type: feedMedia.type, size: feedMedia.size!, key: feedMedia.key!, sha256: feedMedia.sha256!)
    }
}
