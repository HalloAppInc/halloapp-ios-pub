//
//  FeedMedia.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation
import AVKit

enum FeedMediaError: Error {
    case missingImage // Image not available despite isMediaAvailable set to true
}

class FeedMedia: Identifiable, Hashable {
    private static let imageLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    var id: String?
    var feedElementId: FeedElementID?
    let order: Int
    let type: CommonMediaType
    var size: CGSize
    private var status: CommonMedia.Status {
        didSet {
            // Notify all status updates.
            mediaStatusDidChange.send(self)
        }
    }
    private var pendingMediaReadyCancelable: AnyCancellable?
    private var pendingMediaProgress: CurrentValueSubject<Float, Never>?

    var chunkedInfo: ChunkedMediaInfo? = nil

    @Published private(set) var isMediaAvailable: Bool = false
    var isDownloadRequired: Bool {
        get { status == .downloading || status == .none || status == .downloadError}
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
            } else if let task = MainAppContext.shared.feedData.downloadTask(for: self, using: MainAppContext.shared.feedData.viewContext) {
                return task.downloadProgress
            } else {
                return nil
            }
        }
    }

    /// Sends the current value of `image` right away as well as values from `imageDidBecomeAvailable`.
    var imagePublisher: AnyPublisher<UIImage?, Never> {
        let mapped = imageDidBecomeAvailable
            .map { Optional($0) }
            .eraseToAnyPublisher()

        return Just(image).merge(with: mapped)
            .eraseToAnyPublisher()
    }

    let imageDidBecomeAvailable = PassthroughSubject<UIImage, Never>()
    let videoDidBecomeAvailable = PassthroughSubject<URL, Never>()
    let mediaStatusDidChange = PassthroughSubject<FeedMedia, Never>()

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
            case .audio, .document:
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

        DDLogVerbose("FeedMedia/image/load [\(path)]")
        FeedMedia.imageLoadingQueue.async {
            let image = UIImage(contentsOfFile: path)
            DispatchQueue.main.async {
                self.image = image
            }
        }
    }

    init(_ feedPostMedia: CommonMedia) {
        order = Int(feedPostMedia.order)
        if let feedPost = feedPostMedia.post {
            feedElementId = .post(feedPost.id)
            id = "\(feedPost.id)-\(order)"
        }
        if let feedComment = feedPostMedia.comment {
            feedElementId = .comment(feedComment.id)
            id = "\(feedComment.id)-\(order)"
        }
        if let feedLinkPreview = feedPostMedia.linkPreview {
            feedElementId = .linkPreview(feedLinkPreview.id)
            id = "\(feedLinkPreview.id)-\(order)"
        }
        type = feedPostMedia.type
        size = feedPostMedia.size
        fileURL = feedPostMedia.mediaURL
        DDLogDebug("FeedMedia/init/media_id: \(String(describing: id))/url: \(String(describing: fileURL))")
        if [.audio, .video].contains(type) {
            isMediaAvailable = fileURL != nil
        }
        status = feedPostMedia.status
        chunkedInfo = ChunkedMediaInfo(commonMedia: feedPostMedia)
    }

    func reload(from feedPostMedia: CommonMedia) {
        assert(feedPostMedia.order == self.order)
        switch feedElementId {
        case .post(let postId) :
            if let feedPost = feedPostMedia.post {
                assert(feedPost.id == postId)
            }
        case .comment(let commentId):
            if let feedComment = feedPostMedia.comment {
                assert(feedComment.id == commentId)
            }
        case .linkPreview(let linkPreviewId):
            if let linkPreview = feedPostMedia.linkPreview {
                assert(linkPreview.id == linkPreviewId)
            }
        case .none:
            DDLogError("FeedMedia/reload/feedElement of type none")
        }
        assert(feedPostMedia.type == self.type)
        assert(feedPostMedia.size == self.size)
        guard feedPostMedia.status != self.status else { return }
        // Media was downloaded
        if self.fileURL == nil,
           let mediaURL = feedPostMedia.mediaURL {
            self.fileURL = mediaURL
        }

        // TODO: other kinds of updates possible?

        self.status = feedPostMedia.status
        self.chunkedInfo = ChunkedMediaInfo(commonMedia: feedPostMedia)
    }

    init(_ media: PendingMedia) {
        self.id = media.uuid
        self.status = .readyToUpload
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

            self.status = .readyToUpload
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
