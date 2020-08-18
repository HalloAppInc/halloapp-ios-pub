//
//  MediaUploader.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 8/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Core
import Foundation

enum MediaUploadError: Error {
    case canceled
}

protocol MediaUploadable {

    var index: Int { get }

    var encryptedFilePath: String? { get }

    var uploadUrl: URL? { get }
}

final class MediaUploader {

    typealias Completion = (Result<Void, Error>) -> ()

    class Task: Hashable, Equatable {
        let groupId: String // Could be FeedPostID or ChatMessageID.
        let index: Int
        let fileURL: URL
        private let completion: Completion

        private(set) var isCanceled = false
        private var isFinished = false

        var uploadRequest: UploadRequest?

        init(groupId: String, index: Int, fileURL: URL, completion: @escaping Completion) {
            self.groupId = groupId
            self.index = index
            self.fileURL = fileURL
            self.completion = completion
        }

        func cancel() {
            assert(!isCanceled, "Task has already been canceled")
            assert(!isFinished, "Attempt to cancel a finished task")

            isCanceled = true
            uploadRequest?.cancel()
            completion(.failure(MediaUploadError.canceled))
        }

        func finished() {
            assert(!isFinished, "Task has already been finished")
            assert(!isCanceled, "Attempt to finished a canceled task")

            isFinished = true
            completion(.success(Void()))
        }

        func failed(withError error: Error) {
            assert(!isFinished, "Task has already been finished")
            assert(!isCanceled, "Attempt to finished a canceled task")

            isFinished = true
            completion(.failure(error))
        }

        static func == (lhs: Task, rhs: Task) -> Bool {
            return lhs.groupId == rhs.groupId && lhs.index == rhs.index
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(groupId)
            hasher.combine(index)
        }
    }

    private let xmppController: XMPPController

    private var tasks = Set<Task>()

    // Resolves relative media file path to file url.
    var resolveMediaPath: ((String) -> (URL))!

    init(xmppController: XMPPController) {
        self.xmppController = xmppController
    }

    func cancelAllUploads() {
        tasks.forEach({ $0.cancel() })
        tasks.removeAll()
    }

    func cancelUpload(groupId: String) {
        let tasksToCancel = tasks.filter({ $0.groupId == groupId })
        tasksToCancel.forEach { (task) in
            task.cancel()

            tasks.remove(task)
        }
    }

    func upload(media mediaItem: MediaUploadable, groupId: String, didGetURLs: @escaping (MediaURL) -> (), completion: @escaping Completion) {
        let fileURL = resolveMediaPath(mediaItem.encryptedFilePath!)
        let task = Task(groupId: groupId, index: Int(mediaItem.index), fileURL: fileURL, completion: completion)
        if let uploadUrl = mediaItem.uploadUrl {
            // Initiate media upload.
            startUpload(forTask: task, to: uploadUrl)
        } else {
            // Request URLs first.
            let request = XMPPMediaUploadURLRequest { (result) in
                guard !task.isCanceled else { return }

                switch result {
                case .success(let mediaURLs):
                    didGetURLs(mediaURLs)
                    self.startUpload(forTask: task, to: mediaURLs.put)

                case .failure(let error):
                    task.failed(withError: error)
                }
            }
            xmppController.enqueue(request: request)
        }
        tasks.insert(task)
    }

    private func startUpload(forTask task: Task, to url: URL) {
        DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/begin url=[\(url)]")

        task.uploadRequest = AF.upload(task.fileURL, to: url, method: .put, headers: [ "Content-Type": "application/octet-stream" ]).response { (response) in
            if let error = response.error {
                DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/error [\(error)]")
                task.failed(withError: error)
            } else {
                DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/success")
                task.finished()
            }
        }
    }
}

