//
//  Halloapp
//
//  Created by Tony Jiang on 9/27/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class ChatMediaDownloader {
    
    enum MediaType: String {
        case image = "jpg"
        case video = "mp4"
    }
    
    var didChange = PassthroughSubject<Data?, Never>()
    
    private(set) var data: Data? {
        didSet {
            didChange.send(data)
        }
    }
    private var maxRetries = 3
    private var waitBetweenRetries = 5.0
    private var retries = 0
    
    typealias Completion = (URL) -> Void
    
    private var type: MediaType?
    private var getUrl: URL
    private var completion: Completion
    private var outputUrl: URL?
    
    init(url: URL, completion: @escaping Completion) {
//        self.type = type
        self.getUrl = url
        self.completion = completion
        
//        self.outputUrl = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
//            .appendingPathComponent(ProcessInfo().globallyUniqueString)
//            .appendingPathExtension("\(self.type)")
        
        self.tryDownload()
    }

    func tryDownload() {
        DDLogInfo("ImageLoader/\(self.getUrl) Download attempt [\(self.retries)]")
        
        if self.retries < self.maxRetries {
            let delay = (self.retries < 1) ? 0.0 : self.waitBetweenRetries
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                self.download()
            }
        }
        // TODO: signal somehow that all download attempts failed?
        self.retries += 1
    }
    
    func download() {
        var urlRequest = URLRequest(url: self.getUrl)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let task = URLSession.shared.downloadTask(with: urlRequest) { localUrl, response, error in
            if error == nil {
                if let httpResponse = response as? HTTPURLResponse {
                    DDLogInfo("MediaDownloader/\(self.getUrl) Got response [\(httpResponse.statusCode)]")
                    if httpResponse.statusCode != 200 {
                        self.tryDownload()
                        return
                    }
                    
                    self.completion(localUrl!)
                }
                
//                guard let data = data else {
//                    self.tryDownload()
//                    return
//                }

            } else {
                DDLogError("ImageLoader/\(self.getUrl) Error [\(error!)]")
                self.tryDownload()
            }
        }
        task.resume()
    }
}
