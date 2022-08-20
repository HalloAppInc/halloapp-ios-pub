//
//  CommonMediaUploader.swift
//  Core
//
//  Created by Chris Leonavicius on 7/20/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import CoreData
import Foundation

enum MediaUploadType {
    case direct
    case resumable
}

enum MediaUploadError: Error {
    case mediaNotFound
    case uploadOffsetFetchFailed
    case missingDownloadLocation
    case missingFile
    case emptyFile
    case couldNotFetchURLInfo
    case serverError
    case tooLarge
    case cancelled
    case unknown
}

/*
 Uploader for CommonMedia objects

 How it works:
 1/ When a new upload begins, we start a task to interact with the UploadTaskManager actor and ensure we have a UploadTask created.
 2/ This kicks off a detached task, which will fetch URLs, update media status, etc. This returns the background URLSessionUploadTask that it started, or nil if
    the task is already completed.
 3/ The upload task will complete, and we create another task (similar to 1/) for interacting with the UploadTaskManager.
 4/ This will kick off another task similar to 2/ that handles the response, and either begins another request or completes.
*/
public class CommonMediaUploader: NSObject {

    public let postMediaStatusChangedPublisher = PassthroughSubject<FeedPostID, Never>()

    private actor UploadTaskManager {

        nonisolated let taskCreatedSubject = PassthroughSubject<UploadTask?, Never>()

        private var uploadTasks: [CommonMediaID: UploadTask] = [:]

        func existingTask(for mediaID: CommonMediaID) -> UploadTask? {
            return uploadTasks[mediaID]
        }

        func addTaskIfNotExist(for mediaID: CommonMediaID) -> UploadTask? {
            guard existingTask(for: mediaID) == nil else {
                return nil
            }

            let task = UploadTask(mediaID: mediaID)
            uploadTasks[mediaID] = task
            taskCreatedSubject.send(task)
            return task
        }

        func findOrCreateTask(for mediaID: CommonMediaID) -> UploadTask {
            let task = existingTask(for: mediaID) ?? UploadTask(mediaID: mediaID)
            uploadTasks[mediaID] = task
            taskCreatedSubject.send(task)
            return task
        }

        func cancelAndRemoveTask(for mediaID: CommonMediaID) {
            existingTask(for: mediaID)?.cancel()
            uploadTasks[mediaID] = nil
        }
    }

    private class UploadTask {
        let mediaID: CommonMediaID
        var currentTask: Task<URLSessionUploadTask?, Error>?
        var currentURLTask: URLSessionTask? {
            didSet {
                // Keep a single upload progress task per uploadTask that holds the max completed progress percent of any request
                progressCancellable = currentURLTask?.progress.publisher(for: \.fractionCompleted).sink { [weak self] progress in
                    guard let self = self else {
                        return
                    }

                    self.progressPublisher.send(max(self.progressPublisher.value, Float(progress)))
                }
            }
        }
        var progressCancellable: AnyCancellable?
        var progressPublisher = CurrentValueSubject<Float, Never>(Float(0))

        init(mediaID: CommonMediaID) {
            self.mediaID = mediaID
        }

        func cancel() {
            progressCancellable?.cancel()
            currentTask?.cancel()
            currentURLTask?.cancel()
        }
    }

    private var backgroundURLSessionCompletion: (() -> Void)?

    private let service: CoreService
    private let mainDataStore: MainDataStore
    private let mediaHashStore: MediaHashStore
    private let uploadTaskManager = UploadTaskManager()

    private lazy var backgroundURLSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.halloapp.media")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = TimeInterval(15)
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(service: CoreService, mainDataStore: MainDataStore, mediaHashStore: MediaHashStore) {
        self.service = service
        self.mainDataStore = mainDataStore
        self.mediaHashStore = mediaHashStore
        super.init()

        _ = backgroundURLSession // ensure this is created at init so the system can find it on reconnect
    }

    public func upload(mediaID: CommonMediaID, didBeginUpload: ((Result<CommonMediaID, Error>) -> Void)? = nil) {
        Task {
            guard let uploadTask = await uploadTaskManager.addTaskIfNotExist(for: mediaID) else {
                DDLogInfo("CommonMediaUploader/upload/existing upload task in progress for \(mediaID), aborting")
                return
            }

            DDLogInfo("CommonMediaUploader/upload/Starting upload for \(mediaID)")

            let task = Task.detached {
                try await self.beginUpload(mediaID: mediaID)
            }
            uploadTask.currentTask = task

            switch await task.result {
            case .success(let urlSessionUploadTask):
                if let urlSessionUploadTask = urlSessionUploadTask {
                    uploadTask.currentTask = nil
                    uploadTask.currentURLTask = urlSessionUploadTask
                } else {
                    await uploadTaskManager.cancelAndRemoveTask(for: mediaID)
                }
                didBeginUpload?(.success(mediaID))
            case .failure(let error):
                try? await self.updateMedia(with: mediaID) { media in
                    media.status = .uploadError
                }
                dispatchMediaStatusChanged(with: mediaID)
                await uploadTaskManager.cancelAndRemoveTask(for: mediaID)
                didBeginUpload?(.failure(error))
            }
        }
    }

    public func cancelUpload(mediaID: CommonMediaID) {
        Task {
            await uploadTaskManager.cancelAndRemoveTask(for: mediaID)
            try? await self.updateMedia(with: mediaID) { media in
                media.status = .uploadError
            }
            dispatchMediaStatusChanged(with: mediaID)
        }
    }

    public func resumeHandlingEventsForBackgroundURLSession(completion: (() -> Void)?) {
        backgroundURLSessionCompletion = completion
        // Create tasks for any in-progress requests
        Task {
            let (_, uploadTasks, _) = await backgroundURLSession.tasks
            for uploadTask in uploadTasks {
                guard let mediaID = uploadTask.taskDescription else {
                    DDLogError("CommonMediaUploader/resumeHandlingEventsForBackgroundURLSession/invalid task")
                    return
                }
                let task = await uploadTaskManager.findOrCreateTask(for: mediaID)
                task.currentURLTask = uploadTask
                DDLogInfo("CommonMediaUploader/resumeHandlingEventsForBackgroundURLSession/existing task with \(mediaID)")
            }
        }
    }

    private func beginUpload(mediaID: CommonMediaID) async throws -> URLSessionUploadTask? {
        var mediaURL: URL?
        var type: CommonMediaType?
        var sha256: String?
        var key: String?
        var blobVersion: BlobVersion?
        var encryptedFileURL: URL?
        var existingURLInfo: MediaURLInfo?

        // not really an update here, just extract the values we need
        try await updateMedia(with: mediaID) { media in
            mediaURL = media.mediaURL
            type = media.type
            sha256 = media.sha256
            key = media.key
            blobVersion = media.blobVersion
            encryptedFileURL = media.encryptedFileURL
            existingURLInfo = media.urlInfo
        }

        guard let type = type, let sha256 = sha256, let key = key, let blobVersion = blobVersion else {
            DDLogError("CommonMediaUploader/beginUpload/unexpected nil values from \(mediaID)")
            throw MediaUploadError.mediaNotFound
        }

        // Begin processing if not already processed
        if let url = mediaURL, sha256.isEmpty, key.isEmpty {
            DDLogDebug("CommonMediaUploader/beginUpload/being processing \(mediaID)")
            let result = try await encodeMedia(mediaID: mediaID, type: type, mediaURL: url, blobVersion: blobVersion)
            DDLogDebug("CommonMediaUploader/beginUpload/completed processing \(mediaID)")

            let outputURL = url
                .deletingLastPathComponent()
                .appendingPathComponent(mediaID, isDirectory: false)
                .appendingPathExtension("processed")
                .appendingPathExtension(url.pathExtension)

            guard result.copy(to: outputURL) else {
                DDLogError("CommonMediaUploader/beginUpload/Could not copy processed media file for \(mediaID)")
                throw MediaUploadError.missingFile
            }

            if result.url != url {
                result.clear()
            }

            try await updateMedia(with: mediaID) { media in
                media.size = result.size
                media.key = result.key
                media.sha256 = result.sha256
                media.chunkSize = result.chunkSize
                media.blobSize = result.blobSize
                media.relativeFilePath = media.mediaDirectory.relativePath(forFileURL: outputURL)

                // re-resolve encryptedFileURL
                encryptedFileURL = media.encryptedFileURL
            }
        }

        guard let encryptedFileURL = encryptedFileURL else {
            DDLogError("CommonMediaUploader/beginUpload/missing encryptedFileURL for \(mediaID)")
            throw MediaUploadError.missingFile
        }

        guard FileManager.default.fileExists(atPath: encryptedFileURL.path) else {
            DDLogError("CommonMediaUploader/beginUpload/missing encryptedFileURL \(encryptedFileURL) for \(mediaID) does not exist")
            throw MediaUploadError.missingFile
        }

        guard let fileSize = try? encryptedFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > 0 else {
            DDLogError("CommonMediaUploader/beginUpload/attempting to upload empty file \(encryptedFileURL) for \(mediaID)")
            throw MediaUploadError.emptyFile
        }

        // Check if we've already uploaded the file
        let previousUploadInfo = await self.mediaHashStore.fetch(url: encryptedFileURL, blobVersion: blobVersion)

        let previousDownloadURL = previousUploadInfo?.url
        if let previousDownloadURL = previousDownloadURL  {
            DDLogInfo("CommonMediaUploader/beginUpload/Media was previously uploaded at \(previousDownloadURL) for \(mediaID)")
        }

        var urlInfo: MediaURLInfo?

        if previousDownloadURL == nil, let existingURLInfo = existingURLInfo, existingURLInfo.hasUploadURL {
            urlInfo = existingURLInfo
        } else {
            urlInfo = try await self.mediaURLInfo(uploadType: .resumable, uploadSizeInBytes: fileSize, previousDownloadURL: previousDownloadURL)
            if let urlInfo = urlInfo {
                try await self.updateMedia(with: mediaID) { media in
                    media.urlInfo = urlInfo
                }
            }
        }

        switch urlInfo {
        case .download(let downloadURL):
            try await updateMedia(with: mediaID) { media in
                media.url = downloadURL
                media.status = .uploaded

                if downloadURL == previousDownloadURL, let key = previousUploadInfo?.key, let sha256 = previousUploadInfo?.sha256 {
                    media.key = key
                    media.sha256 = sha256
                }
            }
            dispatchMediaStatusChanged(with: mediaID)
            return nil
        case .getPut(_, let putURL):
            return startDirectUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, patchURL: putURL)
        case .patch(let patchURL):
            return startResumableUpload(mediaID: mediaID, offset: try await uploadOffset(forPatchURL: patchURL), encryptedFileURL: encryptedFileURL, patchURL: patchURL)
        case .none:
            DDLogError("CommonMediaUploader/upload/Could not fetch urlInfo for \(mediaID)")
            throw MediaUploadError.couldNotFetchURLInfo
        }
    }

    private func parseResponseAndRetryIfNeeded(mediaID: CommonMediaID, task: URLSessionTask, error: Error?) async throws -> URLSessionUploadTask? {
        let downloadURL = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Download-location").flatMap { URL(string: $0) }
        var responseError: Error?
        // PATCH indicates this was a resumable upload
        if task.originalRequest?.httpMethod == "PATCH", downloadURL == nil {
            responseError = MediaUploadError.missingDownloadLocation
        }

        if let error = error ?? responseError {
            // Upload failed
            DDLogError("CommonMediaUploader/parseResponseAndRetryIfNeeded with error: \(error) \(task.response?.debugDescription ?? "(null)")")

            var numTries: Int16 = 0
            var encryptedFileURL: URL?
            try await updateMedia(with: mediaID) { media in
                encryptedFileURL = media.encryptedFileURL
                numTries = media.numTries + 1
                media.numTries = numTries
            }

            guard let encryptedFileURL = encryptedFileURL else {
                DDLogError("CommonMediaUploader/parseResponseAndRetryIfNeeded")
                throw MediaUploadError.mediaNotFound
            }

            if numTries > 3 {
                // fetch new urls for direct upload and start task freshly again!
                return try await retryUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, type: .direct)
            } else {
                guard let statusCode = (task.response as? HTTPURLResponse)?.statusCode else {
                    // If the error is unknown - this is primarily due to loss of connection without a server response.
                    // so we should retry this task immediately.
                    DDLogError("CommonMediaUploader/parseResponseAndRetryIfNeeded/Failed with empty status code for \(mediaID)")
                    return try await retryUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, type: .resumable)
                }
                DDLogInfo("CommonMediaUploader/parseResponseAndRetryIfNeeded/Failed with status \(statusCode) for \(mediaID)")

                switch statusCode {
                /*
                 Missing or invalid Content-Type/Upload-Offset header, or Indication that Upload has been stopped by the server;
                 Fix the header (in case of header problem) and start by sending HEAD to fetch the offset and send PATCH to upload content.
                 Upload can be stopped by the server in case the client sends HEAD request while a PATCH request is ongoing.
                 */
                case 400:
                    throw MediaUploadError.serverError

                /*
                 Object not found; Retry by sending IQ with size request to ejabberd.
                 This condition is possible in case upload server looses its state and the upload needs to be started from the very begining.
                 */
                case 404:
                    // fetch new urls for resumable upload and start task freshly again!
                    return try await retryUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, type: .resumable)
                /*
                 Precondition failed; Try direct upload by sending IQ without size attribute.
                 Here we are checking Tus-Resumable header to be compatible. The current expected value is 1.0.0.
                 */
                case 412:
                    // fetch new urls for direct upload and start task freshly again!
                    return try await retryUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, type: .direct)
                /*
                 Requested Entity too large; Cann't upload this large an object (We don't impose any limits right now, but we will in future).
                 */
                case 413:
                    throw MediaUploadError.tooLarge
                /*
                 Other 4XX errors or 5XX errors
                 */
                default:
                    // Retry three time after (2, 4, 8) seconds. After three failures try direct upload by sending IQ without size attribute.
                    try await Task.sleep(nanoseconds: 2 * UInt64(numTries) * NSEC_PER_SEC)
                    return try await retryUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, type: .resumable)
                }
            }
        } else {
            var encryptedFileURL: URL?
            var mediaURL: URL?
            var blobVersion: BlobVersion?
            var key: String?
            var sha256: String?

            try await updateMedia(with: mediaID) { media in
                // downloadURL is not present for direct uploads, do not overwrite
                if let downloadURL = downloadURL {
                    media.url = downloadURL
                }
                media.status = .uploaded

                encryptedFileURL = media.encryptedFileURL
                mediaURL = media.url
                blobVersion = media.blobVersion
                key = media.key
                sha256 = media.sha256
            }
            dispatchMediaStatusChanged(with: mediaID)

            if let encryptedURL = encryptedFileURL, let blobVersion = blobVersion, let key = key, let sha256 = sha256, let mediaURL = mediaURL {
                mediaHashStore.update(url: encryptedURL, blobVersion: blobVersion, key: key, sha256: sha256, downloadURL: mediaURL)
            }

            DDLogError("CommonMediaUploader/parseResponseAndRetryIfNeeded/successfully uploaded \(mediaID)")
            return nil
        }
    }

    private func retryUpload(mediaID: CommonMediaID, encryptedFileURL: URL, type: MediaUploadType) async throws -> URLSessionUploadTask? {
        guard let fileSize = try? encryptedFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > 0 else {
            DDLogError("CommonMediaUploader/retryUpload/attempting to upload empty file \(encryptedFileURL) for \(mediaID)")
            throw MediaUploadError.emptyFile
        }
        guard let urlInfo = try await mediaURLInfo(uploadType: type, uploadSizeInBytes: fileSize, previousDownloadURL: nil) else {
            DDLogError("CommonMediaUploader/retryUpload/Could retreive urlInfo for \(mediaID)")
            throw MediaUploadError.couldNotFetchURLInfo
        }

        switch urlInfo {
        case .download(let downloadURL):
            try await updateMedia(with: mediaID) { media in
                media.url = downloadURL
                media.status = .uploaded
            }
            dispatchMediaStatusChanged(with: mediaID)
            return nil
        case .getPut(_, let putURL):
            return startDirectUpload(mediaID: mediaID, encryptedFileURL: encryptedFileURL, patchURL: putURL)
        case .patch(let patchURL):
            return startResumableUpload(mediaID: mediaID, offset: try await uploadOffset(forPatchURL: patchURL), encryptedFileURL: encryptedFileURL, patchURL: patchURL)
        }
    }
}

// MARK: - Helpers

extension CommonMediaUploader {

    private func startDirectUpload(mediaID: CommonMediaID, encryptedFileURL: URL, patchURL: URL) -> URLSessionUploadTask {
        DDLogInfo("CommonMediaUploader/startDirectUpload")
        var request = URLRequest(url: patchURL)
        request.httpMethod = "PUT"
        request.addValue("application/octet-stream", forHTTPHeaderField: "content-type")

        let uploadTask = backgroundURLSession.uploadTask(with: request, fromFile: encryptedFileURL)
        uploadTask.taskDescription = mediaID
        uploadTask.resume()

        return uploadTask
    }

    private func startResumableUpload(mediaID: CommonMediaID, offset: Int, encryptedFileURL: URL, patchURL: URL) -> URLSessionUploadTask {
        DDLogInfo("CommonMediaUploader/beginResumableUpload")

        var request = URLRequest(url: patchURL)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "content-type")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-offset")

        let uploadTask: URLSessionUploadTask
        if offset == 0 {
            uploadTask = backgroundURLSession.uploadTask(with: request, fromFile: encryptedFileURL)
        } else {
            // Background upload tasks are always file based - create a new temp file from the expected offset
            DDLogInfo("CommonMediaUploader/creating temp file at non-zero offset")
            do {
                let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString, isDirectory: false)
                    .appendingPathExtension("upload")
                let originalFileHandle = try FileHandle(forReadingFrom: encryptedFileURL)
                try originalFileHandle.seek(toOffset: UInt64(offset))
                try originalFileHandle.availableData.write(to: tempFileURL)
                try originalFileHandle.close()
                uploadTask = backgroundURLSession.uploadTask(with: request, fromFile: tempFileURL)
            } catch {
                DDLogError("CommonMediaUploader/Unable to copy file \(encryptedFileURL) for resuming upload, restarting...")
                request.setValue(String(0), forHTTPHeaderField: "Upload-offset")
                uploadTask = backgroundURLSession.uploadTask(with: request, fromFile: encryptedFileURL)
            }
        }
        uploadTask.taskDescription = mediaID
        uploadTask.resume()

        return uploadTask
    }

    private func mediaURLInfo(uploadType: MediaUploadType, uploadSizeInBytes: Int, previousDownloadURL: URL?) async throws -> MediaURLInfo? {
        DDLogInfo("CommonMediaUploader/requestURLs")

        let type: Server_UploadMedia.TypeEnum
        let size: Int
        switch uploadType {
        case .resumable:
            type = .resumable
            size = uploadSizeInBytes
        case .direct:
            type = .direct
            size = 0
        }

        return try await withCheckedThrowingContinuation { continuation in
            service.requestMediaUploadURL(type: type, size: size, downloadURL: previousDownloadURL) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func uploadOffset(forPatchURL url: URL) async throws -> Int {
        DDLogInfo("CommonMediaUploader/uploadOffset")
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")

            let response: URLResponse
            if #available(iOSApplicationExtension 15.0, *) {
                (_, response) = try await URLSession.shared.data(for: request)
            } else {
                response = try await withCheckedThrowingContinuation { continuation in
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let response = response, error == nil {
                            continuation.resume(returning: response)
                        } else {
                            continuation.resume(throwing: error ?? MediaUploadError.unknown)
                        }
                    }.resume()
                }
            }

            guard let response = response as? HTTPURLResponse, let uploadOffset = response.value(forHTTPHeaderField: "Upload-Offset").flatMap({ Int($0) }) else {
                throw MediaUploadError.uploadOffsetFetchFailed
            }

            return uploadOffset
        } catch {
            DDLogError("CommonMediaUploader/Failed to fetch upload offset for \(url) - \(error)")
            throw MediaUploadError.uploadOffsetFetchFailed
        }
    }

    private func encodeMedia(mediaID: CommonMediaID, type: CommonMediaType, mediaURL: URL, blobVersion: BlobVersion) async throws -> ImageServerResult {
        return try await withCheckedThrowingContinuation { continuation in
            ImageServer.shared.prepare(type, url: mediaURL, for: mediaID, shouldStreamVideo: blobVersion == .chunked) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func updateMedia(with mediaID: CommonMediaID, update: @escaping (CommonMedia) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
                guard let self = self else {
                    return
                }
                guard let media = self.mainDataStore.commonMediaItem(id: mediaID, in: context) else {
                    DDLogError("CommonMediaUploader/UpdateMedia/Media not found!")
                    continuation.resume(throwing: MediaUploadError.mediaNotFound)
                    return
                }

                
                update(media)

                if context.hasChanges {
                    do {
                        try context.save()
                        continuation.resume()
                    } catch {
                        DDLogError("CommonMediaUploader/UpdateMedia/Failed to save \(error)")
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func dispatchMediaStatusChanged(with mediaID: CommonMediaID) {
        mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else {
                return
            }
            guard let media = self.mainDataStore.commonMediaItem(id: mediaID, in: context) else {
                DDLogError("CommonMediaUploader/dispatchmediaStatusChanged/Could not find media \(mediaID)")
                return
            }

            if let post = media.post ?? media.linkPreview?.post {
                self.postMediaStatusChangedPublisher.send(post.id)
            } else {
                DDLogError("CommonMediaUploader/dispatchmediaStatusChanged/Uploaded media with an unsupported associated type")
                #if DEBUG
                fatalError("Please add support for the host object here")
                #endif
            }
        }
    }

    public func progress(for mediaID: CommonMediaID) -> AnyPublisher<Float, Never> {
        // Find any existing or new task for the media ID and return its progressPublisher
        let existingUploadTaskPublisher = Future<UploadTask?, Never> { completion in
            Task {
                completion(.success(await self.uploadTaskManager.existingTask(for: mediaID)))
            }
        }.eraseToAnyPublisher()

        return Publishers.Merge(existingUploadTaskPublisher, uploadTaskManager.taskCreatedSubject)
            .compactMap { $0 }
            .filter { $0.mediaID == mediaID }
            .flatMap { $0.progressPublisher }
            .eraseToAnyPublisher()
    }
}

// MARK: - URLSessionDelegate

extension CommonMediaUploader: URLSessionDelegate {

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DDLogInfo("CommonMediaUploader/urlSessionDidFinishEvents")
        backgroundURLSessionCompletion?()
        backgroundURLSessionCompletion = nil
    }
}

// MARK: - URLSessionTaskDelegate

extension CommonMediaUploader: URLSessionTaskDelegate {

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DDLogInfo("CommonMediaUploader/Progress/\(task.taskDescription ?? "")/ \(totalBytesSent) / \(totalBytesExpectedToSend)")
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let mediaID = task.taskDescription else {
            DDLogError("CommonMediaUploader/didCompleteWithError/media task description does not contain mediaID")
            return
        }

        DDLogInfo("CommonMediaUploader/didCompleteWithError/received response for \(mediaID)")

        // Check if this was just cancelled
        if let urlError = error as? URLError, urlError.code == .cancelled {
            DDLogInfo("CommonMediaUploader/didCompleteWithError/cancelled request for \(mediaID)")
            return
        }

        Task {
            let uploadTask = await uploadTaskManager.findOrCreateTask(for: mediaID)
            uploadTask.currentURLTask = nil

            let task = Task.detached {
                try await self.parseResponseAndRetryIfNeeded(mediaID: mediaID, task: task, error: error)
            }

            uploadTask.currentTask = task

            switch await task.result {
            case .success(let urlSessionUploadTask):
                if let urlSessionUploadTask = urlSessionUploadTask {
                    uploadTask.currentTask = nil
                    uploadTask.currentURLTask = urlSessionUploadTask
                } else {
                    await uploadTaskManager.cancelAndRemoveTask(for: mediaID)
                }
            case .failure:
                try? await self.updateMedia(with: mediaID) { media in
                    media.status = .uploadError
                }
                dispatchMediaStatusChanged(with: mediaID)
                await uploadTaskManager.cancelAndRemoveTask(for: mediaID)
            }
        }
    }
}
