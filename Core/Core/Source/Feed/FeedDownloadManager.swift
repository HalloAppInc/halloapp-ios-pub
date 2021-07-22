//
//  FeedDownloadManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjackSwift
import Combine
import CoreData
import Foundation

public protocol FeedDownloadManagerDelegate: AnyObject {
    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task)
}

public class FeedDownloadManager {

    public class Task: Identifiable, Hashable, Equatable {
        public let id: String

        // Input parameters.
        var mediaData: FeedMediaData
        public var feedMediaObjectId: NSManagedObjectID?

        // Output parameters.
        public let downloadProgress = CurrentValueSubject<Float, Never>(0)
        public weak var downloadRequest: Alamofire.DownloadRequest?
        public fileprivate(set) var completed = false
        public var error: Error?
        fileprivate var encryptedFilePath: String?
        public var decryptedFilePath: String?
        public var fileSize: Int?

        fileprivate var filename: String {
            get {
                return "\(id).\(FeedDownloadManager.fileExtension(forMediaType: mediaData.type))"
            }
        }

        public init(media: FeedMediaProtocol) {
            self.id = Self.taskId(for: media)
            self.mediaData = FeedMediaData(
                id: media.id,
                url: media.url,
                type: media.type,
                size: media.size,
                key: media.key,
                sha256: media.sha256)
        }

        public static func == (lhs: Task, rhs: Task) -> Bool {
            return lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.id)
        }

        public class func taskId(for media: FeedMediaProtocol) -> String {
            return media.id
        }
    }

    weak public var delegate: FeedDownloadManagerDelegate!
    private let mediaDirectoryURL: URL

    public init(mediaDirectoryURL: URL) {
        self.mediaDirectoryURL = mediaDirectoryURL
    }
    
    private let decryptionQueue = DispatchQueue(label: "com.halloapp.downloadmanager", qos: .userInitiated, attributes: [ .concurrent ])

    // MARK: Scheduling

    private var tasks: Set<Task> = []

    /**
     - returns:
     True if download task was scheduled.
     */
    public func downloadMedia(for feedPostMedia: FeedMediaProtocol) -> (Bool, Task) {
        assert(delegate != nil, "Must set delegate before starting any task.")
        if let existingTask = currentTask(for: feedPostMedia) {
            DDLogWarn("FeedDownloadManager/\(existingTask.id)/warning Already downloading")
            return (false, existingTask)
        }
        let task = Task(media: feedPostMedia)
        let taskAdded = self.addTask(task)
        return (taskAdded, task)
    }

    @discardableResult private func addTask(_ task: Task) -> Bool {
        guard let downloadURL = task.mediaData.url else {
            DDLogError("FeedDownloadManager/\(task.id)/missing-url")
            return false
        }
        guard !self.tasks.contains(task) else {
            DDLogError("FeedDownloadManager/\(task.id)/duplicate [\(downloadURL)]")
            return false
        }
        DDLogDebug("FeedDownloadManager/\(task.id)/download/start [\(downloadURL)]")
        let fileURL = self.fileURL(forMediaFilename: task.filename).appendingPathExtension("enc")
        let destination: DownloadRequest.Destination = { _, _ in
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        // Resume from existing partial data if possible
        let request: Alamofire.DownloadRequest = {
            if let resumeData = try? Data(contentsOf: resumeDataFileURL(forMediaFilename: task.filename)) {
                DDLogInfo("FeedDownloadManager/\(task.id)/resuming")
                return AF.download(resumingWith: resumeData, to: destination)
            } else {
                DDLogInfo("FeedDownloadManager/\(task.id)/initiating")
                return AF.download(downloadURL, to: destination)
            }
        }()

        // TODO: move reponse handler off the main thread.

        request.downloadProgress { (progress) in
                DDLogDebug("FeedDownloadManager/\(task.id)/download/progress [\(progress.fractionCompleted)]")
                task.fileSize = Int(progress.totalUnitCount)
                task.downloadProgress.send(Float(progress.fractionCompleted))
            }
            .responseURL { (afDownloadResponse) in
                task.downloadProgress.send(completion: .finished)
                task.downloadRequest = nil

                if afDownloadResponse.error == nil, let httpURLResponse = afDownloadResponse.response {
                    DDLogDebug("FeedDownloadManager/\(task.id)/download/finished [\(afDownloadResponse.response!)]")
                    if httpURLResponse.statusCode == 200 || httpURLResponse.statusCode == 206, let fileURL = afDownloadResponse.fileURL {
                        task.encryptedFilePath = self.relativePath(from: fileURL)
                        self.cleanUpResumeData(for: task)
                        self.decryptionQueue.async {
                            self.decryptDataInChunks(for: task)
                        }
                    } else {
                        task.error = NSError(domain: "com.halloapp.downloadmanager", code: httpURLResponse.statusCode, userInfo: nil)
                        self.taskFailed(task)
                    }
                } else {
                    DDLogDebug("FeedDownloadManager/\(task.id)/download/error [\(String(describing: afDownloadResponse.error))]")
                    if let underlyingError = afDownloadResponse.error?.underlyingError,
                       let resumeData = (underlyingError as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                    {
                        self.saveResumeData(resumeData, for: task)
                    }
                    task.error = afDownloadResponse.error
                    self.taskFailed(task)
                }
        }
        task.downloadRequest = request
        self.tasks.insert(task)
        return true
    }

    public func currentTask(for media: FeedMediaProtocol) -> Task? {
        let taskId = Task.taskId(for: media)
        return self.tasks.first(where: { $0.id == taskId })
    }

    // MARK: Suspend downloads and keep track of mediaObjectIds

    public var suspendedMediaObjectIds: Set<NSManagedObjectID> = []

    public func suspendMediaDownloads() {
        for task in tasks {
            guard let request = task.downloadRequest else { continue }
            request.cancel() { resumeData in
                if let resumeData = resumeData {
                    self.saveResumeData(resumeData, for: task)
                }
            }
            if let mediaObjectId = task.feedMediaObjectId {
                suspendedMediaObjectIds.insert(mediaObjectId)
            }
        }
    }

    private func saveResumeData(_ resumeData: Data, for task: Task) {
        do {
            let fileURL = self.resumeDataFileURL(forMediaFilename: task.filename)
            try FileManager.default.createDirectory(
                atPath: fileURL.deletingLastPathComponent().path,
                withIntermediateDirectories: true,
                attributes: nil)
            try resumeData.write(to: fileURL)
            DDLogInfo("FeedDownloadManager/\(task.id)/saveResumeData saved to \(fileURL)")
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/saveResumeData/error \(error)")
        }
    }

    private func cleanUpResumeData(for task: Task) {
        let resumeDataFileURL = self.resumeDataFileURL(forMediaFilename: task.filename)
        guard FileManager.default.fileExists(atPath: resumeDataFileURL.path) else {
            DDLogInfo("FeedDownloadManager/\(task.id)/cleanUpResumeData unnecessary")
            return
        }
        do {
            try FileManager.default.removeItem(at: resumeDataFileURL)
            DDLogInfo("FeedDownloadManager/\(task.id)/cleanUpResumeData success")
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/cleanUpResumeData/error \(error)")
        }
    }

    // MARK: Decryption in chunks

    private func decryptDataInChunks(for task: Task) {
        /*
         First we create an object of MediaChunkCrypter and initialize it with all the keys and hash of the whole file.
         Then, we read the encrypted file chunk by chunk and calculate the sha256 of the entire file.
         At the same time, we try and calculate the hmac-sha256 signature on the file using the symmetric key.
         To avoid multiple reads of the file here - we do an iteration of the file and keep track of the last chunk and the current chunk.
         We always send the current chunk to do streaming hash computation and send the previous chunk to do streaming hmac computation.
         If the current chunk is less than the requested size - this indicates that the file has ended.
         For hash computation: - it is simple - just send in the last chunk and then verify. if this fails - return.
         For hmac computation:
            - we now observe both last chunk and current chunk and drop the last 32 bytes to get the mac
            - we send in the remaining data to do stream hmac computation and compare it against the attached mac.
            - now verify this signature. if this fails - return
         To decrypt file:
            - Only after verifying both the hash and hmac we now read the file again to do streaming decryption.
            - we decrypt the file in chunks and the decrypted chunks are also written to file after that.
            - after writing all the chunks to the file, we then close and log success and return.
         // FileHandle.readData has some issue with releasing memory when calling repeatedly inside a loop.
         // reference: https://forums.swift.org/t/why-is-this-apparently-leaking-memory/34612
         */
        guard let encryptedFilePath = task.encryptedFilePath else {
            self.taskFailed(task)
            return
        }

        let ts = Date()

        // Fetch keys
        guard let mediaKey = Data(base64Encoded: task.mediaData.key), let sha256Hash = Data(base64Encoded: task.mediaData.sha256) else {
            DDLogError("FeedDownloadManager/\(task.id)/load/error Invalid key or hash.")
            task.error = NSError(domain: "com.halloapp.downloadmanager", code: 1, userInfo: nil)
            self.taskFailed(task)
            return
        }

        let chunkSize = 512 * 1024 // 0.5MB
        let attachedMacLength = 32
        var prevEncryptedDataChunk: Data
        var curEncryptedDataChunk: Data
        let mediaChunkCrypter: MediaChunkCrypter
        let encryptedFileURL = fileURL(forRelativeFilePath: encryptedFilePath)
        let encryptedFileHandle: FileHandle
        var fileSize: Int = 0
        do {
            mediaChunkCrypter  = try MediaChunkCrypter.init(mediaKey: mediaKey, sha256hash: sha256Hash, mediaType: task.mediaData.type)
            DDLogError("FeedDownloadManager/\(task.id)/init/MediaChunkCrypter duration: \(-ts.timeIntervalSinceNow) s]")
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/load/error Failed to create chunkCrypter: [\(error)]")
            task.error = error
            self.taskFailed(task)
            return
        }

        do {
            // see comments under the function signature for more details about the logic below.
            encryptedFileHandle  = try FileHandle(forReadingFrom: encryptedFileURL)

            prevEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)
            fileSize += prevEncryptedDataChunk.count
            try mediaChunkCrypter.hashUpdate(input: prevEncryptedDataChunk)
            curEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)
            fileSize += curEncryptedDataChunk.count

            while (curEncryptedDataChunk.count == chunkSize) {
                try mediaChunkCrypter.hashUpdate(input: curEncryptedDataChunk)
                try mediaChunkCrypter.hmacUpdate(input: prevEncryptedDataChunk)
                autoreleasepool {
                    prevEncryptedDataChunk = curEncryptedDataChunk
                    curEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)
                }
                fileSize += curEncryptedDataChunk.count
            }
            DDLogInfo("FeedDownloadManager/\(task.id)/verifyHash/wip fileSize=[\(fileSize)]")

            // Verify hash-sha256 here and only then proceed.
            try mediaChunkCrypter.hashUpdate(input: curEncryptedDataChunk)
            try mediaChunkCrypter.hashFinalizeAndVerify()

            // Verify hmac-sha256 signature here and only then proceed
            if (curEncryptedDataChunk.count > attachedMacLength) {
                let attachedMAC = curEncryptedDataChunk.suffix(attachedMacLength)
                let remainingEncryptedChunk = curEncryptedDataChunk.dropLast(attachedMacLength)
                try mediaChunkCrypter.hmacUpdate(input: prevEncryptedDataChunk)
                try mediaChunkCrypter.hmacUpdate(input: remainingEncryptedChunk)
                try mediaChunkCrypter.hmacFinalizeAndVerify(attachedMAC: attachedMAC)
            } else if (curEncryptedDataChunk.count == attachedMacLength) {
                try mediaChunkCrypter.hmacUpdate(input: prevEncryptedDataChunk)
                try mediaChunkCrypter.hmacFinalizeAndVerify(attachedMAC: curEncryptedDataChunk)
            } else {
                let prevPartMACLength = attachedMacLength - curEncryptedDataChunk.count
                var attachedMAC = prevEncryptedDataChunk.suffix(prevPartMACLength)
                let remainingEncryptedChunk = prevEncryptedDataChunk.dropLast(prevPartMACLength)
                attachedMAC.append(curEncryptedDataChunk)
                try mediaChunkCrypter.hmacUpdate(input: remainingEncryptedChunk)
                try mediaChunkCrypter.hmacFinalizeAndVerify(attachedMAC: attachedMAC)
            }

            DDLogInfo("FeedDownloadManager/\(task.id)/verifyHash/success full-fileSize=[\(fileSize)] duration: \(-ts.timeIntervalSinceNow) s]")
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/verifyHash/error Failed to verify hash: [\(error)]")
            task.error = error
            self.taskFailed(task)
            return
        }

        let decryptedFileURL = encryptedFileURL.deletingPathExtension()
        DDLogInfo("FeedDownloadManager/\(task.id)/createFile/name=[\(decryptedFileURL.absoluteString)]")
        do {
            if FileManager.default.fileExists(atPath: decryptedFileURL.path) {
                // if the file already exists - delete and decrypt the whole file again!
                DDLogError("FeedDownloadManager/\(task.id)/exists/duplicate-file exists")
                try FileManager.default.removeItem(at: decryptedFileURL)
                DDLogError("FeedDownloadManager/\(task.id)/delete/file [\(decryptedFileURL)]")
            }
            try FileManager.default.createDirectory(at: decryptedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            FileManager.default.createFile(atPath: decryptedFileURL.path, contents: nil, attributes: nil)
            DDLogInfo("FeedDownloadManager/\(task.id)/create/file: [\(decryptedFileURL)]")
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/createFile/failed: failed to create file: [\(error)]")
            task.error = error
            self.taskFailed(task)
            return
        }

        // TODO(murali@): this is duplicated logic - similar loop as above when reading the file.
        var decryptedDataChunk: Data
        do {
            // Seek to beginning to start decryption
            try encryptedFileHandle.seek(toOffset: 0)
            try mediaChunkCrypter.decryptInit()
            let decryptedFileHandle = try FileHandle(forWritingTo: decryptedFileURL)

            prevEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)
            curEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)

            while (curEncryptedDataChunk.count == chunkSize) {
                decryptedDataChunk = try mediaChunkCrypter.decryptUpdate(dataChunk: prevEncryptedDataChunk)
                autoreleasepool {
                    prevEncryptedDataChunk = curEncryptedDataChunk
                    curEncryptedDataChunk = encryptedFileHandle.readData(ofLength: chunkSize)
                }
                decryptedFileHandle.write(decryptedDataChunk)
            }

            if (curEncryptedDataChunk.count > attachedMacLength) {
                let remainingEncryptedChunk = curEncryptedDataChunk.dropLast(attachedMacLength)
                decryptedDataChunk = try mediaChunkCrypter.decryptUpdate(dataChunk: prevEncryptedDataChunk)
                decryptedFileHandle.write(decryptedDataChunk)
                decryptedDataChunk = try mediaChunkCrypter.decryptUpdate(dataChunk: remainingEncryptedChunk)
                decryptedFileHandle.write(decryptedDataChunk)
            } else if (curEncryptedDataChunk.count == attachedMacLength) {
                decryptedDataChunk = try mediaChunkCrypter.decryptUpdate(dataChunk: prevEncryptedDataChunk)
                decryptedFileHandle.write(decryptedDataChunk)
            } else {
                let prevPartMACLength = attachedMacLength - curEncryptedDataChunk.count
                let remainingEncryptedChunk = prevEncryptedDataChunk.dropLast(prevPartMACLength)
                decryptedDataChunk = try mediaChunkCrypter.decryptUpdate(dataChunk: remainingEncryptedChunk)
                decryptedFileHandle.write(decryptedDataChunk)
            }

            decryptedDataChunk = try mediaChunkCrypter.decryptFinalize()
            decryptedFileHandle.write(decryptedDataChunk)
            decryptedFileHandle.closeFile()

            DDLogInfo("FeedDownloadManager/\(task.id)/decrypt/successful: full-fileSize=[\(fileSize)] duration: \(-ts.timeIntervalSinceNow) s")
        } catch {
            task.error = error
            DDLogError("FeedDownloadManager/\(task.id)/decrypt/failed [\(error)]")
            self.taskFailed(task)
            return
        }

        DDLogInfo("FeedDownloadManager/\(task.id)/decrypt/finished full-fileSize=[\(fileSize)] duration: \(-ts.timeIntervalSinceNow) s")
        // Delete encrypted file
        do {
            try FileManager.default.removeItem(at: encryptedFileURL)
        }
        catch {
            DDLogError("FeedDownloadManager/\(task.id)/delete-encrypted/error [\(error)]")
        }
        task.decryptedFilePath = relativePath(from: decryptedFileURL)

        self.taskFinished(task)

    }

    private func taskFinished(_ task: Task) {
        task.completed = true
        DispatchQueue.main.async {
            self.tasks.remove(task)
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    private func taskFailed(_ task: Task) {
        assert(task.decryptedFilePath == nil, "Failing task that has completed download.")
        task.completed = true
        if task.encryptedFilePath != nil {
            do {
                try FileManager.default.removeItem(at: fileURL(forRelativeFilePath: task.encryptedFilePath!))
            }
            catch {
                DDLogDebug("FeedDownloadManager/\(task.id)/delete-encrypted/error [\(error)]")
            }
        }
        DispatchQueue.main.async {
            self.tasks.remove(task)
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    // MARK: File management

    public class func fileExtension(forMediaType mediaType: FeedMediaType) -> String {
        switch mediaType {
        case .image:
            return "jpg"
        case .video:
            return "mp4"
        case .audio:
            return "aac"
        }
    }

    public func fileURL(forMediaFilename mediaFilename: String) -> URL {
        var first: String?, second: String?
        for ch in mediaFilename.unicodeScalars {
            guard CharacterSet.alphanumerics.contains(ch) else { continue }
            if first == nil {
                first = String(ch).uppercased()
                continue
            }
            if second == nil {
                second = String(ch).uppercased()
                break
            }
        }
        return mediaDirectoryURL
                .appendingPathComponent(first!, isDirectory: true)
                .appendingPathComponent(second!, isDirectory: true)
                .appendingPathComponent(mediaFilename, isDirectory: false)
    }

    public func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return mediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    public func relativePath(from fileURL: URL) -> String? {
        let fullPath = fileURL.path
        let mediaDirectoryPath = mediaDirectoryURL.path
        if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
            return String(fullPath.suffix(from: range.upperBound))
        }
        return nil
    }

    private func resumeDataFileURL(forMediaFilename mediaFilename: String) -> URL {
        return fileURL(forMediaFilename: mediaFilename).appendingPathExtension("partial")
    }

}
