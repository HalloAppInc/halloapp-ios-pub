//
//  MediaUploader.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 8/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Combine
import Core
import Foundation

enum MediaUploadError: Error {
    case canceled
    case malformedResponse
}

protocol MediaUploadable {

    var index: Int { get }

    var encryptedFilePath: String? { get }

    var urlInfo: MediaURLInfo? { get }
}

final class MediaUploader {

    /**
     URL is media download url.
     */
    typealias Completion = (Result<URL, Error>) -> ()

    class Task: Hashable, Equatable {
        let groupId: String // Could be FeedPostID or ChatMessageID.
        let index: Int
        let fileURL: URL
        private let completion: Completion

        private(set) var isCanceled = false
        private var isFinished = false

        var downloadURL: URL?
        var uploadRequest: Request?
        var totalUploadSize: Int64 = 0
        var completedSize: Int64 = 0

        init(groupId: String, index: Int, fileURL: URL, completion: @escaping Completion) {
            self.groupId = groupId
            self.index = index
            self.fileURL = fileURL
            self.completion = completion
        }

        func cancel() {
            guard !isCanceled && !isFinished else {
                return
            }

            DDLogDebug("MediaUploader/task/\(groupId)-\(index)/cancel")

            isCanceled = true
            uploadRequest?.cancel()
            completion(.failure(MediaUploadError.canceled))
        }

        func finished() {
            guard !isCanceled && !isFinished else {
                return
            }

            DDLogDebug("MediaUploader/task/\(groupId)-\(index)/finished")

            isFinished = true
            completion(.success(downloadURL!))
        }

        func failed(withError error: Error) {
            guard !isCanceled && !isFinished else {
                return
            }

            DDLogDebug("MediaUploader/task/\(groupId)-\(index)/failed [\(error)]")

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

    private let service: CoreService

    // Resolves relative media file path to file url.
    var resolveMediaPath: ((String) -> (URL))!

    init(service: CoreService) {
        self.service = service
    }

    // MARK: Task Management

    private var tasks = Set<Task>()

    func activeTaskGroupIdentifiers() -> Set<String> {
        return Set(tasks.map({ $0.groupId }))
    }

    func hasTasks(forGroupId groupId: String) -> Bool {
        return tasks.contains(where: { $0.groupId == groupId })
    }

    private func finish(task: Task) {
        task.finished()
        tasks.remove(task)
    }

    private func fail(task: Task, withError error: Error) {
        task.failed(withError: error)
        tasks.remove(task)
    }

    // MARK: Upload progress

    let uploadProgressDidChange = PassthroughSubject<(String, Float), Never>()

    func uploadProgress(forGroupId groupId: String) -> Float {
        let (totalSize, uploadedSize) = tasks.filter({ $0.groupId == groupId }).reduce(into: (Int64(0), Int64(0))) { (result, task) in
            result.0 += task.totalUploadSize
            result.1 += task.completedSize
        }
        guard totalSize > 0 else {
            DDLogDebug("MediaUploader/task/\(groupId)/upload-progress [0.0]")
            return 0
        }
        let progress = Float(Double(uploadedSize) / Double(totalSize))
        DDLogDebug("MediaUploader/task/\(groupId)/upload-progress [\(progress)]")
        return progress
    }

    private func updateUploadProgress(forGroupId groupId: String) {
        let progress = uploadProgress(forGroupId: groupId)
        uploadProgressDidChange.send((groupId, progress))
    }

    // MARK: Starting / canceling uploads.

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

    func upload(media mediaItem: MediaUploadable, groupId: String, didGetURLs: @escaping (MediaURLInfo) -> (), completion: @escaping Completion) {
        let fileURL = resolveMediaPath(mediaItem.encryptedFilePath!)
        let task = Task(groupId: groupId, index: Int(mediaItem.index), fileURL: fileURL, completion: completion)
        // Task might fail immediately so make sure it's added before being started.
        tasks.insert(task)
        if let urlInfo = mediaItem.urlInfo {
            // Initiate media upload.
            switch urlInfo {
            case .getPut(let getURL, let putURL):
                task.downloadURL = getURL
                startUpload(forTask: task, to: putURL)

            case .patch(let patchURL):
                startResumableUpload(forTask: task, to: patchURL)
            }

        } else {
            // Request URLs first.
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            service.requestMediaUploadURL(size: fileSize) { result in
                guard !task.isCanceled else { return }

                switch result {
                case .success(let mediaURLs):
                    didGetURLs(mediaURLs)
                    switch mediaURLs {
                    case .getPut(let getURL, let putURL):
                        task.downloadURL = getURL
                        self.startUpload(forTask: task, to: putURL)

                    case .patch(let patchURL):
                        self.startResumableUpload(forTask: task, to: patchURL)
                    }

                case .failure(let error):
                    self.fail(task: task, withError: error)
                }
            }
        }
    }

    private func startUpload(forTask task: Task, to url: URL) {
        DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/begin url=[\(url)]")

        task.uploadRequest = AF.upload(task.fileURL, to: url, method: .put, headers: [ .contentType("application/octet-stream") ])
            .uploadProgress { [weak task, weak self] (progress) in
                guard let self = self, let task = task, !task.isCanceled else {
                    return
                }
                DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/progress \(progress.fractionCompleted)")
                task.totalUploadSize = progress.totalUnitCount
                task.completedSize = progress.completedUnitCount
                self.updateUploadProgress(forGroupId: task.groupId)
            }
            .validate()
            .response { [weak task] (response) in
                guard let task = task, !task.isCanceled else {
                    return
                }
                switch response.result {
                case .success(_):
                    DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/success")
                    self.finish(task: task)

                case .failure(let error):
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/error [\(error)]")
                    self.fail(task: task, withError: error)
                }
        }
    }

    private func startResumableUpload(forTask task: Task, to url: URL) {
        DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/begin url=[\(url)]")

        task.uploadRequest = AF.request(url, method: .head, headers: [ "Tus-Resumable": "1.0.0" ])
            .validate()
            .response { [weak task] response in
                guard let task = task, !task.isCanceled else {
                    return
                }
                switch response.result {
                case .success(_):
                    if let uploadOffsetStr = response.response?.headers["Upload-Offset"], let uploadOffset = Int(uploadOffsetStr) {
                        DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/head/success Offset [\(uploadOffset)]")
                        self.continueResumableUpload(forTask: task, to: url, from: uploadOffset)
                    } else {
                        DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/head/malformed")
                        self.fail(task: task, withError: MediaUploadError.malformedResponse)
                    }

                case .failure(let error):
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/head/error [\(error)]")
                    self.fail(task: task, withError: error)
                }
            }

    }

    private func continueResumableUpload(forTask task: Task, to url: URL, from offset: Int) {

        if let fileSize = try? task.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            task.totalUploadSize = Int64(fileSize)
        }

        var effectiveOffset = offset
        var headers: HTTPHeaders = [ .contentType("application/offset+octet-stream"),
                                     .init(name: "Tus-Resumable", value: "1.0.0"),
                                     .init(name: "Upload-offset", value: String(offset)) ]
        var uploadRequest: UploadRequest!
        if offset > 0 {
            DDLogInfo("MediaUploader/upload/\(task.groupId)/\(task.index)/resume from=[\(offset)] totalSize=[\(task.totalUploadSize)]")

            if let fileHandle = FileHandle(forReadingAtPath: task.fileURL.path) {
                do {
                    try fileHandle.seek(toOffset: UInt64(offset))
                    let data = fileHandle.availableData
                    DDLogInfo("MediaUploader/upload/\(task.groupId)/\(task.index)/resume Loaded remainer size=[\(data.count)]")
                    uploadRequest = AF.upload(data, to: url, method: .patch, headers: headers)
                }
                catch {
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/seek-error [\(error)]")
                }
            }
        }
        if uploadRequest == nil {
            effectiveOffset = 0
            headers.update(name: "Upload-offset", value: String(effectiveOffset))
            uploadRequest = AF.upload(task.fileURL, to: url, method: .patch, headers: headers)
        }

        task.uploadRequest = uploadRequest
            .uploadProgress { [weak task, weak self] progress in
                guard let self = self, let task = task, !task.isCanceled else {
                    return
                }
                DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/progress \(progress.fractionCompleted)")
                task.completedSize = Int64(effectiveOffset) + progress.completedUnitCount
                self.updateUploadProgress(forGroupId: task.groupId)
            }
            .validate()
            .response { [weak task] response in
                guard let task = task, !task.isCanceled else {
                    return
                }
                switch response.result {
                case .success(_):
                    if let downloadLocation = response.response?.headers["Download-Location"], let downloadURL = URL(string: downloadLocation) {
                        DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/success downloadUrl=[\(downloadURL)]")
                        task.downloadURL = downloadURL
                        self.finish(task: task)
                    } else {
                        DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/malformed-response [\(response)]")
                        self.fail(task: task, withError: MediaUploadError.malformedResponse)
                    }

                case .failure(let error):
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/error [\(error)]")
                    self.fail(task: task, withError: error)
                }
        }
    }
}

