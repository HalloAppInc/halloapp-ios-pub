//
//  FeedDownloadManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import CoreData
import Foundation

public protocol FeedDownloadManagerDelegate: AnyObject {

    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task)
}

public class FeedDownloadManager {

    public class Task: Identifiable, Hashable, Equatable {
        public let id: String

        // Input parameters.
        let downloadURL: URL
        public var feedMediaObjectId: NSManagedObjectID?

        // These are required for decrypting.
        let mediaType: FeedMediaType
        let key: String
        let sha256: String

        // Output parameters.
        public fileprivate(set) var completed = false
        public var error: Error?
        fileprivate var encryptedFilePath: String?
        public var decryptedFilePath: String?

        fileprivate var filename: String {
            get {
                return "\(id).\(FeedDownloadManager.fileExtension(forMediaType: mediaType))"
            }
        }

        public init(id: String, downloadURL: URL, mediaType: FeedMediaType, key: String, sha256: String) {
            self.id = id
            self.downloadURL = downloadURL
            self.mediaType = mediaType
            self.key = key
            self.sha256 = sha256
        }

        public convenience init(media: FeedMediaProtocol) {
            self.init(id: UUID().uuidString, downloadURL: media.url, mediaType: media.type, key: media.key, sha256: media.sha256)
        }

        public static func == (lhs: Task, rhs: Task) -> Bool {
            return lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.id)
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
        let task = Task(media: feedPostMedia)
        let taskAdded = self.addTask(task)
        return (taskAdded, task)
    }

    @discardableResult private func addTask(_ task: Task) -> Bool {
        guard !self.tasks.contains(task) else {
            DDLogError("FeedDownloadManager/\(task.id)/duplicate [\(task.downloadURL)]")
            return false
        }
        DDLogDebug("FeedDownloadManager/\(task.id)/download/start [\(task.downloadURL)]")
        let fileURL = self.fileURL(forMediaFilename: task.filename).appendingPathExtension("enc")
        let destination: DownloadRequest.Destination = { _, _ in
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        // TODO: move reponse handler off the main thread.
        AF.download(task.downloadURL, to: destination).responseData { (afDownloadResponse) in
            if afDownloadResponse.error == nil, let httpURLResponse = afDownloadResponse.response {
                DDLogDebug("FeedDownloadManager/\(task.id)/download/finished [\(afDownloadResponse.response!)]")
                if httpURLResponse.statusCode == 200, let fileURL = afDownloadResponse.fileURL {
                    task.encryptedFilePath = self.relativePath(from: fileURL)
                    self.decryptionQueue.async {
                        self.decryptData(for: task)
                    }
                } else {
                    task.error = NSError(domain: "com.halloapp.downloadmanager", code: httpURLResponse.statusCode, userInfo: nil)
                    self.taskFailed(task)
                }
            } else {
                DDLogDebug("FeedDownloadManager/\(task.id)/download/error [\(String(describing: afDownloadResponse.error))]")
                task.error = afDownloadResponse.error
                self.taskFailed(task)
            }
        }
        self.tasks.insert(task)
        return true
    }

    // MARK: Decryption

    private func decryptData(for task: Task) {
        guard task.encryptedFilePath != nil else {
            self.taskFailed(task)
            return
        }

        // Load data
        // TODO: decrypt without loading contents of the entire file into memory.
        let encryptedFileURL = fileURL(forRelativeFilePath: task.encryptedFilePath!)
        DDLogDebug("FeedDownloadManager/\(task.id)/load-data [\(encryptedFileURL)]")
        var encryptedData: Data
        do {
            encryptedData = try Data(contentsOf: encryptedFileURL)
        } catch {
            task.error = error
            DDLogError("FeedDownloadManager/\(task.id)/load/error [\(error)]")
            self.taskFailed(task)
            return
        }

        // Decrypt data
        guard let mediaKey = Data(base64Encoded: task.key), let sha256Hash = Data(base64Encoded: task.sha256) else {
            DDLogError("FeedDownloadManager/\(task.id)/load/error Invalid key or hash.")
            task.error = NSError(domain: "com.halloapp.downloadmanager", code: 1, userInfo: nil)
            self.taskFailed(task)
            return
        }

        let ts = Date()
        DDLogDebug("FeedDownloadManager/\(task.id)/decrypt/begin size=[\(encryptedData.count)]")
        let decryptedData: Data
        do {
            decryptedData = try MediaCrypter.decrypt(data: encryptedData, mediaKey: mediaKey, sha256hash: sha256Hash, mediaType: task.mediaType)
        } catch {
            DDLogError("FeedDownloadManager/\(task.id)/decrypt/error [\(error)]")
            task.error = error
            self.taskFailed(task)
            return
        }
        DDLogInfo("FeedDownloadManager/\(task.id)/decrypt/finished size=[\(decryptedData.count)] duration: \(-ts.timeIntervalSinceNow) s")

        // Write unencrypted data to file
        let decryptedFileURL = encryptedFileURL.deletingPathExtension()
        DDLogDebug("FeedDownloadManager/\(task.id)/save to [\(decryptedFileURL.absoluteString)]")
        do {
            try decryptedData.write(to: decryptedFileURL)
        }
        catch {
            task.error = error
            DDLogError("FeedDownloadManager/\(task.id)/save/failed [\(error)]")
            self.taskFailed(task)
            return
        }

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

}
