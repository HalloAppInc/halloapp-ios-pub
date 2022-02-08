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
    var url: URL
    var size: CGSize
    var key: String
    var sha256: String

    func copy(to destination: URL) {
        let manager = FileManager.default
        let encrypted = url.appendingPathExtension("enc")
        let encryptedDestination = destination.appendingPathExtension("enc")

        do {
            try manager.copyItem(at: url, to: destination)
            DDLogInfo("ImageServer/result copied from=[\(url)] to=[\(destination)]")

            try manager.copyItem(at: encrypted, to: encryptedDestination)
            DDLogInfo("ImageServer/result copied from=[\(encrypted)] to=[\(encryptedDestination)]")
        } catch {
            DDLogError("ImageServer/result/copy/error [\(error)]")
        }
    }

    func clear() {
        let manager = FileManager.default
        let encrypted = url.appendingPathExtension("enc")

        do {
            try manager.removeItem(at: url)
            DDLogInfo("ImageServer/result deleted url=[\(url)]")

            try manager.removeItem(at: encrypted)
            DDLogInfo("ImageServer/result deleted url=[\(encrypted)]")
        } catch {
            DDLogError("ImageServer/result/clear/error [\(error)]")
        }
    }
}

class ImageServer {
    private struct Constants {
        static let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
        static let maxImageSize: CGFloat = 1600
    }

    typealias Completion = (Result<ImageServerResult, Error>) -> ()

    private class Task {
        var id: String?
        var index: Int?
        var url: URL
        var progress: Float {
            didSet {
                if let id = self.id {
                    ImageServer.shared.progress.send(id)
                }
            }
        }
        var result: Result<ImageServerResult, Error>? {
            didSet {
                guard let result = self.result else { return }

                if case .success(_) = result {
                    progress = 1
                }

                for completion in callbacks {
                    completion(result)
                }
            }
        }
        var callbacks: [Completion] = []
        var videoExporter: CancelableExporter?

        internal init(id: String?, index: Int?, url: URL, completion: Completion?) {
            if let completion = completion {
                self.callbacks.append(completion)
            }

            self.id = id
            self.index = index
            self.url = url
            self.progress = 0
        }
    }

    static let shared = ImageServer()

    private let queue = DispatchQueue(label: "ImageServer.MediaProcessing", qos: .userInitiated)
    private var tasks = [Task]()
    public let progress = PassthroughSubject<String, Never>()

    private init() {}

    public func progress(for id: String) -> (Int, Float) {
        queue.sync {
            let items = self.tasks.filter { $0.id == id }
            guard items.count > 0 else { return (0, 0) }

            let total = items.reduce(into: Float(0)) { $0 += $1.progress }
            return (items.count, total / Float(items.count))
        }
    }

    public func clearAllTasks(keepFiles: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if !keepFiles {
                for task in self.tasks {
                    if case .success(let reseult) = task.result {
                        reseult.clear()
                    }
                }
            }

            self.tasks.removeAll()
        }
    }

    public func clearAllTasks(for id: String, keepFiles: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                guard task.id == id else { return }
                task.videoExporter?.cancel()

                if !keepFiles {
                    if case .success(let reseult) = task.result {
                        reseult.clear()
                    }
                }
            }

            self.tasks.removeAll { $0.id == id }
        }
    }

    public func clearTask(for url: URL, keepFiles: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                guard task.url == url else { return }
                task.videoExporter?.cancel()

                if !keepFiles {
                    if case .success(let reseult) = task.result {
                        reseult.clear()
                    }
                }
            }

            self.tasks.removeAll { $0.url == url }
        }
    }

    // Prevents having more than 3 instances of AVAssetReader
    private static let mediaProcessingSemaphore = DispatchSemaphore(value: 3)

    private func find(url: URL, id: String? = nil, index: Int? = nil) -> Task? {
        if let t = (tasks.first { $0.url == url }) {
            return t
        } else if let t = (tasks.first { $0.id == id && $0.index == index }) {
            return t
        }

        return nil
    }

    func attach(for url: URL, id: String? = nil, index: Int? = nil, completion: Completion? = nil) {
        queue.async {
            if let task = self.find(url: url, id: id, index: index) {
                task.id = id
                task.index = index

                if let completion = completion {
                    task.callbacks.append(completion)
                }
            }
        }
    }

    func prepare(_ type: FeedMediaType, url: URL, for id: String? = nil, index: Int? = nil, completion: Completion? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let task = self.find(url: url, id: id, index: index) {
                task.id = id
                task.index = index

                if let completion = completion {
                    task.callbacks.append(completion)

                    if let result = task.result {
                        completion(result)
                    }
                }

                return
            }

            let task = Task(id: id, index: index, url: url, completion: completion)
            self.tasks.append(task)

            let onCompletion: (Result<(URL, CGSize), Error>) -> Void = { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success((let processed, let size)):
                    let encrypted = processed.appendingPathExtension("enc")
                    task.result = self.encrypt(type, input: processed, output: encrypted).map {
                        ImageServerResult(url: processed, size: size, key: $0.key, sha256: $0.sha256)
                    }
                case .failure(let error):
                    task.result = .failure(error)
                }
            }

            switch type {
            case .image:
                self.process(image: url, completion: onCompletion)
            case .video:
                self.resize(video: task, completion: onCompletion)
            case .audio:
                onCompletion(.success((url, .zero)))
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

    private func resize(video task: Task, completion: @escaping (Result<(URL, CGSize), Error>) -> Void) {
        guard shouldConvert(video: task.url) else {
            DDLogInfo("ImageServer/video/prepare/ready  conversion not required [\(task.url)]")

            if let resolution = VideoUtils.resolutionForLocalVideo(url: task.url) {
                VideoUtils.optimizeForStreaming(url: task.url) {
                    switch $0 {
                    case .success(let optimized):
                        DDLogInfo("ImageServer/video/optimize success \(optimized.description)")
                        completion(.success((optimized, resolution)))
                    case .failure(let err):
                        DDLogError("ImageServer/video/optimize/error [\(err)] \(task.url.description)")
                        AppContext.shared.errorLogger?.logError(err)
                        completion(.success((task.url, resolution)))
                    }
                }
            } else {
                DDLogError("ImageServer/video/prepare/error  Failed to get resolution. \(task.url.description)")
                completion(.failure(VideoProcessingError.failedToLoad))
            }

            return
        }

        guard let fileAttrs = try? FileManager.default.attributesOfItem(atPath: task.url.path) else {
            DDLogError("ImageServer/video/prepare/error  Failed to get file attributes. \(task.url)")
            return completion(.failure(VideoProcessingError.failedToLoad))
        }

        let fileSize = fileAttrs[FileAttributeKey.size] as! NSNumber
        DDLogInfo("ImageServer/video/prepare/ready  Original Video size: [\(fileSize)] url=[\(task.url)]")

        ImageServer.mediaProcessingSemaphore.wait()
        task.videoExporter = VideoUtils.resizeVideo(inputUrl: task.url, progress: { task.progress = $0 }) { (result) in
            ImageServer.mediaProcessingSemaphore.signal()

            switch result {
            case .success(let (outputUrl, videoResolution)):
                DDLogInfo("ImageServer/video/prepare/ready  New video resolution: [\(videoResolution)] [\(task.url)]")

                do {
                    try self.clearTimestamps(video: outputUrl)
                } catch {
                    DDLogError("ImageServer/video/prepare/error clearing timestamps [\(error)] [\(task.url)]")
                }
            case .failure(let error):
                DDLogError("ImageServer/video/prepare/error [\(error)] [\(task.url)]")
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

        let moovSize = Int(data[0..<4].withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) })
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

    // removes the original media and encrypted media file, only relevant for outbound media
    static public func cleanUpUploadData(directoryURL: URL, relativePath: String?) {
        guard let processedMediaRelativePath = relativePath else { return }
        let processedSuffix = "processed."
        let encryptedSuffix = "enc"

        let originalMediaRelativePath = processedMediaRelativePath.replacingOccurrences(of: processedSuffix, with: "")

        let originalMediaFileURL = directoryURL.appendingPathComponent(originalMediaRelativePath, isDirectory: false)
        let processedMediaFileURL = directoryURL.appendingPathComponent(processedMediaRelativePath, isDirectory: false)
        let encryptedMediaFileURL = processedMediaFileURL.appendingPathExtension(encryptedSuffix)

        do {
            try FileManager.default.removeItem(at: originalMediaFileURL)    // xxx.jpg
            try FileManager.default.removeItem(at: encryptedMediaFileURL)   // xxx.processed.jpg.enc
        }
        catch {
            DDLogError("ImageServer/cleanUpUploadData/error [\(error)]")
        }
    }
}
