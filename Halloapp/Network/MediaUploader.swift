//
//  MediaUploader.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 8/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation

enum MediaUploadError: Error {
    case canceled
    case malformedResponse
    case invalidUrls
    case unknownError
}

enum MediaUploadType {
    case directUpload
    case resumableUpload
}

protocol MediaUploadable {

    var index: Int { get }

    var encryptedFilePath: String? { get }

    var urlInfo: MediaURLInfo? { get }
}

struct SimpleMediaUploadable: MediaUploadable {

    let index = 0
    let encryptedFilePath: String?
    let urlInfo: MediaURLInfo? = nil
}

final class MediaUploader {

    /**
     URL is media download url.
     */
    struct UploadDetails {
        var downloadURL: URL
        var fileSize: Int
    }
    typealias Completion = (Result<UploadDetails, Error>) -> ()
    typealias FetchUrls = (MediaURLInfo) -> ()

    class Task: Hashable, Equatable {
        let groupId: String // Could be FeedPostID or ChatMessageID or CommentID
        let index: Int
        let fileURL: URL
        private let completion: Completion

        private(set) var isCanceled = false
        private var isFinished = false

        var downloadURL: URL?
        var uploadRequest: Request?
        var totalUploadSize: Int64 = 0
        var completedSize: Int64 = 0
        var progressDidChange: Bool = false

        var mediaUploadType: MediaUploadType = .resumableUpload
        var didGetUrls: FetchUrls
        var failureCount: Int64 = 0
        var mediaUrls: MediaURLInfo?
        init(groupId: String, mediaUrls: MediaURLInfo?, index: Int, fileURL: URL, didGetUrls: @escaping FetchUrls, completion: @escaping Completion) {
            self.groupId = groupId
            self.mediaUrls = mediaUrls
            self.index = index
            self.fileURL = fileURL
            self.didGetUrls = didGetUrls
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
            let details = UploadDetails(downloadURL: downloadURL!, fileSize: Int(totalUploadSize))
            completion(.success(details))
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

    // Use Custom Alamofire session - we modify the timeoutIntervalForRequest parameter in the configuration
    lazy var afSession : Alamofire.Session = { [weak self] in
        let configuration = URLSessionConfiguration.default
        // Set the timeout to be 20 seconds.
        configuration.timeoutIntervalForRequest = TimeInterval(20)

        let session = Alamofire.Session(configuration: configuration)
        return session
    }()

    init(service: CoreService) {
        self.service = service
    }

    // MARK: Task Management

    private let tasksQueue = DispatchQueue(label: "com.halloapp.media.uploader", qos: .userInitiated)
    private var tasks = Set<Task>()

    private func addTask(task: Task) {
        tasksQueue.sync {
            _ = tasks.insert(task)
        }
    }

    func hasTasks(forGroupId groupId: String) -> Bool {
        return !tasks(forGroupId: groupId).isEmpty
    }

    private func tasks(forGroupId groupId: String) -> Set<Task> {
        tasksQueue.sync {
            return tasks.filter { $0.groupId == groupId }
        }
    }

    private func cancelAllTasks() {
        tasksQueue.sync {
            for task in tasks {
                task.cancel()
                tasks.remove(task)
            }
        }
    }

    private func cancelTasks(withGroupID groupID: String) {
        tasksQueue.sync {
            for task in tasks.filter({ $0.groupId == groupID }) {
                task.cancel()
                tasks.remove(task)
            }
        }
    }

    func clearTasks(withGroupID groupID: String) {
        tasksQueue.sync {
            for task in tasks.filter({ $0.groupId == groupID }) {
                tasks.remove(task)
            }
        }
    }

    private func finish(task: Task) {
        tasksQueue.sync {
            task.finished()
        }
    }

    private func fail(task: Task, withError error: Error) {
        tasksQueue.sync {
            task.failed(withError: error)
            tasks.remove(task)
        }
    }

    // Tus is the name of the protocol we use for resumable file uploads.
    // This function handles all failures in the resumable upload responses.
    private func handleTusFailure(task: Task, withResponse response: AFDataResponse<Data?>) {
        if task.progressDidChange == false {
            task.failureCount += 1
        } else {
            task.failureCount = 0
        }
        DDLogInfo("MediaUploader/handleTusFailure/\(task.groupId)/\(task.index)/ failureCount: \(task.failureCount), response: \(response)")
        DDLogInfo("MediaUploader/handleTusFailure/\(task.groupId)/\(task.index)/ progressDidChange: \(task.progressDidChange)")

        // After three failures try direct upload by sending IQ without size attribute.
        if task.failureCount > 3 {
            // fetch new urls for direct upload and start task freshly again!
            requestUrlsAndStartTask(uploadType: .directUpload, task: task)
        } else {
            // FailureCount is less than or equal to 3: so inspect the error code and act accordingly.
            let error = response.error as Error? ?? MediaUploadError.unknownError
            guard let statusCode = response.response?.statusCode else {
                // If the error is unknown - this is primarily due to loss of connection without a server response.
                // so we should retry this task.
                DDLogError("MediaUploader/handleTusFailure/Failed/response: \(response)")
                retryAfterDelay(task: task)
                return
            }
            DDLogInfo("MediaUploader/handleTusFailure/\(task.groupId)/\(task.index)/statusCode: \(statusCode)")

            switch statusCode {
            /*
             Missing or invalid Content-Type/Upload-Offset header, or Indication that Upload has been stopped by the server;
             Fix the header (in case of header problem) and start by sending HEAD to fetch the offset and send PATCH to upload content.
             Upload can be stopped by the server in case the client sends HEAD request while a PATCH request is ongoing.
             */
            case 400:
                fail(task: task, withError: error)

            /*
             Object not found; Retry by sending IQ with size request to ejabberd.
             This condition is possible in case upload server looses its state and the upload needs to be started from the very begining.
             */
            case 404:
                // fetch new urls for resumable upload and start task freshly again!
                requestUrlsAndStartTask(uploadType: .resumableUpload, task: task)

            /*
             Precondition failed; Try direct upload by sending IQ without size attribute.
             Here we are checking Tus-Resumable header to be compatible. The current expected value is 1.0.0.
             */
            case 412:
                // fetch new urls for direct upload and start task freshly again!
                requestUrlsAndStartTask(uploadType: .directUpload, task: task)

            /*
             Requested Entity too large; Cann't upload this large an object (We don't impose any limits right now, but we will in future).
             */
            case 413:
                fail(task: task, withError: error)

            default:
                // For any other 4XX errors or 5XX errors
                // Retry three time after (5, 10, 20) seconds. After three failures try direct upload by sending IQ without size attribute.
                retryAfterDelay(task: task)
            }
        }
    }

    func retryAfterDelay(task: Task) {
        // Try and resume task using a timer - with delay based on failureCount.
        let timeDelay = Double(task.failureCount) * 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + timeDelay) {
            self.startMediaUpload(task: task)
        }
    }

    // MARK: Upload progress

    let uploadProgressDidChange = PassthroughSubject<String, Never>()

    func uploadProgress(forGroupId groupId: String) -> (Int, Float) {
        let items = tasks(forGroupId: groupId).filter { $0.totalUploadSize > 0 }
        guard items.count > 0 else { return (0, 0) }

        let total = items.reduce(into: Float(0)) { $0 += Float(Double($1.completedSize) / Double($1.totalUploadSize)) }
        return (items.count, total / Float(items.count))
    }

    // MARK: Starting / canceling uploads.

    func cancelAllUploads() {
        cancelAllTasks()
    }

    func cancelUpload(groupId: String) {
        cancelTasks(withGroupID: groupId)
    }

    func upload(media mediaItem: MediaUploadable, groupId: String, didGetURLs: @escaping (MediaURLInfo) -> (), completion: @escaping Completion) {
        // on reconnection stuck we try to resend stuck media items, but they might already have a task scheduled for retry
        guard nil == (tasks(forGroupId: groupId).first { $0.index == mediaItem.index }) else { return }

        let fileURL = resolveMediaPath(mediaItem.encryptedFilePath!)
        let task = Task(groupId: groupId, mediaUrls: mediaItem.urlInfo, index: Int(mediaItem.index), fileURL: fileURL, didGetUrls: didGetURLs, completion: completion)
        // Task might fail immediately so make sure it's added before being started.
        addTask(task: task)

        // Fetch urls if necessary and start media upload.
        switch task.mediaUrls {
        case .download(let downloadURL):
            // No upload to be done here, just refreshUrls
            task.downloadURL = downloadURL
            requestUrlsAndStartTask(uploadType: .resumableUpload, task: task)
        case .getPut(_, _), .patch(_):
            startMediaUpload(task: task)
        case .none:
            requestUrlsAndStartTask(uploadType: .resumableUpload, task: task)
        }
    }

    private func requestUrlsAndStartTask(uploadType: MediaUploadType, task: Task) {
        // Request URLs first.
        let fileSize: Int
        // When sending out an iq - try our preference of urls.
        // we'll update the task-type again depending on what the server responds with.
        switch uploadType {
        case .resumableUpload:
            fileSize = (try? task.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        case .directUpload:
            fileSize = 0
        }
        DDLogInfo("MediaUploader/requestUrlsAndStartTask/fileSize: \(fileSize), fileURL: \(task.fileURL)")

        service.requestMediaUploadURL(size: fileSize, downloadURL: task.downloadURL) { result in
            guard !task.isCanceled else { return }
            switch result {
            case .success(let mediaURLs):
                if let mediaURLs = mediaURLs {
                    DDLogInfo("MediaUploader/requestUrlsAndStartTask/\(task.groupId)/\(task.index)/success urls: [\(mediaURLs)]")
                    task.didGetUrls(mediaURLs)
                    task.mediaUrls = mediaURLs
                    self.startMediaUpload(task: task)
                } else {
                    DDLogError("MediaUploader/requestUrlsAndStartTask/\(task.groupId)/\(task.index)/error missing urls")
                    self.fail(task: task, withError: MediaUploadError.malformedResponse)
                }
            case .failure(let error):
                DDLogError("MediaUploader/requestUrlsAndStartTask/\(task.groupId)/\(task.index)/error [\(error)]")
                self.fail(task: task, withError: error)
            }
        }
    }

    // Check the urls in the task and start direct upload or the resumable upload accordingly.
    private func startMediaUpload(task: Task) {
        // set progressDidChange to false
        task.progressDidChange = false

        let mediaURLs = task.mediaUrls
        // Initiate media upload.
        switch mediaURLs {
        case .getPut(let getURL, let putURL):
            DDLogInfo("MediaUploader/startMediaUpload/\(task.groupId)/\(task.index)/ startDirectUpload")
            task.mediaUploadType = .directUpload
            task.downloadURL = getURL
            task.completedSize = 0
            startUpload(forTask: task, to: putURL)

        case .patch(let patchURL):
            DDLogInfo("MediaUploader/startMediaUpload/\(task.groupId)/\(task.index)/ startResumableUpload")
            task.mediaUploadType = .resumableUpload
            startResumableUpload(forTask: task, to: patchURL)

        case .download(let downloadURL):
            // No upload to be done here, we successfully refreshedUrls
            task.downloadURL = downloadURL
            self.finish(task: task)

        case .none:
            DDLogError("MediaUploader/startMediaUpload/\(task.groupId)/\(task.index)/ invalidUrls")
            fail(task: task, withError: MediaUploadError.invalidUrls)
        }
    }

    private func startUpload(forTask task: Task, to url: URL) {
        DDLogDebug("MediaUploader/startUpload/\(task.groupId)/\(task.index)/begin url=[\(url)]")

        task.uploadRequest = afSession.upload(task.fileURL, to: url, method: .put, headers: [ .contentType("application/octet-stream") ])
            .uploadProgress { [weak task, weak self] (progress) in
                guard let self = self, let task = task, !task.isCanceled else {
                    return
                }
                DDLogDebug("MediaUploader/startUpload/\(task.groupId)/\(task.index)/progress \(progress.fractionCompleted)")
                let completedUnitCount = progress.completedUnitCount
                if completedUnitCount > task.completedSize {
                    task.progressDidChange = true
                }
                task.totalUploadSize = progress.totalUnitCount
                task.completedSize = completedUnitCount
                self.uploadProgressDidChange.send(task.groupId)
            }
            .validate()
            .response { [weak task] (response) in
                guard let task = task, !task.isCanceled else {
                    return
                }
                switch response.result {
                case .success(_):
                    DDLogDebug("MediaUploader/startUpload/\(task.groupId)/\(task.index)/success")
                    self.finish(task: task)

                case .failure(let error):
                    DDLogError("MediaUploader/startUpload/\(task.groupId)/\(task.index)/error [\(error)]")
                    self.fail(task: task, withError: error)
                }
        }
    }

    private func startResumableUpload(forTask task: Task, to url: URL) {
        DDLogDebug("MediaUploader/startResumableUpload/\(task.groupId)/\(task.index)/begin url=[\(url)]")

        task.uploadRequest = afSession.request(url, method: .head, headers: [ "Tus-Resumable": "1.0.0" ])
            .validate()
            .response { [weak task] response in
                guard let task = task, !task.isCanceled else {
                    return
                }
                switch response.result {
                case .success(_):
                    if let uploadOffsetStr = response.response?.headers["Upload-Offset"], let uploadOffset = Int(uploadOffsetStr) {
                        DDLogDebug("MediaUploader/startResumableUpload/\(task.groupId)/\(task.index)/head/success Offset [\(uploadOffset)]")
                        self.continueResumableUpload(forTask: task, to: url, from: uploadOffset)
                    } else {
                        DDLogError("MediaUploader/startResumableUpload/\(task.groupId)/\(task.index)/head/malformed")
                        self.handleTusFailure(task: task, withResponse: response)
                    }

                case .failure(let error):
                    DDLogError("MediaUploader/startResumableUpload/\(task.groupId)/\(task.index)/head/error [\(error)]")
                    self.handleTusFailure(task: task, withResponse: response)
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
                    uploadRequest = afSession.upload(data, to: url, method: .patch, headers: headers)
                }
                catch {
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/seek-error [\(error)]")
                }
            }
        }
        if uploadRequest == nil {
            effectiveOffset = 0
            headers.update(name: "Upload-offset", value: String(effectiveOffset))
            uploadRequest = afSession.upload(task.fileURL, to: url, method: .patch, headers: headers)
        }

        task.uploadRequest = uploadRequest
            .uploadProgress { [weak task, weak self] progress in
                guard let self = self, let task = task, !task.isCanceled else {
                    return
                }
                DDLogDebug("MediaUploader/upload/\(task.groupId)/\(task.index)/progress \(progress.fractionCompleted)")
                let completedUnitCount = Int64(effectiveOffset) + progress.completedUnitCount
                if completedUnitCount > task.completedSize {
                    task.progressDidChange = true
                }
                task.completedSize = completedUnitCount
                self.uploadProgressDidChange.send(task.groupId)
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
                        self.handleTusFailure(task: task, withResponse: response)
                    }

                case .failure(let error):
                    DDLogError("MediaUploader/upload/\(task.groupId)/\(task.index)/error [\(error)]")
                    self.handleTusFailure(task: task, withResponse: response)
                }
        }
    }
}

