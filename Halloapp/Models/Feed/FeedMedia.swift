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

enum FeedMediaType: String {
    case image = "image"
    case video = "video"
}

class FeedMedia: Identifiable, ObservableObject, Hashable {

    var feedItemId: String
    var order: Int = 0
    var type: FeedMediaType
    var url: URL
    var size: CGSize
    //TODO: eventually make `key` and `sha256` non-optional.
    var key: String?
    var sha256hash: String?
    var numTries: Int = 0

    var didChange = PassthroughSubject<Void, Never>()

    @Published var image: UIImage?
    @Published var tempUrl: URL?

    private var imageLoader: ImageLoader?
    private var cancellableSet: Set<AnyCancellable> = []

    init(_ media: XMPPFeedMedia, feedPostId: String, order: Int = 0) {
        self.feedItemId = feedPostId
        self.order = order

        switch media.type {
        case .image:
            self.type = .image
        case .video:
            self.type = .video
        }
        self.url = media.url
        self.size = media.size
        self.key = media.key
        self.sha256hash = media.sha256
    }

    init?(_ media: CFeedImage) {
        guard let type = FeedMediaType(rawValue: media.type ?? "") else {
            DDLogError("FeedMedia/\(media.feedItemId!) Invalid media type [\(media)]")
            return nil
        }
        guard let urlString = media.url else {
            DDLogError("FeedMedia/\(media.feedItemId!) Empty media url [\(media)]")
            return nil
        }
        guard let url = URL(string: urlString) else {
            DDLogError("FeedMedia/\(media.feedItemId!) Invalid media url [\(media)]")
            return nil
        }
        guard media.width > 0 && media.height > 0 else {
            DDLogError("FeedMedia/\(media.feedItemId!) Invalid media size [\(media)]")
            return nil
        }

        self.feedItemId = media.feedItemId!
        self.order = Int(media.order)
        self.type = type
        self.url = url
        self.size = CGSize(width: Int(media.width), height: Int(media.height))
        self.numTries = Int(media.numTries)
        if let key = media.key {
            // Use nil instead of empty strings.
            self.key = key.isEmpty ? nil : key
        } else {
            self.key = nil
        }
        if let sha256 = media.sha256hash {
            // Use nil instead of empty strings.
            self.sha256hash = sha256.isEmpty ? nil : sha256
        } else {
            self.sha256hash = nil
        }

        if let mediaData = media.blob {
            if self.type == .image {
                if let image = UIImage(data: mediaData) {
                    self.image = image
                }
            } else if self.type == .video {
                let fileName = "\(self.feedItemId)-\(self.order)"
                let fileUrl = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(fileName).appendingPathExtension("mp4")

                if !FileManager.default.fileExists(atPath: fileUrl.path) {
                    DDLogDebug("FeedMedia/\(feedItemId)-\(order) File does not exists")

                    let wasFileWritten = (try? mediaData.write(to: fileUrl, options: [.atomic])) != nil

                    if !wasFileWritten {
                        DDLogDebug("FeedMedia/\(feedItemId)-\(order) File was NOT Written")
                    } else {
                        DDLogDebug("FeedMedia/\(feedItemId)-\(order) File was written")
                    }
                } else {
                    DDLogDebug("FeedMedia/\(feedItemId)-\(order) File exists")
                }

                self.tempUrl = fileUrl
            }
        } else {
            DDLogWarn("FeedMedia/\(feedItemId)-\(order) BLOB is empty")
        }
    }

    init(_ media: PendingMedia, feedItemId: String) {
        self.feedItemId = feedItemId
        self.order = media.order
        self.type = media.type
        self.image = media.image
        if let url = media.url {
            self.url = url
        } else {
            // FIXME: This is a terrible hack required when FeedMedia objects
            // are created just to be displayed in MediaSlider in post composer.
            self.url = URL(fileReferenceLiteralResourceName: "Info.plist")
        }
        self.size = media.size!
        self.key = media.key
        self.sha256hash = media.sha256hash
        self.tempUrl = media.tempUrl
    }

    func loadImage() {
        let logPrefix = "FeedMedia/\(self.feedItemId)-\(self.order)"
        guard self.imageLoader == nil else {
            DDLogError("\(logPrefix) Already downloading media")
            return
        }
        DDLogInfo("\(logPrefix) Updating numTries to \(self.numTries + 1)")
        FeedMediaCore().updateNumTries(feedItemId: self.feedItemId, url: self.url, numTries: self.numTries + 1)

        self.imageLoader = ImageLoader(url: self.url)
        cancellableSet.insert(
            imageLoader!.didChange.sink { [weak self] _ in
                guard let self = self else { return }

                guard let downloadedData = self.imageLoader!.data else {
                    DDLogInfo("\(logPrefix) Download failed.")
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    DDLogInfo("\(logPrefix) Processing downloaded data.")

                    var mediaData: Data
                    if let key = self.key, let sha256 = self.sha256hash {
                        DDLogInfo("\(logPrefix) Media is encrypted.")

                        if let decryptedData = HAC.decrypt(data: downloadedData, key: key, sha256hash: sha256, mediaType: self.type) {
                            mediaData = decryptedData
                            DDLogInfo("\(logPrefix) Decrypoted media. size=[\(mediaData.count)]")
                        } else {
                            DDLogError("\(logPrefix) Failed to decrypt.")
                            return
                        }
                    } else {
                        DDLogWarn("\(logPrefix)  Media not encrypted.")
                        mediaData = downloadedData
                    }

                    /* compare to "" also as older media (pre 19) might not have type set yet */
                    if (self.type == .image) {
                        if let image = UIImage(data: mediaData) {
                            DispatchQueue.main.async {
                                self.image = image
                                self.didChange.send()
                            }
                            DispatchQueue.global(qos: .default).async {
                                var res: Int = 640
                                if UIScreen.main.bounds.width <= 375 {
                                    res = 480
                                }
                                /* thumbnails are currently not used right now but will be used in the future */
                                let thumbnail = image.getNewSize(res: res) ?? UIImage() // note: getNewSize will not resize if the pic is lower than res
                                FeedMediaCore().updateImage(feedItemId: self.feedItemId, url: self.url, thumb: thumbnail, orig: image)
                            }
                        } else {
                            DDLogError("\(logPrefix) Invalid image data.")
                        }
                    } else if self.type == .video {
                        DispatchQueue.main.async {
                            // check order, might be always 0 for new downloads
                            let fileName = "\(self.feedItemId)-\(self.order)"
                            let fileUrl = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(fileName).appendingPathExtension("mp4")

                            if !FileManager.default.fileExists(atPath: fileUrl.path)   {
                                DDLogDebug("\(logPrefix) Video file does not exist.")

                                let wasFileWritten = (try? mediaData.write(to: fileUrl, options: [.atomic])) != nil
                                if !wasFileWritten {
                                    DDLogError("\(logPrefix) Video file was NOT Written.")
                                } else {
                                    DDLogDebug("\(logPrefix) Video file was written.")
                                }
                            } else {
                                DDLogDebug("\(logPrefix) Video file does exists.")
                            }

                            self.tempUrl = fileUrl
                            self.didChange.send()
                        }

                        FeedMediaCore().updateBlob(feedItemId: self.feedItemId, url: self.url, data: mediaData)
                    }
                }
            }
        )
    }
    
    static func == (lhs: FeedMedia, rhs: FeedMedia) -> Bool {
        return lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}


class PendingMedia {
    var order: Int = 0
    var type: FeedMediaType
    var url: URL?
    var size: CGSize?
    var key: String?
    var sha256hash: String?
    var image: UIImage?
    var tempUrl: URL?

    init(type: FeedMediaType) {
        self.type = type
    }

    init?(_ media: CPending) {
        guard let type = FeedMediaType(rawValue: media.type ?? "") else { return nil }
        guard let urlString = media.url else { return nil }
        guard let url = URL(string: urlString) else { return nil }

        self.type = type
        self.url = url
        if media.blob != nil {
            if let image = UIImage(data: media.blob!) {
                self.image = image
            }
        }
    }
}
