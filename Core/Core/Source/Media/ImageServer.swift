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
import CoreCommon

enum MediaProcessingError: Error {
    case failedToReadSize
    case failedToOpenFile
    case unexpectedEndOfFile
}

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

public struct ImageServerResult {
    public var url: URL
    public var size: CGSize
    public var key: String
    public var sha256: String
    public var chunkSize: Int32
    public var blobSize: Int64

    @discardableResult
    public func copy(to destination: URL) -> Bool {
        let manager = FileManager.default
        let encrypted = url.appendingPathExtension("enc")
        let encryptedDestination = destination.appendingPathExtension("enc")

        do {
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
                DDLogInfo("ImageServer/result deleted url=[\(url)]")
            }

            if manager.fileExists(atPath: encryptedDestination.path) {
                try manager.removeItem(at: encryptedDestination)
                DDLogInfo("ImageServer/result deleted url=[\(encrypted)]")
            }

            try manager.copyItem(at: url, to: destination)
            DDLogInfo("ImageServer/result copied from=[\(url)] to=[\(destination)]")

            try manager.copyItem(at: encrypted, to: encryptedDestination)
            DDLogInfo("ImageServer/result copied from=[\(encrypted)] to=[\(encryptedDestination)]")

            return true
        } catch {
            DDLogError("ImageServer/result/copy/error [\(error)]")
            return false
        }
    }

    public func clear() {
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

public class ImageServer {
    private struct Constants {
        static let jpegCompressionQuality = CGFloat(UserData.compressionQuality)
        static let maxImageSize: CGFloat = 1600
    }

    public typealias Completion = (Result<ImageServerResult, Error>) -> ()

    private class Task {
        var id: String?
        var index: Int?
        var url: URL
        var shouldStreamVideo: Bool
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

        internal init(id: String?, index: Int?, url: URL, shouldStreamVideo: Bool, completion: Completion?) {
            if let completion = completion {
                self.callbacks.append(completion)
            }

            self.id = id
            self.index = index
            self.url = url
            self.shouldStreamVideo = shouldStreamVideo
            self.progress = 0
        }
    }

    public static let shared = ImageServer()

    private let taskQueue = DispatchQueue(label: "ImageServer.Tasks", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "ImageServer.MediaProcessing", qos: .userInitiated)
    private var tasks = [Task]()
    public let progress = PassthroughSubject<String, Never>()
    private let chunkSize = 512 * 1024 // 0.5MB

    private init() {}

    public func progress(for id: String) -> (Int, Float) {
        taskQueue.sync {
            let items = self.tasks.filter { $0.id == id }
            guard items.count > 0 else { return (0, 0) }

            let total = items.reduce(into: Float(0)) { $0 += $1.progress }
            return (items.count, total / Float(items.count))
        }
    }

    public func clearAllTasks(keepFiles: Bool = true) {
        taskQueue.sync { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                task.videoExporter?.cancel()

                if case .success(let result) = task.result, !keepFiles {
                    result.clear()
                }
            }

            self.tasks.removeAll()
        }
    }

    public func clearAllTasks(for id: String, keepFiles: Bool = true) {
        taskQueue.sync { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                guard task.id == id else { continue }
                task.videoExporter?.cancel()

                if case .success(let result) = task.result, !keepFiles {
                    result.clear()
                }
            }

            self.tasks.removeAll { $0.id == id }
        }
    }

    public func clearTask(for url: URL, keepFiles: Bool = true) {
        taskQueue.sync { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                guard task.url == url else { continue }
                task.videoExporter?.cancel()

                if case .success(let result) = task.result, !keepFiles {
                    result.clear()
                }
            }

            self.tasks.removeAll { $0.url == url }
        }
    }

    public func clearUnattachedTasks(keepFiles: Bool = true) {
        taskQueue.sync { [weak self] in
            guard let self = self else { return }

            for task in self.tasks {
                guard task.id == nil else { continue }
                task.videoExporter?.cancel()

                if case .success(let result) = task.result, !keepFiles {
                    result.clear()
                }
            }

            self.tasks.removeAll { $0.id == nil }
        }
    }

    // Prevents having more than 3 instances of AVAssetReader
    private static let mediaProcessingSemaphore = DispatchSemaphore(value: 3)

    private func find(url: URL, id: String? = nil, index: Int? = nil, shouldStreamVideo: Bool? = nil) -> Task? {
        taskQueue.sync {
            if let t = (tasks.first { $0.url == url && (shouldStreamVideo == nil || $0.shouldStreamVideo == shouldStreamVideo) }) {
                return t
            } else if let id = id, let index = index, let t = (tasks.first { $0.id == id && $0.index == index && (shouldStreamVideo == nil || $0.shouldStreamVideo == shouldStreamVideo) }) {
                return t
            }

            return nil
        }
    }

    public func attach(for url: URL, id: String? = nil, index: Int? = nil, completion: Completion? = nil) {
        if let task = self.find(url: url, id: id, index: index) {
            task.id = id
            task.index = index

            if let completion = completion {
                task.callbacks.append(completion)
            }
        }
    }

    public func prepare(_ type: CommonMediaType, url: URL, for id: String? = nil, index: Int? = nil, shouldStreamVideo: Bool, completion: Completion? = nil) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if let task = self.find(url: url, id: id, index: index, shouldStreamVideo: shouldStreamVideo) {
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

            let task = Task(id: id, index: index, url: url, shouldStreamVideo: shouldStreamVideo, completion: completion)
            self.tasks.append(task)

            let onCompletion: (Result<(URL, CGSize), Error>) -> Void = { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success((let processed, let size)):
                    let encrypted = processed.appendingPathExtension("enc")
                    if shouldStreamVideo {
                        task.result = self.encryptChunkedMedia(type, input: processed, output: encrypted).map {
                            ImageServerResult(url: processed, size: size, key: $0.key, sha256: $0.sha256, chunkSize: $0.chunkSize, blobSize: $0.blobSize)
                        }
                    } else {
                        task.result = self.encrypt(type, input: processed, output: encrypted).map {
                            ImageServerResult(url: processed, size: size, key: $0.key, sha256: $0.sha256, chunkSize: 0, blobSize: 0)
                        }
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

    private func encrypt(_ type: CommonMediaType, input: URL, output: URL) -> Result<(key: String, sha256: String), Error> {
        let ts = Date()
        do {
            if FileManager.default.fileExists(atPath: output.path) {
                DDLogError("ImageServer/encrypt/error ecrypted file exists")
                try FileManager.default.removeItem(at: output)
            }

            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: nil)

            let crypter  = try MediaChunkCrypter(mediaType: type)
            let inputFile = try FileHandle(forReadingFrom: input)
            let outputFile = try FileHandle(forWritingTo: output)

            defer {
                inputFile.closeFile()
                outputFile.closeFile()
            }

            try crypter.encryptInit()

            while true {
                var dataSize = 0
                try autoreleasepool {
                    let dataChunk = inputFile.readData(ofLength: chunkSize)
                    let encryptedChunk = try crypter.encryptUpdate(dataChunk: dataChunk)

                    dataSize = dataChunk.count
                    outputFile.write(encryptedChunk)
                }

                if dataSize < chunkSize {
                    break
                }
            }

            let (encryptedChunk, key, sha256Hash) = try crypter.encryptFinalize()
            outputFile.write(encryptedChunk)

            DDLogDebug("ImageServer/encrypt/finished  Duration: \(-ts.timeIntervalSinceNow) s")
            return .success((key.base64EncodedString(), sha256Hash.base64EncodedString()))
        } catch {
            DDLogError("ImageServer/encrypt/error url=[\(input)] [\(error)]")
            return .failure(error)
        }
    }

    private func encryptChunkedMedia(_ type: CommonMediaType, input: URL, output: URL) -> Result<(key: String, sha256: String, chunkSize: Int32, blobSize: Int64), Error> {
        guard let plaintextResource = try? input.resourceValues(forKeys: [.fileSizeKey]),
              let plaintextSize = plaintextResource.fileSize else {
            DDLogError("ImageServer/encryptChunkedMedia/media/error  Could not read file size")
            return .failure(MediaProcessingError.failedToReadSize)
        }
        DDLogInfo("ImageServer/encryptChunkedMedia/media/ready  New media file size: [\(plaintextSize)]")

        let chunkedParameters: ChunkedMediaParameters
        do {
            chunkedParameters = try ChunkedMediaParameters(plaintextSize: Int64(plaintextSize), chunkSize: Int32(ServerProperties.streamingUploadChunkSize))
        } catch {
            DDLogError("ImageServer/encryptChunkedMedia/media/error  Error while computing chunk parameters")
            return .failure(error)
        }

        DDLogInfo("ImageServer/encryptChunkedMedia/media/file name=[\(output.absoluteString)]")
        do {
            if FileManager.default.fileExists(atPath: output.path) {
                // if the file already exists - delete and decrypt the whole file again!
                DDLogError("ImageServer/encryptChunkedMedia/media/file/duplicate exists")
                try FileManager.default.removeItem(at: output)
                DDLogError("ImageServer/encryptChunkedMedia/media/file/duplicate delete [\(output)]")
            }
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: nil)
            DDLogInfo("ImageServer/encryptChunkedMedia/media/file/create: [\(output)]")
        } catch {
            DDLogError("ImageServer/encryptChunkedMedia/media/file/error: failed to create file: [\(error)]")
            return .failure(error)
        }

        guard let plaintextFileHandle = try? FileHandle(forReadingFrom: input) else {
            DDLogError("ImageServer/encryptChunkedMedia/media/error  Could not open input file")
            return .failure(MediaProcessingError.failedToOpenFile)
        }
        defer {
            plaintextFileHandle.closeFile()
        }
        guard let encryptedFileHandle = try? FileHandle(forWritingTo: output) else {
            DDLogError("ImageServer/encryptChunkedMedia/media/error  Could not open output file")
            return .failure(MediaProcessingError.failedToOpenFile)
        }
        defer {
            encryptedFileHandle.closeFile()
        }

        DDLogDebug("ImageServer/encryptChunkedMedia/encrypt/begin")
        let ts = Date()
        let encryptionResult: ChunkedMediaCrypter.EncryptionResult
        var fileSize: UInt64 = 0
        do {
            encryptionResult = try ChunkedMediaCrypter.encryptChunkedMedia(
                mediaType: type,
                chunkedParameters: chunkedParameters,
                readChunkData: { _, chunkSize in plaintextFileHandle.readData(ofLength: chunkSize) },
                writeChunkData: { chunkData, _ in encryptedFileHandle.write(chunkData) })
            fileSize = encryptedFileHandle.offsetInFile
        } catch {
            DDLogError("ImageServer/encryptChunkedMedia/encrypt/error url=[\(input.description)] [\(error)]")
            return .failure(error)
        }

        DDLogDebug("ImageServer/encryptChunkedMedia/encrypt/finished  File size: \(fileSize) bytes  Duration: \(-ts.timeIntervalSinceNow) s")
        return .success((encryptionResult.mediaKey.base64EncodedString(),
                         encryptionResult.sha256.base64EncodedString(),
                         chunkedParameters.chunkSize,
                         chunkedParameters.blobSize))
    }

    private func process(image url: URL, completion: @escaping (Result<(URL, CGSize), Error>) -> Void) {
        completion(autoreleasepool {
            self.resize(image: url).flatMap(self.save(image:))
        })
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
        let videoFile = try FileHandle(forUpdating: url)
        defer { try? videoFile.close() }

        // atom types
        guard let moov = "moov".data(using: .ascii) else { return }
        guard let mvhd = "mvhd".data(using: .ascii) else { return }
        guard let tkhd = "tkhd".data(using: .ascii) else { return }
        guard let mdhd = "mdhd".data(using: .ascii) else { return }

        // Find the moov atom
        try videoFile.seek(toOffset: 0)
        guard var moovIdx = find(atom: moov, in: videoFile) else { return }
        moovIdx -= 4

        try videoFile.seek(toOffset: UInt64(moovIdx))
        let moovSizeData = videoFile.readData(ofLength: 4)
        let moovSize = Int(moovSizeData.withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) })

        try videoFile.seek(toOffset: UInt64(moovIdx))
        let moovData = videoFile.readData(ofLength: moovSize)

        try clearTimestamps(for: mvhd, from: moovData, at: moovIdx, in: videoFile)
        try clearTimestamps(for: tkhd, from: moovData, at: moovIdx, in: videoFile)
        try clearTimestamps(for: mdhd, from: moovData, at: moovIdx, in: videoFile)
    }

    private func find(atom: Data, in file: FileHandle) -> Int? {
        var atomIdx: Int?
        var offset = 0
        var previousChunkSuffix = Data()

        while true {
            var dataSize = 0

            autoreleasepool {
                let previousSize = previousChunkSuffix.count

                let dataChunk = file.readData(ofLength: chunkSize)
                previousChunkSuffix.append(dataChunk)

                if let idx = previousChunkSuffix.firstRange(of: atom)?.lowerBound {
                    atomIdx = offset + idx - previousSize
                    return
                }

                dataSize = dataChunk.count
                previousChunkSuffix.removeAll()
                previousChunkSuffix = dataChunk.suffix(atom.count)
            }

            if dataSize < chunkSize || atomIdx != nil {
                break
            }

            offset += dataSize
        }

        return atomIdx
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
            if FileManager.default.fileExists(atPath: originalMediaFileURL.absoluteString) {
                try FileManager.default.removeItem(at: originalMediaFileURL)    // xxx.jpg
                DDLogDebug("ImageServer/cleanUpUploadData/success: \(originalMediaFileURL)")
            }
        } catch {
            DDLogError("ImageServer/cleanUpUploadData/error [\(error)]")
        }
        do {
            if FileManager.default.fileExists(atPath: originalMediaFileURL.absoluteString) {
                try FileManager.default.removeItem(at: encryptedMediaFileURL)   // xxx.processed.jpg.enc
                DDLogDebug("ImageServer/cleanUpUploadData/success: \(encryptedMediaFileURL)")
            }
        } catch {
            DDLogError("ImageServer/cleanUpUploadData/error [\(error)]")
        }
    }
}
