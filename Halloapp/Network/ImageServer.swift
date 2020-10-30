//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import SwiftUI

enum ImageProcessingError: Error {
    case invalidImage
    case resizeFailure
    case jpegConversionFailure
}

enum VideoProcessingError: Error {
    case emptyURL
    case failedToLoad
}

class ImageServer {

    private struct Constants {
        static let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
        static let maxImageSize: CGFloat = 1600
    }

    private let mediaProcessingQueue = DispatchQueue(label: "ImageServer.MediaProcessing")
    private let mediaProcessingGroup = DispatchGroup()
    private let mediaProcessingSemaphore = DispatchSemaphore(value: 3) // Prevents having more than 3 instances of AVAssetReader
    private var isCancelled = false

    func prepare(mediaItems: [PendingMedia], completion: @escaping (Bool) -> ()) {
        mediaItems.forEach{ prepare(mediaItem: $0) }
        self.mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.isCancelled {
                let allItemsPrepared = mediaItems.filter{ $0.error != nil }.isEmpty
                completion(allItemsPrepared)
            }
        }
    }
    
    func prepare(mediaItems: [PendingMedia], isReady: Binding<Bool>, numberOfFailedItems: Binding<Int>) {
        mediaItems.forEach{ prepare(mediaItem: $0) }
        self.mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.isCancelled {
                isReady.wrappedValue = true
                numberOfFailedItems.wrappedValue = mediaItems.filter{ $0.error != nil }.count
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    private func prepare(mediaItem item: PendingMedia) {
        mediaProcessingGroup.enter()
        mediaProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            // 1. Resize media as necessary.
            let mediaResizeGroup = DispatchGroup()
            switch item.type {
            case .image:
                mediaResizeGroup.enter()
                self.resizeImage(inMediaItem: item) { (result) in
                    switch result {
                    case .success(let resizedImage):
                        // Original image could be returned if resize wasn't necessary, thus this comparison.
                        if resizedImage != item.image {
                            mediaResizeGroup.enter()
                            DispatchQueue.main.async {
                                item.image = resizedImage
                                item.size = resizedImage.size
                                mediaResizeGroup.leave()
                            }
                        }

                    case .failure(let error):
                        item.error = error
                    }

                    mediaResizeGroup.leave()
                }

            case .video:
                mediaResizeGroup.enter()
                self.mediaProcessingSemaphore.wait()
                self.resizeVideo(inMediaItem: item) { (result) in
                    switch (result) {
                    case .success(let (videoUrl, videoResolution)):
                        mediaResizeGroup.enter()
                        DispatchQueue.main.async {
                            item.videoURL = videoUrl
                            item.size = videoResolution
                            mediaResizeGroup.leave()
                        }

                    case .failure(let error):
                        item.error = error
                    }

                    mediaResizeGroup.leave()
                    self.mediaProcessingSemaphore.signal()
                }
            }

            // 2. Encrypt media.
            mediaResizeGroup.notify(queue: self.mediaProcessingQueue) {
                guard item.error == nil else {
                    self.mediaProcessingGroup.leave()
                    return
                }

                /// TODO: Encrypt media without loading into memory.

                // 2.1 Load image / video into memory.
                var plaintextData: Data! = nil
                switch item.type {
                case .image:
                    if let image = item.image, let imageData = image.jpegData(compressionQuality: Constants.jpegCompressionQuality) {
                        DDLogInfo("ImageServer/image/prepare/ready  JPEG Quality: [\(Constants.jpegCompressionQuality)] Size: [\(imageData.count)]")
                        plaintextData = imageData

                        // Save resized image to the temp directory - it will be copied to the permanent directory if user proceeds posting media.
                        let tempMediaURL = URL(fileURLWithPath: NSTemporaryDirectory())
                            .appendingPathComponent(UUID().uuidString, isDirectory: false)
                            .appendingPathExtension("jpg")
                        DDLogDebug("ImageServer/media/copy to [\(tempMediaURL)]")
                        do {
                            try imageData.write(to: tempMediaURL, options: [ .atomic ])
                            item.fileURL = tempMediaURL
                        }
                        catch {
                            DDLogError("ImageServer/media/copy/error [\(error)]")
                            item.error = error
                        }
                    } else {
                        DDLogError("ImageServer/image/prepare/error  Failed to generate JPEG data. \(item)")
                        item.error = ImageProcessingError.jpegConversionFailure
                    }

                case .video:
                    if let videoData = try? Data(contentsOf: item.videoURL!) {
                        DDLogInfo("ImageServer/video/prepare/ready  New Video file size: [\(videoData.count)]")
                        plaintextData = videoData

                        // Exported video would be copied to the permanent directory if user proceeds posting media.
                        item.fileURL = item.videoURL
                    } else {
                        DDLogError("ImageServer/video/prepare/error  File not accessible")
                        item.error = VideoProcessingError.failedToLoad
                    }
                }
                                
                guard item.error == nil && plaintextData != nil else {
                    self.mediaProcessingGroup.leave()
                    return
                }

                // 2.2 Encrypt media.
                let ts = Date()
                let encryptedData: Data, key: Data, sha256Hash: Data
                DDLogDebug("ImageServer/encrypt/begin")
                do {
                    (encryptedData, key, sha256Hash) = try MediaCrypter.encrypt(data: plaintextData, mediaType: item.type)
                } catch {
                    DDLogError("ImageServer/encrypt/error item=[\(item)] [\(error)]")
                    item.error = error
                    self.mediaProcessingGroup.leave()
                    return
                }
                DDLogDebug("ImageServer/encrypt/finished  Duration: \(-ts.timeIntervalSinceNow) s")

                // 2.3 Save encrypted data into a temp file.
                let encryptedFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString, isDirectory: false)
                    .appendingPathExtension("enc")
                DDLogDebug("ImageServer/media/save-enc to [\(encryptedFileURL)]")
                do {
                    try encryptedData.write(to: encryptedFileURL, options: [ .atomic ])
                    item.key = key.base64EncodedString()
                    item.sha256 = sha256Hash.base64EncodedString()
                    item.encryptedFileUrl = encryptedFileURL
                }
                catch {
                    DDLogError("ImageServer/media/save-enc/error [\(error)]")
                    item.error = error
                    self.mediaProcessingGroup.leave()
                    return
                }

                // 2.4 Finish processing.
                self.mediaProcessingGroup.leave()
            }
        }
    }

    private func resizeImage(inMediaItem item: PendingMedia, completion: @escaping (Result<UIImage, Error>) -> ()) {
        guard let image = item.image else {
            DDLogError("ImageServer/image/prepare/error  Empty image [\(item)]")
            completion(.failure(ImageProcessingError.invalidImage))
            return
        }
        DDLogInfo("ImageServer/image/prepare  Original image size: [\(NSCoder.string(for: item.size!))]")

        let imageSize = item.size!

        // Do not resize if image is within required dimensions.
        guard imageSize.width > Constants.maxImageSize || imageSize.height > Constants.maxImageSize else {
            completion(.success(image))
            return
        }

        let aspectRatioForWidth = Constants.maxImageSize / imageSize.width
        let aspectRatioForHeight = Constants.maxImageSize / imageSize.height
        let aspectRatio = min(aspectRatioForWidth, aspectRatioForHeight)
        let targetSize = CGSize(width: (imageSize.width * aspectRatio).rounded(), height: (imageSize.height * aspectRatio).rounded())

        let ts = Date()
        guard let resized = image.fastResized(to: targetSize) else {
            DDLogError("ImageServer/image/prepare/error  Resize failed [\(item)]")
            completion(.failure(ImageProcessingError.resizeFailure))
            return
        }
        DDLogDebug("ImageServer/image/prepare  Resized in \(-ts.timeIntervalSinceNow) s")
        DDLogInfo("ImageServer/image/prepare  Downscaled image size: [\(resized.size)]")
        completion(.success(resized))
    }

    private func resizeVideo(inMediaItem item: PendingMedia, completion: @escaping (Result<(URL, CGSize), Error>) -> ()) {
        guard let videoUrl = item.videoURL else {
            DDLogError("ImageServer/video/prepare/error  Empty video URL. \(item)")
            completion(.failure(VideoProcessingError.emptyURL))
            return
        }
        guard let fileAttrs = try? FileManager.default.attributesOfItem(atPath: videoUrl.path) else {
            DDLogError("ImageServer/video/prepare/error  Failed to get file attributes. \(item)")
            completion(.failure(VideoProcessingError.failedToLoad))
            return
        }
        let fileSize = fileAttrs[FileAttributeKey.size] as! NSNumber
        DDLogInfo("ImageServer/video/prepare/ready  Original Video size: [\(fileSize)]")

        VideoUtils.resizeVideo(inputUrl: videoUrl) { (result) in
            switch result {
            case .success(let (_, videoResolution)):
                DDLogInfo("ImageServer/video/prepare/ready  New video resolution: [\(videoResolution)]")

            case .failure(let error):
                DDLogError("ImageServer/video/prepare/error [\(error)]")
            }
            completion(result)
        }
    }
}
