//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Foundation
import SwiftUI
import XMPPFramework

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
            var itemsToUpload: [PendingMedia] = []
            for (index, item) in mediaItems.enumerated() {
                item.url = mediaURLs[index].get

                let itemToUpload = PendingMedia(type: item.type)
                itemToUpload.url = mediaURLs[index].put

                if itemToUpload.type == .image {
                    guard let image = item.image else {
                        DDLogError("ImageServer/ Empty image [\(item)]")
                        continue
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
                            continue
                        }
                        DDLogDebug("ImageServer/ Resized in \(-ts.timeIntervalSinceNow) s")
                        item.image = resized
                        item.size = resized.size

                        DDLogInfo("ImageServer/ Downscaled image size: [\(item.size!)]")
                    }

                    itemToUpload.image = item.image

                    /* turn on/off encryption of media */
                    guard let imgData = itemToUpload.image!.jpegData(compressionQuality: self.jpegCompressionQuality) else {
                        DDLogError("ImageServer/ Failed to generate JPEG data. \(itemToUpload)")
                        continue
                    }
                    DDLogInfo("ImageServer/ Prepare to encrypt image. Compression: [\(self.jpegCompressionQuality)] Compressed size: [\(imgData.count)]")

                    // TODO: move encryption off the main thread
                    if let (data, key, sha256) = HAC.encrypt(data: imgData, mediaType: .image) {
                        itemToUpload.encryptedData = data
                        itemToUpload.key = key
                        itemToUpload.sha256hash = sha256
                    }

                    item.key = itemToUpload.key
                    item.sha256hash = itemToUpload.sha256hash
                } else if itemToUpload.type == .video {
                    itemToUpload.tempUrl = item.tempUrl
                    guard let videoUrl = itemToUpload.tempUrl else {
                        fatalError("Empty video URL. \(itemToUpload)")
                    }
                    guard let videoData = try? Data(contentsOf: videoUrl) else {
                        DDLogError("ImageServer/ Failed to load video. \(itemToUpload)")
                        continue
                    }
                    DDLogInfo("ImageServer/ Prepare to encrypt video. Video size: [\(videoData.count)]")

                    if let (data, key, sha256) = HAC.encrypt(data: videoData, mediaType: .video) {
                        itemToUpload.encryptedData = data
                        itemToUpload.key = key
                        itemToUpload.sha256hash = sha256
                    }

                    item.key = itemToUpload.key
                    item.sha256hash = itemToUpload.sha256hash
                }

                itemsToUpload.append(itemToUpload)
            }

            self.upload(items: itemsToUpload)
            isReady.wrappedValue = true
        }
    }

    func upload(items mediaItems: [PendingMedia]) {
        guard !mediaItems.isEmpty else { return }
        let pendingCore = PendingCore()
        for item in mediaItems {
            if item.key != nil {
                uploadData(for: item)
            } else {
                // TODO: do we need to proceed if encryption failed?
                upload(mediaItem: item)
                
                pendingCore.create(item: item)
            }
        }
    }
    
    func uploadData(for mediaItem: PendingMedia) {
        guard let uploadUrl = mediaItem.url else { fatalError("Upload URL is not set. \(mediaItem)") }
        guard let dataToUpload = mediaItem.encryptedData else { fatalError("No data to upload. \(mediaItem)") }

        Alamofire.upload(dataToUpload, to: uploadUrl, method: .put, headers: [ "Content-Type": "image/jpeg" ])
            .responseData { response in
                if (response.response != nil) {
                    DDLogInfo("ImageServer/ Successfully uploaded encrypted data. [\(uploadUrl)]")
                    PendingCore().delete(url: uploadUrl)
                }
        }
    }
    
    func upload(mediaItem: PendingMedia) {
        guard let uploadUrl = mediaItem.url else { fatalError("Upload URL is not set. \(mediaItem)") }
        guard let imageToUpload = mediaItem.image else { fatalError("No image to upload. \(mediaItem)") }
        guard let jpegData = imageToUpload.jpegData(compressionQuality: self.jpegCompressionQuality) else {
            DDLogError("ImageServer/ Failed to generate JPEG data. \(mediaItem)")
            return
        }

        Alamofire.upload(jpegData, to: uploadUrl, method: .put, headers: [ "Content-Type": "image/jpeg" ])
            .responseData { response in
                if (response.response != nil) {
                    DDLogInfo("ImageServer/ Successfully uploaded plaintext data. [\(uploadUrl)]")
                    PendingCore().delete(url: uploadUrl)
                }
        }
    }
    
    func processPending() {
        upload(items: PendingCore().getAll())
    }
}
