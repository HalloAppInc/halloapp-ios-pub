//
//  ExternalSharePost.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import CocoaLumberjackSwift
import Core
import CoreCommon
import CryptoSwift
import UIKit

class ExternalSharePost: FeedPostDisplayable {

    let id: FeedPostID
    let userId: UserID
    let name: String
    let avatarID: String
    let timestamp: Date
    let status: FeedPost.Status
    let media: [ExternalShareMedia]
    let orderedMentions: [FeedMentionProtocol]
    let externalShareLinkPreview: ExternalShareLinkPreview?
    let text: String?

    init(name: String, avatarID: String, postContainerBlob: Clients_PostContainerBlob) {
        id = postContainerBlob.postID
        userId = String(postContainerBlob.uid)
        self.name = name
        self.avatarID = avatarID
        timestamp = Date(timeIntervalSince1970: TimeInterval(postContainerBlob.timestamp))
        status = .seen

        let postContent = PostData.extractContent(postId: postContainerBlob.postID,
                                                  postContainer: postContainerBlob.postContainer,
                                                  payload: Data())

        let mediaData: [FeedMediaData]
        let mentionText: MentionText?
        let linkPreviews: [LinkPreviewData]?

        switch postContent {
        case .text(let mention, let linkPreviewData):
            mediaData = []
            mentionText = mention
            linkPreviews = linkPreviewData
        case .album(let mention, let media):
            mediaData = media
            mentionText = mention
            linkPreviews = nil
        case .voiceNote(let media):
            mediaData = [media]
            mentionText = nil
            linkPreviews = nil
        case .waiting, .unsupported, .retracted, .none:
            mediaData = []
            mentionText = nil
            linkPreviews = nil
        }

        media = mediaData
            .map { ExternalShareMedia(feedMediaData: $0) }
        externalShareLinkPreview = linkPreviews?.first
            .flatMap { ExternalShareLinkPreview(linkPreviewData: $0, postID: postContainerBlob.postID) }
        orderedMentions = (mentionText?.mentions ?? [:])
            .map { (i, user) in MentionData(index: i, userID: user.userID, name: user.pushName ?? "") }
            .sorted { $0.index < $1.index }
        text = mentionText?.collapsedText
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

    var canComment: Bool {
        return false
    }

    var posterFullName: String {
        let fullName = MainAppContext.shared.contactStore.fullNameIfAvailable(for: userId,
                                                                              ownName: Localizations.meCapitalized,
                                                                              showPushNumber: false)
        return fullName ?? "~\(name)"
    }

    func userAvatar(using avatarStore: AvatarStore) -> UserAvatar {
        return UserAvatar(userId: userId, avatarID: avatarID)
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

// MARK: - Encryption Helpers

extension ExternalSharePost {

    enum ExternalSharePostError: Error {
        case invalidData
        case invalidHmac
        case keygen
    }

    static func decrypt(encryptedBlob: Data, key: Data) throws -> Clients_PostContainerBlob {
        guard encryptedBlob.count > 32 else {
            throw ExternalSharePostError.invalidData
        }

        let encryptedPostData = [UInt8](encryptedBlob[0 ..< encryptedBlob.count - 32])
        let hmac = [UInt8](encryptedBlob[encryptedBlob.count - 32 ..< encryptedBlob.count])
        let (iv, aesKey, hmacKey) = try externalShareKeys(from: [UInt8](key))

        // Calculate and compare HMAC
        let calculatedHmac = try HMAC(key: hmacKey, variant: .sha256).authenticate(encryptedPostData)

        guard hmac == calculatedHmac else {
            throw ExternalSharePostError.invalidHmac
        }

        let postData = try AES(key: aesKey, blockMode: CBC(iv: iv), padding: .pkcs5).decrypt(encryptedPostData)

        return try Clients_PostContainerBlob(contiguousBytes: postData)
    }

    static func encypt(blob: Clients_PostContainerBlob) throws -> (encryptedBlob: Data, key: Data) {
        let data = try blob.serializedData()

        var attachmentKey = [UInt8](repeating: 0, count: 15)
        guard SecRandomCopyBytes(kSecRandomDefault, 15, &attachmentKey) == errSecSuccess else {
            throw ExternalSharePostError.keygen
        }

        let (iv, aesKey, hmacKey) = try Self.externalShareKeys(from: attachmentKey)
        let encryptedPostData = try AES(key: aesKey, blockMode: CBC(iv: iv), padding: .pkcs5).encrypt(data.bytes)
        let hmac = try HMAC(key: hmacKey, variant: .sha256).authenticate(encryptedPostData)

        return (encryptedBlob: Data(encryptedPostData + hmac), key: Data(attachmentKey))
    }

    private static func externalShareKeys(from key: [UInt8]) throws -> (iv: [UInt8], aesKey: [UInt8], hmacKey: [UInt8]) {
        let fullKey = try HKDF(password: key, info: "HalloApp Share Post".bytes, keyLength: 80, variant: .sha256).calculate()
        let iv = Array(fullKey[0..<16])
        let aesKey = Array(fullKey[16..<48])
        let hmacKey = Array(fullKey[48..<80])
        return (iv, aesKey, hmacKey)
    }
}
