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

enum FeedMediaError: Error {
    case missingImage // Image not available despite isMediaAvailable set to true
}

class FeedMedia: Identifiable, Hashable {
    private static let imageLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    let id: String
    let feedPostId: FeedPostID
    let order: Int
    let type: FeedMediaType
    var size: CGSize
    private var status: FeedPostMedia.Status
    private var pendingMediaReadyCancelable: AnyCancellable?
    private var pendingMediaProgress: CurrentValueSubject<Float, Never>?

    private(set) var isMediaAvailable: Bool = false
    var isDownloadRequired: Bool {
        get { status == .downloading || status == .none }
    }

    private(set) var image: UIImage? {
        didSet {
            guard let image = image else { return }
            isImageLoaded = true
            isMediaAvailable = true
            imageDidBecomeAvailable.send(image)
        }
    }
    private var isImageLoaded: Bool = false

    var progress: CurrentValueSubject<Float, Never>? {
        get {
            if let progress = pendingMediaProgress {
                return progress
            } else if let task = MainAppContext.shared.feedData.downloadTask(for: self) {
                return task.downloadProgress
            } else {
                return nil
            }
        }
    }
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
        self.status = .uploading
        self.feedPostId = feedPostId
        self.order = media.order
        self.type = media.type
        self.image = media.image
        self.size = media.size ?? CGSize(width: 100, height: 100)
        self.fileURL = media.fileURL
        self.isMediaAvailable = media.ready.value

        if !media.ready.value {
            updateWhenReady(media: media)
        }
    }

    private func updateWhenReady(media: PendingMedia) {
        self.status = .downloading
        
        pendingMediaReadyCancelable = media.ready.sink { [weak self] ready in
            guard let self = self else { return }
            guard ready else { return }

            if let size = media.size {
                self.size = size
            }

            self.status = .uploading
            self.image = media.image
            self.fileURL = media.fileURL
        }

        pendingMediaProgress = media.progress
    }

    static func == (lhs: FeedMedia, rhs: FeedMedia) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
