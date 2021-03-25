//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Combine
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

struct ImageServerResult {
    var size: CGSize
    var key: String
    var sha256: String
}

class ImageServer {
    private struct Constants {
        static let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
        static let maxImageSize: CGFloat = 1600
    }

    private static let mediaProcessingSemaphore = DispatchSemaphore(value: 3) // Prevents having more than 3 instances of AVAssetReader

    private let mediaProcessingQueue = DispatchQueue(label: "ImageServer.MediaProcessing")
    private var isCancelled = false
    private var maxAllowedAspectRatio: CGFloat? = nil

    init(maxAllowedAspectRatio: CGFloat? = nil) {
        self.maxAllowedAspectRatio = maxAllowedAspectRatio
    }

    func cancel() {
        isCancelled = true
    }

    func prepare(_ type: FeedMediaType, url: URL, output: URL, completion: @escaping (Result<ImageServerResult, Error>) -> Void) {
        let processingCompletion: (Result<(URL, CGSize), Error>) -> Void = { [weak self] result in
            guard let self = self, !self.isCancelled else { return }

            switch result {
            case .success((let tmp, let size)):
                do {
                    try FileManager.default.copyItem(at: tmp, to: output)
                    DDLogInfo("ImageServer/prepare/media/processed copied from=[\(tmp.description)] to=[\(output.description)]")

                    try FileManager.default.removeItem(at: tmp)
                    DDLogInfo("ImageServer/prepare/media/deleted url=[\(tmp.description)]")
                } catch {
                    DDLogError("ImageServer/preapre/media/error error=[\(error)]")
                }

                completion(
                    self.encrypt(type, input: output, output: output.appendingPathExtension("enc"))
                        .map { ImageServerResult(size: size, key: $0.key, sha256: $0.sha256) }
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }

        mediaProcessingQueue.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }

            switch type {
            case .image:
                self.process(image: url, completion: processingCompletion)
            case .video:
                self.resize(video: url, completion: processingCompletion)
            }
        }
    }

    private func encrypt(_ type: FeedMediaType, input: URL, output: URL) -> Result<(key: String, sha256: String), Error> {
        // TODO:  Encrypt media without loading into memory.
        guard let plaintextData = try? Data(contentsOf: input) else {
            DDLogError("ImageServer/encrypt/media/error  File not accessible")
            return .failure(VideoProcessingError.failedToLoad)
        }
        DDLogInfo("ImageServer/prepare/media/ready  New media file size: [\(plaintextData.count)]")

        // encrypt
        let ts = Date()
        let encryptedData: Data, key: Data, sha256Hash: Data
        DDLogDebug("ImageServer/encrypt/begin")
        do {
            (encryptedData, key, sha256Hash) = try MediaCrypter.encrypt(data: plaintextData, mediaType: type)
        } catch {
            DDLogError("ImageServer/encrypt/error url=[\(input.description)] [\(error)]")
            return .failure(error)
        }
        DDLogDebug("ImageServer/encrypt/finished  Duration: \(-ts.timeIntervalSinceNow) s")

        // save encrypted data
        DDLogDebug("ImageServer/media/save-enc to [\(output.description)]")
        do {
            try encryptedData.write(to: output, options: [ .atomic ])
            return .success((key.base64EncodedString(), sha256Hash.base64EncodedString()))
        } catch {
            DDLogError("ImageServer/media/save-enc/error [\(error)]")
            return .failure(error)
        }
    }

    private func process(image url: URL, completion: @escaping (Result<(URL, CGSize), Error>) -> Void) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, !self.isCancelled else { return }

            guard let data = data, error == nil else {
                DDLogError("ImageServer/image/prepare/error  Cannot get image url=[\(url.description)] [\(String(describing: error))]")
                return completion(.failure(ImageProcessingError.invalidImage))
            }

            guard let image = UIImage(data: data) else {
                DDLogError("ImageServer/image/prepare/error  Empty image url=[\(url.description)]")
                return completion(.failure(ImageProcessingError.invalidImage))
            }

            completion(
                self.resize(image: image)
                .flatMap(self.crop(image:))
                .flatMap(self.save(image:))
            )
        }.resume()
    }

    private func save(image: UIImage) -> Result<(URL, CGSize), Error> {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            DDLogError("ImageServer/image/prepare/error  JPEG conversation failure")
            return .failure(ImageProcessingError.jpegConversionFailure)
        }

        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("jpg")

        DDLogInfo("ImageServer/image/prepare  Saving temporarily to: [\(output.description)]")

        return Result {
            try data.write(to: output)
        }.map {
            (output, image.size)
        }
    }

    private func crop(image: UIImage) -> Result<UIImage, Error> {
        guard let maxAllowedAspectRatio = maxAllowedAspectRatio, image.size.height > maxAllowedAspectRatio * image.size.width else {
            return .success(image)
        }

        DDLogInfo("ImageServer/image/crop  Cropping image to ratio: [\(maxAllowedAspectRatio)]")
        let ts = Date()
        guard let cropped = image.aspectRatioCropped(heightToWidthRatio: maxAllowedAspectRatio) else {
            DDLogError("ImageServer/image/crop/error  Cropping failed")
            return .failure(ImageProcessingError.cropFailure)
        }

        DDLogDebug("ImageServer/image/crop  Cropped in \(-ts.timeIntervalSinceNow) s")
        DDLogInfo("ImageServer/image/crop  Cropped image size: [\(cropped.size))]")

        return .success(cropped)
    }

    private func resize(image: UIImage) -> Result<UIImage, Error> {
        guard image.size.width > Constants.maxImageSize || image.size.height > Constants.maxImageSize else {
            return .success(image)
        }

        let aspectRatio = min(Constants.maxImageSize / image.size.width, Constants.maxImageSize / image.size.height)
        let targetSize = CGSize(width: (image.size.width * aspectRatio).rounded(), height: (image.size.height * aspectRatio).rounded())

        let ts = Date()
        guard let resized = image.fastResized(to: targetSize) else {
            DDLogError("ImageServer/image/resize/error  Resizing failed")
            return .failure(ImageProcessingError.resizeFailure)
        }

        DDLogDebug("ImageServer/image/resize  Resized in \(-ts.timeIntervalSinceNow) s")
        DDLogInfo("ImageServer/image/resize  Downscaled image size: [\(resized.size)]")

        return .success(resized)
    }

    private func resize(video url: URL, completion: @escaping (Result<(URL, CGSize), Error>) -> Void) {
        guard let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            DDLogError("ImageServer/video/prepare/error  Failed to get file attributes. \(url.description)")
            return completion(.failure(VideoProcessingError.failedToLoad))
        }

        let fileSize = fileAttrs[FileAttributeKey.size] as! NSNumber
        DDLogInfo("ImageServer/video/prepare/ready  Original Video size: [\(fileSize)] url=[\(url.description)]")

        ImageServer.mediaProcessingSemaphore.wait()
        VideoUtils.resizeVideo(inputUrl: url) { (result) in
            ImageServer.mediaProcessingSemaphore.signal()

            switch result {
            case .success(let (_, videoResolution)):
                DDLogInfo("ImageServer/video/prepare/ready  New video resolution: [\(videoResolution)] [\(url.description)]")
            case .failure(let error):
                DDLogError("ImageServer/video/prepare/error [\(error)] [\(url.description)]")
            }

            completion(result)
        }
    }
}
