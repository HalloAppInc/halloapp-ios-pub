//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Core
import SwiftUI

enum ImageProcessingError: Error {
    case invalidImage
    case resizeFailure
    case cropFailure
    case jpegConversionFailure
}

enum VideoProcessingError: Error {
    case emptyURL
    case failedToLoad
    case failedToCopyLocally
}

fileprivate struct ProcessedImageData {
    var image: UIImage
    var uncroppedImage: UIImage?
    var cropRect: CGRect?
}

class ImageServer {
    private struct Constants {
        static let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
        static let maxImageSize: CGFloat = 1600
    }

    private static let mediaProcessingSemaphore = DispatchSemaphore(value: 3) // Prevents having more than 3 instances of AVAssetReader

    private let mediaProcessingQueue = DispatchQueue(label: "ImageServer.MediaProcessing")
    private let mediaProcessingGroup = DispatchGroup()
    private let imageProcessingGroup = DispatchGroup()
    private var isCancelled = false
    private var maxAllowedAspectRatio: CGFloat? = nil
    private var maxVideoLength: TimeInterval?

    init(maxAllowedAspectRatio: CGFloat? = nil, maxVideoLength: TimeInterval? = nil) {
        self.maxAllowedAspectRatio = maxAllowedAspectRatio
        self.maxVideoLength = maxVideoLength
    }

    func prepare(mediaItems: [PendingMedia], completion: @escaping (Bool) -> ()) {
        mediaItems.forEach{ prepare(mediaItem: $0) }
        mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.isCancelled {
                let allItemsPrepared = mediaItems.filter{ $0.error != nil }.isEmpty
                completion(allItemsPrepared)
            }
        }
    }
    
    func prepare(mediaItems: [PendingMedia], isReady: Binding<Bool>, imagesAreProcessed: Binding<Bool>, numberOfFailedItems: Binding<Int>) {
        mediaItems.forEach{ prepare(mediaItem: $0) }
        imageProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.isCancelled {
                imagesAreProcessed.wrappedValue = true
            }
        }
        mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
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
        let typeSpecificProcessingGroup = item.type == .image ? imageProcessingGroup : nil
        typeSpecificProcessingGroup?.enter()
        mediaProcessingQueue.async(group: mediaProcessingGroup) { [weak self] in
            defer { typeSpecificProcessingGroup?.leave() }
            guard let self = self, !self.isCancelled else { return }
            // 1. Resize media as necessary.
            let mediaResizeCropGroup = DispatchGroup()
            switch item.type {
            case .image:
                mediaResizeCropGroup.enter()
                self.processImage(inMediaItem: item) { (result) in
                    defer { mediaResizeCropGroup.leave() }
                    switch result {
                    case .success(let processedData):
                        // Original image could be returned if resize wasn't necessary, thus this comparison.
                        if processedData.image != item.image {
                            mediaResizeCropGroup.enter()
                            DispatchQueue.main.async {
                                item.image = processedData.image
                                item.size = processedData.image.size
                                if let cropRect = processedData.cropRect, let originalImage = processedData.uncroppedImage, item.edit == nil {
                                    DDLogInfo("ImageServer/image/prepare set edit image")
                                    item.edit = PendingMediaEdit(image: originalImage)
                                    item.edit!.cropRect = cropRect
                                }
                                item.isResized = true
                                mediaResizeCropGroup.leave()
                            }
                        }

                    case .failure(let error):
                        item.error = error
                    }

                }

            case .video:
                if let url = item.videoURL, let max = self.maxVideoLength {
                    let asset = AVURLAsset(url: url)

                    if asset.duration.seconds > max {
                        DDLogWarn("ImageServer/video/prepare/warn  video is \(asset.duration.seconds) seconds long. Maximum is \(max) seconds. \(item)")
                        return
                    }
                }

                mediaResizeCropGroup.enter()
                defer { mediaResizeCropGroup.leave() }

                if !item.isResized {
                    mediaResizeCropGroup.enter()
                    ImageServer.mediaProcessingSemaphore.wait()
                    self.resizeVideo(inMediaItem: item) { (result) in
                        defer {
                            mediaResizeCropGroup.leave()
                            ImageServer.mediaProcessingSemaphore.signal()
                        }

                        switch (result) {
                        case .success(let (videoUrl, videoResolution)):
                            mediaResizeCropGroup.enter()
                            DispatchQueue.main.async {
                                item.videoURL = videoUrl
                                item.size = videoResolution
                                item.isResized = true
                                mediaResizeCropGroup.leave()
                            }

                        case .failure(let error):
                            item.error = error
                        }
                    }
                }
            }

            // 2. Encrypt media.
            self.mediaProcessingGroup.enter()
            typeSpecificProcessingGroup?.enter()
            mediaResizeCropGroup.notify(queue: self.mediaProcessingQueue) {
                defer {
                    self.mediaProcessingGroup.leave()
                    typeSpecificProcessingGroup?.leave()
                }
                guard item.error == nil, !self.isCancelled else { return }

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
                                
                guard item.error == nil && plaintextData != nil else { return }

                // 2.2 Encrypt media.
                let ts = Date()
                let encryptedData: Data, key: Data, sha256Hash: Data
                DDLogDebug("ImageServer/encrypt/begin")
                do {
                    (encryptedData, key, sha256Hash) = try MediaCrypter.encrypt(data: plaintextData, mediaType: item.type)
                } catch {
                    DDLogError("ImageServer/encrypt/error item=[\(item)] [\(error)]")
                    item.error = error
                    return
                }
                DDLogDebug("ImageServer/encrypt/finished  Duration: \(-ts.timeIntervalSinceNow) s")

                // 2.3 Save encrypted data into a temp file.
                if let existingFileURL = item.encryptedFileUrl {
                    do {
                        try FileManager.default.removeItem(at: existingFileURL)
                        DDLogInfo("ImageServer/media/delete-existing-encrypted/deleted [\(existingFileURL.absoluteString)]")
                    } catch {
                        DDLogError("ImageServer/media/delete-existing-encrypted/error [\(error)]")
                    }
                }
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
                    return
                }
            }
        }
    }

    private func cropImage(inMediaItem item: PendingMedia, image: UIImage, completion: @escaping (Result<ProcessedImageData, Error>) -> ()) {
        guard let maxAllowedAspectRatio = maxAllowedAspectRatio, image.size.height > maxAllowedAspectRatio * image.size.width else {
            completion(.success(ProcessedImageData(image: image)))
            return
        }

        DDLogInfo("ImageServer/image/prepare  Cropping image to ratio: [\(maxAllowedAspectRatio)]")
        let ts = Date()
        guard let croppedImage = image.aspectRatioCropped(heightToWidthRatio: maxAllowedAspectRatio) else {
            DDLogError("ImageServer/image/prepare/error  Cropping failed [\(item)]")
            completion(.failure(ImageProcessingError.cropFailure))
            return
        }
        DDLogDebug("ImageServer/image/prepare  Cropped in \(-ts.timeIntervalSinceNow) s")
        DDLogInfo("ImageServer/image/prepare  Cropped image size: [\(NSCoder.string(for: croppedImage.size))]")

        let cropOrigin = CGPoint(x: 0, y: (image.size.height - croppedImage.size.height) / 2)
        let cropRect = CGRect(origin: cropOrigin, size: croppedImage.size)

        completion(.success(ProcessedImageData(image: croppedImage, uncroppedImage: image, cropRect: cropRect)))
    }

    private func processImage(inMediaItem item: PendingMedia, completion: @escaping (Result<ProcessedImageData, Error>) -> ()) {
        guard let image = item.image else {
            DDLogError("ImageServer/image/prepare/error  Empty image [\(item)]")
            completion(.failure(ImageProcessingError.invalidImage))
            return
        }
        DDLogInfo("ImageServer/image/prepare  Original image size: [\(NSCoder.string(for: item.size!))]")

        let imageSize = image.size

        // Do not resize if image is within required dimensions.
        guard imageSize.width > Constants.maxImageSize || imageSize.height > Constants.maxImageSize else {
            cropImage(inMediaItem: item, image: image, completion: completion)
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

        cropImage(inMediaItem: item, image: resized, completion: completion)
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
        DDLogInfo("ImageServer/video/prepare/ready  Original Video size: [\(fileSize)] url=[\(videoUrl.description)]")

        // Sometimes NextLevelSessionExporterError/AVAssetReader is unable to process videos if they are not copied first
        let tempMediaURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("mp4")

        do {
            try FileManager.default.copyItem(at: videoUrl, to: tempMediaURL)
        } catch {
            DDLogError("ImageServer/video/prepare/error Failed to copy [\(error)] url=[\(videoUrl.description)] tmp=[\(tempMediaURL.description)]")
            completion(.failure(VideoProcessingError.failedToCopyLocally))
            return
        }
        DDLogInfo("ImageServer/video/prepare/ready  Temporary url: [\(tempMediaURL.description)] url=[\(videoUrl.description)] original order=[\(item.order)]")

        VideoUtils.resizeVideo(inputUrl: tempMediaURL) { (result) in
            do {
                try FileManager.default.removeItem(at: tempMediaURL)
                DDLogInfo("video-processing/export/cleanup/\(tempMediaURL.absoluteString)/deleted")
            } catch {
                DDLogError("video-processing/export/cleanup/\(tempMediaURL.absoluteString)/error [\(error)]")
            }
            switch result {
            case .success(let (_, videoResolution)):
                DDLogInfo("ImageServer/video/prepare/ready  New video resolution: [\(videoResolution)] [\(tempMediaURL.description)]")

            case .failure(let error):
                DDLogError("ImageServer/video/prepare/error [\(error)] [\(tempMediaURL.description)]")
            }
            completion(result)
        }
    }
}
