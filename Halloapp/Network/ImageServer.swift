//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import SwiftUI

class ImageServer {
    private let jpegCompressionQuality = CGFloat(AppContext.shared.userData.compressionQuality)
    private let maxImageSize: CGFloat = 1600

    func beginUploading(items mediaItems: [PendingMedia], isReady: Binding<Bool>) {
        guard !mediaItems.isEmpty else {
            isReady.wrappedValue = true
            return
        }
        // Request media URLs for all items
        var mediaURLs: [MediaURL] = []
        for _ in mediaItems {
            let request = XMPPMediaUploadURLRequest(completion: { urls, error in
                if urls != nil {
                    mediaURLs.append(contentsOf: urls!)
                }
                if mediaURLs.count == mediaItems.count {
                    startUploadingMedia()
                }
            })
            AppContext.shared.xmppController.enqueue(request: request)
        }

        func startUploadingMedia() {
            for (index, item) in mediaItems.enumerated() {
                item.url = mediaURLs[index].get

                var plaintextData: Data? = nil
                switch (item.type) {
                case .image:
                    guard let image = item.image else {
                        DDLogError("ImageServer/ Empty image [\(item)]")
                        break
                    }
                    DDLogInfo("ImageServer/ Original image size: [\(NSCoder.string(for: item.size!))]")

                    // TODO: move resize off the main thread
                    let imageSize = item.size!
                    if imageSize.width > maxImageSize || imageSize.height > maxImageSize {
                        let aspectRatioForWidth = maxImageSize / imageSize.width
                        let aspectRatioForHeight = maxImageSize / imageSize.height
                        let aspectRatio = min(aspectRatioForWidth, aspectRatioForHeight)
                        let targetSize = CGSize(width: (imageSize.width * aspectRatio).rounded(), height: (imageSize.height * aspectRatio).rounded())

                        let ts = Date()
                        guard let resized = image.resized(to: targetSize) else {
                            DDLogError("ImageServer/ Resize failed [\(item)]")
                            break
                        }
                        DDLogDebug("ImageServer/ Resized in \(-ts.timeIntervalSinceNow) s")
                        item.image = resized
                        item.size = resized.size

                        DDLogInfo("ImageServer/ Downscaled image size: [\(item.size!)]")
                    }

                    /* turn on/off encryption of media */
                    guard let imgData = item.image!.jpegData(compressionQuality: self.jpegCompressionQuality) else {
                        DDLogError("ImageServer/ Failed to generate JPEG data. \(item)")
                        break
                    }
                    DDLogInfo("ImageServer/ Prepare to encrypt image. Compression: [\(self.jpegCompressionQuality)] Compressed size: [\(imgData.count)]")

                    plaintextData = imgData

                case .video:
                    guard let videoUrl = item.tempUrl else {
                        fatalError("Empty video URL. \(item)")
                    }
                    guard let videoData = try? Data(contentsOf: videoUrl) else {
                        DDLogError("ImageServer/ Failed to load video. \(item)")
                        break
                    }
                    DDLogInfo("ImageServer/ Prepare to encrypt video. Video size: [\(videoData.count)]")

                    plaintextData = videoData
                }

                guard plaintextData != nil else {
                    continue
                }

                // TODO: move encryption off the main thread
                let ts = Date()
                guard let (data, key, sha256) = HAC.encrypt(data: plaintextData!, mediaType: item.type) else {
                    DDLogError("ImageServer/ Failed to encrypt media. [\(item)]")
                    continue
                }
                DDLogDebug("ImageServer/ Enctypted media in \(-ts.timeIntervalSinceNow) s")

                // Encryption data would be send over the wire and saved to db.
                item.key = key
                item.sha256hash = sha256

                // Start upload.
                self.upload(data: data, to: mediaURLs[index].put)
            }

            isReady.wrappedValue = true
        }
    }

    private func upload(data: Data, to url: URL) {
        Alamofire.upload(data, to: url, method: .put, headers: [ "Content-Type": "application/octet-stream" ])
            .responseData { response in
                if (response.response != nil) {
                    DDLogInfo("ImageServer/ Successfully uploaded encrypted data. [\(url)]")
                }
        }
    }
}
