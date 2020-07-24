//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
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
    case fileInaccessible
}

class ImageServer {
    private let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
    private let maxImageSize: CGFloat = 1600
    private let mediaProcessingQueue = DispatchQueue(label: "ImageServer.MediaProcessing")
    private let mediaProcessingGroup = DispatchGroup()
    private var cancelled = false

    func upload(_ mediaItems: [PendingMedia], completion: @escaping (Bool) -> Void) {
        mediaItems.forEach{ self.initiateUpload($0) }
        self.mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.cancelled {
                let allUploadsSuccessful = mediaItems.filter{ $0.error != nil }.isEmpty
                completion(allUploadsSuccessful)
            }
        }
    }
    
    func upload(_ mediaItems: [PendingMedia], isReady: Binding<Bool>, numberOfFailedUploads: Binding<Int>) {
        mediaItems.forEach{ self.initiateUpload($0) }
        self.mediaProcessingGroup.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            if !self.cancelled {
                isReady.wrappedValue = true
                numberOfFailedUploads.wrappedValue = mediaItems.filter{ $0.error != nil }.count
            }
        }
    }

    func cancel() {
        self.cancelled = true
        AF.session.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) in
            uploadTasks.forEach { (task) in
                // Cancellation of a task will invoke task completion handler.
                DDLogDebug("ImageServer/upload/cancel")
                task.cancel()
            }
        }
    }

    private func initiateUpload(_ item: PendingMedia) {
        self.mediaProcessingGroup.enter()
        let request = XMPPMediaUploadURLRequest(completion: { urls, error in
            guard !self.cancelled else {
                self.mediaProcessingGroup.leave()
                return
            }
            if urls != nil {
                self.processAndUpload(item, to: urls!)
            } else {
                item.error = error!
            }
            self.mediaProcessingGroup.leave()
        })
        AppContext.shared.xmppController.enqueue(request: request)
    }

    private func processAndUpload(_ item: PendingMedia, to mediaURL: MediaURL) {
        item.url = mediaURL.get

        self.mediaProcessingGroup.enter()
        self.mediaProcessingQueue.async {
            var plaintextData: Data? = nil

            let mediaResizeGroup = DispatchGroup()
            switch (item.type) {
            case .image:
                guard let image = item.image else {
                    DDLogError("ImageServer/image/prepare/error  Empty image [\(item)]")
                    item.error = ImageProcessingError.invalidImage
                    break
                }
                DDLogInfo("ImageServer/image/prepare  Original image size: [\(NSCoder.string(for: item.size!))]")

                // TODO: move resize off the main thread
                let imageSize = item.size!
                if imageSize.width > self.maxImageSize || imageSize.height > self.maxImageSize {
                    let aspectRatioForWidth = self.maxImageSize / imageSize.width
                    let aspectRatioForHeight = self.maxImageSize / imageSize.height
                    let aspectRatio = min(aspectRatioForWidth, aspectRatioForHeight)
                    let targetSize = CGSize(width: (imageSize.width * aspectRatio).rounded(), height: (imageSize.height * aspectRatio).rounded())

                    let ts = Date()
                    guard let resized = image.resized(to: targetSize) else {
                        DDLogError("ImageServer/image/prepare/error  Resize failed [\(item)]")
                        item.error = ImageProcessingError.resizeFailure
                        break
                    }
                    DDLogDebug("ImageServer/image/prepare  Resized in \(-ts.timeIntervalSinceNow) s")

                    self.mediaProcessingGroup.enter()
                    DispatchQueue.main.async {
                        item.image = resized
                        item.size = resized.size
                        self.mediaProcessingGroup.leave()
                    }

                    DDLogInfo("ImageServer/image/prepare  Downscaled image size: [\(item.size!)]")
                }

                guard let imgData = item.image!.jpegData(compressionQuality: self.jpegCompressionQuality) else {
                    DDLogError("ImageServer/image/prepare/error  Failed to generate JPEG data. \(item)")
                    item.error = ImageProcessingError.jpegConversionFailure
                    break
                }
                DDLogInfo("ImageServer/image/prepare/ready  JPEG Quality: [\(self.jpegCompressionQuality)] Size: [\(imgData.count)]")

                plaintextData = imgData

            case .video:
                guard let videoUrl = item.videoURL else {
                    DDLogError("ImageServer/video/prepare/error  Empty video URL. \(item)")
                    item.error = VideoProcessingError.emptyURL
                    break
                }
                guard let fileAttrs = try? FileManager.default.attributesOfItem(atPath: videoUrl.path) else {
                    DDLogError("ImageServer/video/prepare/error  Failed to get file attributes. \(item)")
                    item.error = VideoProcessingError.fileInaccessible
                    break
                }
                let fileSize = fileAttrs[FileAttributeKey.size] as! NSNumber
                DDLogInfo("ImageServer/video/prepare/ready  Original Video size: [\(fileSize)]")

                mediaResizeGroup.enter()
                VideoUtils.resizeVideo(inputUrl: videoUrl) { (result) in
                    switch result {
                    case .success(let (videoURL, videoResolution)):
                        if let resizedVideoData = try? Data(contentsOf: videoURL) {
                            DDLogInfo("ImageServer/video/prepare/ready  New Video file size: [\(resizedVideoData.count)]")
                            self.mediaProcessingGroup.enter()
                            DispatchQueue.main.async {
                                item.size = videoResolution
                                self.mediaProcessingGroup.leave()
                            }
                            plaintextData = resizedVideoData
                        } else {
                            DDLogError("ImageServer/video/prepare/error  File not accessible")
                            item.error = VideoProcessingError.fileInaccessible
                        }

                    case .failure(let error):
                        DDLogError("ImageServer/video/prepare/error [\(error)]")
                        item.error = error
                    }
                    mediaResizeGroup.leave()
                }
            }

            mediaResizeGroup.notify(queue: self.mediaProcessingQueue) {
                                
                guard plaintextData != nil else {
                    self.mediaProcessingGroup.leave()
                    return
                }

                // Save unencrypted data to disk - this will be copied to Feed media directory
                // if user proceeds posting media.
                let tempMediaURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(item.url!.lastPathComponent)
                DDLogDebug("ImageServer/media/copy to [\(tempMediaURL)]")
                do {
                    try plaintextData?.write(to: tempMediaURL, options: [ .atomic ])
                    item.fileURL = tempMediaURL
                }
                catch {
                    DDLogError("ImageServer/media/copy/error [\(error)]")
                    // TODO: assign error
                    self.mediaProcessingGroup.leave()
                    return
                }

                let ts = Date()
                let data: Data, key: Data, sha256Hash: Data
                DDLogDebug("ImageServer/encrypt/begin")
                do {
                    (data, key, sha256Hash) = try MediaCrypter.encrypt(data: plaintextData!, mediaType: item.type)
                } catch {
                    DDLogError("ImageServer/encrypt/error item=[\(item)] [\(error)]")
                    // TODO: assign error
                    self.mediaProcessingGroup.leave()
                    return
                }
                DDLogDebug("ImageServer/encrypt/finished  Duration: \(-ts.timeIntervalSinceNow) s")

                self.mediaProcessingGroup.enter()
                DispatchQueue.main.async {
                    if (self.cancelled) {
                        // Post composer was canceled while media was being processed.
                        self.mediaProcessingGroup.leave()
                        return
                    }

                    // Encryption data would be send over the wire and saved to db.
                    item.key = key.base64EncodedString()
                    item.sha256 = sha256Hash.base64EncodedString()

                    // Start upload.
                    DDLogDebug("ImageServer/upload/begin url=[\(mediaURL.get)]")
                    self.mediaProcessingGroup.enter()
                    AF.upload(data, to: mediaURL.put, method: .put, headers: [ "Content-Type": "application/octet-stream" ]).response { (response) in
                        if (response.error != nil) {
                            DDLogError("ImageServer/upload/error url=[\(mediaURL.get)] [\(response.error!)]")
                            item.error = response.error
                        } else {
                            DDLogDebug("ImageServer/upload/success url=[\(mediaURL.get)]")
                        }
                        self.mediaProcessingGroup.leave()
                    }
                    self.mediaProcessingGroup.leave()
                }

                self.mediaProcessingGroup.leave()
            }
        }
    }
}
