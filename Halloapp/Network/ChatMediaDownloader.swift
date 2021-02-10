//
//  Halloapp
//
//  Created by Tony Jiang on 9/27/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class ChatMediaDownloader: NSObject {
    
    private var maxRetries = 3
    private var waitBetweenRetries = 5.0
    private var retries = 0
    
    typealias ProgressHandler = (Double) -> Void
    typealias Completion = (URL) -> Void
    
    private var downloadUrl: URL
    private var progressHandler: ProgressHandler
    private var completion: Completion
    private var outputUrl: URL?
    
    init(url: URL, progressHandler: @escaping ProgressHandler, completion: @escaping Completion) {
        self.downloadUrl = url
        self.progressHandler = progressHandler
        self.completion = completion
        super.init()
        
        self.tryDownload()
    }
    
    deinit {
        DDLogInfo("ChatMediaDownloader/deinit")
    }

    private func tryDownload() {
        DDLogInfo("ChatMediaDownloader/tryDownload/\(downloadUrl) attempt [\(retries)]")
        
        if retries < maxRetries {
            let delay = (retries < 1) ? 0.0 : waitBetweenRetries
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                self.download()
            }
        }
        // TODO: signal somehow that all download attempts failed?
        retries += 1
    }
    
    private func download() {
        DDLogInfo("ChatMediaDownloader/download/\(downloadUrl)")
        var urlRequest = URLRequest(url: downloadUrl)
        
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.current)
        
        let task = session.downloadTask(with: urlRequest)
        task.resume()
    }
}

extension ChatMediaDownloader: URLSessionDelegate, URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DDLogInfo("ChatMediaDownloader/\(downloadUrl)/progress \(progress)")
            progressHandler(progress)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
            DDLogError("ChatMediaDownloader/\(downloadUrl) not a valid http response")
            tryDownload()
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            DDLogError("ChatMediaDownloader/\(downloadUrl) http error code: \(httpResponse.statusCode)")
            tryDownload()
            return
        }
        
        DDLogInfo("ChatMediaDownloader/complete/\(downloadUrl)")
        
        completion(location)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        DDLogError("ChatMediaDownloader/\(downloadUrl) Error [\(error)]")
        tryDownload()
    }
    
}
