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
        let mediaType: FeedPostMedia.MediaType
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

            let fileExtension: String = {
                switch feedMedia.type {
                case .image:
                    return "jpg"
                case .video:
                    return "mp4"
                }
            }()
            self.filename = "\(id).\(fileExtension)"
        }

        var fileURL: URL? {
            get {
                guard self.relativeFilePath != nil else { return nil }
                return AppContext.mediaDirectoryURL.appendingPathComponent(self.relativeFilePath!, isDirectory: false)
            }
            set {
                if newValue == nil {
                    self.relativeFilePath = nil
                } else {
                    let fullPath = newValue!.path
                    let mediaDirectoryPath = AppContext.mediaDirectoryURL.path
                    if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
                        self.relativeFilePath = String(fullPath.suffix(from: range.upperBound))
                    } else {
                        self.relativeFilePath = nil
                    }
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
    private let decryptionQueue = DispatchQueue(label: "com.halloapp.downloadmanager")

    // MARK: Singleton

    private static let sharedManager = FeedDownloadManager()

    class var shared: FeedDownloadManager {
        get {
            return sharedManager
        }
    }

    // MARK: Scheduling

    private var tasks: Set<Task> = []

    func downloadMedia(for feedPostMedia: FeedPostMedia) {
        self.addTask(Task(feedPostMedia))
    }

    private func addTask(_ task: Task) {
        guard !self.tasks.contains(task) else {
            DDLogError("FeedDownloadManager/\(task.id)/duplicate [\(task.downloadURL)]")
            return
        }
        DDLogDebug("FeedDownloadManager/\(task.id)/download/start [\(task.downloadURL)]")
        let fileURL = self.fileURL(for: task).appendingPathExtension("enc")
        let destination: DownloadRequest.DownloadFileDestination = { _, _ in
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        Alamofire.download(task.downloadURL, to: destination)
            .response { response in
                if let httpResponse = response.response {
                    DDLogDebug("FeedDownloadManager/\(task.id)/download/finished [\(httpResponse)]")
                    task.fileURL = response.destinationURL
                    if httpResponse.statusCode == 200 {
                        self.decryptionQueue.async {
                            self.decryptData(for: task)
                        }
                    } else {
                        task.error = NSError(domain: "com.halloapp.downloadmanager", code: httpResponse.statusCode, userInfo: nil)
                        self.taskFailed(task)
                    }
                } else {
                    DDLogDebug("FeedDownloadManager/\(task.id)/download/error [\(String(describing: response.error))]")
                    task.error = response.error
                    self.taskFailed(task)
                }
        }
        self.tasks.insert(task)
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
        let ts = Date()
        DDLogDebug("FeedDownloadManager/\(task.id)/decrypt/begin size=[\(encryptedData.count)]")
        guard let decryptedData = HAC.decrypt(data: encryptedData, key: task.key, sha256hash: task.sha256, mediaType: task.mediaType) else {
            DDLogError("FeedDownloadManager/\(task.id)/decrypt/error")
            // TODO: propagate error from HAC
            task.error = NSError(domain: "com.halloapp.downloadmanager", code: 1, userInfo: nil)
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
        self.tasks.remove(task)

        DispatchQueue.main.async {
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    private func taskFailed(_ task: Task) {
        self.tasks.remove(task)

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
            self.delegate?.feedDownloadManager(self, didFinishTask: task)
        }
    }

    // MARK: File management

    private func fileURL(for task: Task) -> URL {
        var first: String?, second: String?
        for ch in task.filename.unicodeScalars {
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
        return AppContext.mediaDirectoryURL
                .appendingPathComponent(first!, isDirectory: true)
                .appendingPathComponent(second!, isDirectory: true)
                .appendingPathComponent(task.filename, isDirectory: false)
    }
}
