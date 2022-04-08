//
//  ExternalSharePost.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

class ExternalSharePost: FeedPostDisplayable {

    let id: FeedPostID
    let userId: UserID
    let timestamp: Date
    let status: FeedPost.Status
    let media: [ExternalShareMedia]
    let orderedMentions: [FeedMentionProtocol]
    let externalShareLinkPreview: ExternalShareLinkPreview?
    let text: String?

    init(postData: PostData) {
        id = postData.id
        userId = postData.userId
        timestamp = postData.timestamp
        status = {
            switch postData.content {
            case .retracted:
                return .retracted
            case .unsupported:
                return .unsupported
            case .waiting:
                return .none
            case .text, .album, .voiceNote:
                switch postData.status {
                case .none:
                    return .none
                case .sent:
                    return .sent
                case .received:
                    return .incoming
                case .sendError:
                    return .sendError
                case .rerequesting:
                    return .rerequesting
                }
            }
        }()
        media = postData.orderedMedia.map { ExternalShareMedia(feedMediaData: $0) }
        orderedMentions = postData.orderedMentions
        externalShareLinkPreview = postData.linkPreviewData.first.flatMap {
            ExternalShareLinkPreview(linkPreviewData: $0, postID: postData.id)
        }
        text = postData.text
    }

    var groupId: GroupID? {
        return nil
    }

    var unreadCount: Int32 {
        return 0
    }

    var mediaCount: Int {
        return media.count
    }

    var feedMedia: [FeedMedia] {
        return media.enumerated().map { (index, media) in FeedMedia(media, feedPostId: id, order: index)}
    }

    var hasSaveablePostMedia: Bool {
        return false
    }

    var canSaveMedia: Bool {
        return false
    }

    var hasComments: Bool {
        return false
    }

    var audienceType: AudienceType? {
        return nil
    }

    var seenReceipts: [FeedPostReceipt] {
        return []
    }

    var linkPreview: LinkPreviewDisplayable? {
        return externalShareLinkPreview
    }

    var isWaiting: Bool {
        return false
    }

    var hasAudio: Bool {
        return media.contains { $0.type == .audio }
    }

    var canDeletePost: Bool {
        return false
    }

    var canSharePost: Bool {
        return false
    }

    func downloadMedia() {
        media.forEach { $0.download() }
        externalShareLinkPreview?.media?.forEach { $0.download() }
    }
}

class ExternalShareLinkPreview: LinkPreviewDisplayable {

    let id: FeedLinkPreviewID
    let url: URL?
    let title: String?
    let media: [ExternalShareMedia]?

    init(linkPreviewData: LinkPreviewData, postID: FeedPostID) {
        let id = linkPreviewData.id ?? "\(postID)-linkpreview"
        self.id = id
        url = linkPreviewData.url
        title = linkPreviewData.title
        // By default, link preview media is populated with an id of "", which causes issues in the media downloader
        media = linkPreviewData.previewImages.map { ExternalShareMedia(feedMediaData: $0, id: id) }
    }

    var feedMedia: FeedMedia? {
        return media?.first.flatMap { FeedMedia($0, feedPostId: id, order: 0) }
    }
}

class ExternalShareMedia: FeedMediaProtocol {

    let id: String
    let url: URL?
    let type: FeedMediaType
    let size: CGSize
    let key: String
    let sha256: String
    let blobVersion: BlobVersion
    let chunkSize: Int32
    let blobSize: Int64

    var status: FeedPostMedia.Status
    var fileURL: URL?
    let ready = CurrentValueSubject<Bool, Never>(false)
    var progress = CurrentValueSubject<Float, Never>(0)
    private var downloadTaskProgressCancellable: AnyCancellable?

    init(feedMediaData: FeedMediaData, id: String? = nil) {
        self.id = id ?? feedMediaData.id
        url = feedMediaData.url
        type = feedMediaData.type
        size = feedMediaData.size
        key = feedMediaData.key
        sha256 = feedMediaData.sha256
        blobVersion = feedMediaData.blobVersion
        chunkSize = feedMediaData.chunkSize
        blobSize = feedMediaData.blobSize
        status = .none
        fileURL = nil
    }

    private static let downloadManager = FeedDownloadManager(mediaDirectoryURL: FileManager.default.temporaryDirectory)

    func download() {
        guard status != .downloading else  {
            return
        }
        let (downloading, task) = Self.downloadManager.downloadMedia(for: self) { [weak self] result in
            guard let self = self else {
                return
            }

            switch result {
            case .success(let url):
                self.status = .downloaded
                self.fileURL = url
                self.ready.send(true)
                self.ready.send(completion: .finished)
                self.progress.send(1)
                self.progress.send(completion: .finished)
            case .failure(_):
                self.status = .downloadError
            }
        }

        if downloading {
            status = .downloading
            downloadTaskProgressCancellable = task.downloadProgress.sink { [weak self] downloadProgress in
                self?.progress.send(downloadProgress)
            }
        }
    }
}
