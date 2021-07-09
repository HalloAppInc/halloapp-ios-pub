//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
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

                    if tmp != url {
                        try FileManager.default.removeItem(at: tmp)
                        DDLogInfo("ImageServer/prepare/media/deleted url=[\(tmp.description)]")
                    }
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
        completion(self.resize(image: url).flatMap(self.save(image:)))
    }

    private func save(image: UIImage) -> Result<(URL, CGSize), Error> {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("jpg")

        guard image.save(to: output) else {
            DDLogError("ImageServer/image/prepare/error  JPEG conversation failure")
            return .failure(ImageProcessingError.jpegConversionFailure)
        }

        DDLogInfo("ImageServer/image/prepare  Saving temporarily to: [\(output.description)]")

        return .success((output, image.size))
    }

    private func resize(image url: URL) -> Result<UIImage, Error> {
        let ts = Date()
        if let image = UIImage.thumbnail(contentsOf: url, maxPixelSize: Constants.maxImageSize) {
            DDLogDebug("ImageServer/image/resize  Resized in \(-ts.timeIntervalSinceNow) s")
            DDLogInfo("ImageServer/image/resize  Downscaled image size: [\(image.size)]")
            return .success(image)
        } else {
            DDLogError("ImageServer/image/resize/error  Resizing failed")
            return .failure(ImageProcessingError.resizeFailure)
        }
    }

    private func resize(video url: URL, completion: @escaping (Result<(URL, CGSize), Error>) -> Void) {
        guard shouldConvert(video: url) else {
            DDLogInfo("ImageServer/video/prepare/ready  conversion not required [\(url.description)]")

            VideoUtils.optimizeForStreaming(url: url) {
                switch $0 {
                case .success(let url):
                    if let resolution = VideoUtils.resolutionForLocalVideo(url: url) {
                        return completion(.success((url, resolution)))
                    } else {
                        DDLogError("ImageServer/video/prepare/error  Failed to get resolution. \(url.description)")
                        return completion(.failure(VideoProcessingError.failedToLoad))
                    }
                case .failure(let err):
                    DDLogError("ImageServer/video/prepare/error  Failed to optimize [\(err)] \(url.description)")
                    return completion(.failure(VideoProcessingError.failedToLoad))
                }
            }

            return
        }

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
            case .success(let (outputUrl, videoResolution)):
                DDLogInfo("ImageServer/video/prepare/ready  New video resolution: [\(videoResolution)] [\(url.description)]")

                do {
                    try self.clearTimestamps(video: outputUrl)
                } catch {
                    DDLogError("ImageServer/video/prepare/error clearing timestamps [\(error)] [\(url.description)]")
                }
            case .failure(let error):
                DDLogError("ImageServer/video/prepare/error [\(error)] [\(url.description)]")
            }

            completion(result)
        }
    }

    // Clears uncompressed movie atom headers from timestamps
    //
    // Video format details
    // https://openmp4file.com/format.html
    // https://developer.apple.com/library/archive/documentation/QuickTime/QTFF/QTFFChap2/qtff2.html#//apple_ref/doc/uid/TP40000939-CH204-33299
    // https://www.cimarronsystems.com/wp-content/uploads/2017/04/Elements-of-the-H.264-VideoAAC-Audio-MP4-Movie-v2_0.pdf
    private func clearTimestamps(video url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        // atom types
        guard let moov = "moov".data(using: .ascii) else { return }
        guard let mvhd = "mvhd".data(using: .ascii) else { return }
        guard let tkhd = "tkhd".data(using: .ascii) else { return }
        guard let mdhd = "mdhd".data(using: .ascii) else { return }

        // Find the moov atom
        try handle.seek(toOffset: 0)
        guard var moovIdx = handle.availableData.firstRange(of: moov)?.lowerBound else { return }
        moovIdx -= 4

        try handle.seek(toOffset: UInt64(moovIdx))
        var data = handle.availableData
        guard !data.isEmpty && data.count > 8 else { return }

        let moovSize = (Int(data[0]) << 24) + (Int(data[1]) << 16) + (Int(data[2]) << 8) + Int(data[3])
        data = data.subdata(in: 0..<moovSize)

        try clearTimestamps(for: mvhd, from: data, at: moovIdx, in: handle)
        try clearTimestamps(for: tkhd, from: data, at: moovIdx, in: handle)
        try clearTimestamps(for: mdhd, from: data, at: moovIdx, in: handle)

        try handle.synchronize()
    }

    // Finds the atoms for the specified header, maps the timestamp locations in the file and clears them
    private func clearTimestamps(for header: Data, from data: Data, at offset: Int, in handle: FileHandle) throws {
        var searchRange = 0..<data.count
        while let position = data.firstRange(of: header, in: searchRange) {
            try handle.seek(toOffset: UInt64(offset + position.upperBound) + 4)
            handle.write(Data(count: 8))

            searchRange = position.upperBound..<data.count
        }
    }

    private func shouldConvert(video url: URL) -> Bool {
        let asset = AVURLAsset(url: url, options: nil)

        for track in asset.tracks {
            if track.timeRange.duration != .zero && track.estimatedDataRate > Float(ServerProperties.maxVideoBitRate) {
                DDLogInfo("ImageServer/video/prepare/shouldConvert bitrate[\(track.estimatedDataRate)] > max[\(ServerProperties.maxVideoBitRate)]  [\(url.description)]")
                return true
            }
        }

        return false
    }
}
