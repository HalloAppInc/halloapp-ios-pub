//
//  FeedDownloadManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Core
import CoreData
import Foundation

protocol FeedDownloadManagerDelegate: AnyObject {
    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task)
}

class FeedDownloadManager {
    class Task: Identifiable, Hashable, Equatable {
        let id: String

        // Input parameters.
        let downloadURL: URL
        let feedMediaObjectId: NSManagedObjectID

        // These are required for decrypting.
        let mediaType: FeedMediaType
        let key: String
        let sha256: String

        // Output parameters.
        var error: Error?
        var relativeFilePath: String?

        fileprivate var filename: String

        init(_ feedMedia: FeedPostMedia) {
            self.id = "\(feedMedia.post.id)-\(feedMedia.order)"
            self.downloadURL = feedMedia.url
            self.feedMediaObjectId = feedMedia.objectID
            self.mediaType = feedMedia.type
            self.key = feedMedia.key
            self.sha256 = feedMedia.sha256

            self.filename = Task.filename(for: feedMedia)
        }

        class func filename(for feedMedia: FeedPostMedia) -> String {
            let fileExtension: String = {
                switch feedMedia.type {
                case .image:
                    return "jpg"
                case .video:
                    return "mp4"
                }
            }()
            return "\(feedMedia.post.id)-\(feedMedia.order).\(fileExtension)"
        }

        var fileURL: URL? {
            get {
                guard self.relativeFilePath != nil else { return nil }
                return MainAppContext.mediaDirectoryURL.appendingPathComponent(self.relativeFilePath!, isDirectory: false)
            }
            set {
                if newValue == nil {
                    self.relativeFilePath = nil
                } else {
                    self.relativeFilePath = FeedDownloadManager.relativePath(from: newValue!)
                }
            }
        }

        static func == (lhs: Task, rhs: Task) -> Bool {
            return lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.id)
        }
    }

    weak var delegate: FeedDownloadManagerDelegate?
    
    private let decryptionQueue = DispatchQueue(label: "com.halloapp.downloadmanager", qos: .userInitiated, attributes: [ .concurrent ])

    // MARK: Singleton

    private static let sharedManager = FeedDownloadManager()

    class var shared: FeedDownloadManager {
        get {
            return sharedManager
        }
    }

    // MARK: Scheduling

    private var tasks: Set<Task> = []

    /**
     - returns:
     True if download task was scheduled.
     */
    @discardableResult func downloadMedia(for feedPostMedia: FeedPostMedia) -> Bool {
        return self.addTask(Task(feedPostMedia))
    }

    @discardableResult private func addTask(_ task: Task) -> Bool {
        guard !self.tasks.contains(task) else {
            DDLogError("FeedDownloadManager/\(task.id)/duplicate [\(task.downloadURL)]")
            return false
        }
        DDLogDebug("FeedDownloadManager/\(task.id)/download/start [\(task.downloadURL)]")
        let fileURL = FeedDownloadManager.self.fileURL(for: task.filename).appendingPathExtension("enc")
        let destination: DownloadRequest.Destination = { _, _ in
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        // TODO: move reponse handler off the main thread.
        AF.download(task.downloadURL, to: destination).responseData { (afDownloadResponse) in
            if afDownloadResponse.error == nil, let httpURLResponse = afDownloadResponse.response {
                DDLogDebug("FeedDownloadManager/\(task.id)/download/finished [\(afDownloadResponse.response!)]")
                if httpURLResponse.statusCode == 200, let fileURL = afDownloadResponse.fileURL {
                    task.fileURL = fileURL
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
        guard task.fileURL != nil else {
            self.taskFailed(task)
            return
        }

        // Load data
        // TODO: decrypt without loading contents of the entire file into memory.
        DDLogDebug("FeedDownloadManager/\(task.id)/load-data [\(task.fileURL!)]")
        var encryptedData: Data
        do {
            encryptedData = try Data(contentsOf: task.fileURL!)
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
        let fileURL = task.fileURL!.deletingPathExtension()
        DDLogDebug("FeedDownloadManager/\(task.id)/save to [\(fileURL.absoluteString)]")
        do {
            try decryptedData.write(to: fileURL)
        }
        catch {
            task.error = error
            DDLogError("FeedDownloadManager/\(task.id)/save/failed [\(error)]")
            self.taskFailed(task)
            return
        }

        // Delete encrypted file
        do {
            try FileManager.default.removeItem(at: task.fileURL!)
        }
        catch {
            DDLogError("FeedDownloadManager/\(task.id)/delete-encrypted/error [\(error)]")
        }
        task.fileURL = fileURL

        self.taskFinished(task)
    }

    private func taskFinished(_ task: Task) {
        DispatchQueue.main.async {
            self.tasks.remove(task)
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    private func taskFailed(_ task: Task) {
        if task.fileURL != nil {
            do {
                try FileManager.default.removeItem(at: task.fileURL!)
            }
            catch {
                DDLogDebug("FeedDownloadManager/\(task.id)/delete-encrypted/error [\(error)]")
            }
            task.fileURL = nil
        }
        DispatchQueue.main.async {
            self.tasks.remove(task)
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    // MARK: File management

    private class func fileURL(for mediaFilename: String) -> URL {
        var first: String?, second: String?
        for ch in mediaFilename.unicodeScalars {
            guard CharacterSet.alphanumerics.contains(ch) else { continue }
            if first == nil {
                first = String(ch)
                continue
            }
            if second == nil {
                second = String(ch)
                break
            }
        }
        return MainAppContext.mediaDirectoryURL
                .appendingPathComponent(first!, isDirectory: true)
                .appendingPathComponent(second!, isDirectory: true)
                .appendingPathComponent(mediaFilename, isDirectory: false)
    }

    private class func relativePath(from fileURL: URL) -> String? {
        let fullPath = fileURL.path
        let mediaDirectoryPath = MainAppContext.mediaDirectoryURL.path
        if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
            return String(fullPath.suffix(from: range.upperBound))
        }
        return nil
    }

    func copyMedia(from pendingMedia: PendingMedia, to feedPostMedia: FeedPostMedia) throws {
        assert(pendingMedia.fileURL != nil)
        let fileURL = FeedDownloadManager.fileURL(for: Task.filename(for: feedPostMedia))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: pendingMedia.fileURL!, to: fileURL)
        feedPostMedia.relativeFilePath = FeedDownloadManager.relativePath(from: fileURL)
    }
}
