//
//  ImageLoader.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/27/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class ImageLoader: ObservableObject {
    
    var didChange = PassthroughSubject<Data?, Never>()
    
    private(set) var data: Data? {
        didSet {
            didChange.send(data)
        }
    }
    
    private var retries = 0
    
    init(url: URL) {
        tryLoad(url: url)
    }

    func tryLoad(url: URL) {
        DDLogInfo("ImageLoader/\(url) Download attempt [\(self.retries)]")
        
        if self.retries < 3 {
            let delay = (self.retries < 1) ? 0.0 : 5.0
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                self.load(url: url)
            }
        }
        // TODO: signal somehow that all download attempts failed?
        self.retries += 1
    }
    
    func load(url: URL) {
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if error == nil {
                if let httpResponse = response as? HTTPURLResponse {
                    DDLogInfo("ImageLoader/\(url) Got response [\(httpResponse)]")
                    if httpResponse.statusCode != 200 {
                        self.tryLoad(url: url)
                        return
                    }
                }
                
                guard let data = data else {
                    self.tryLoad(url: url)
                    return
                }

                DispatchQueue.main.async {
                    DDLogInfo("ImageLoader/\(url) Download complete. size=[\(data.count)]")
                    self.data = data
                }
            } else {
                DDLogError("ImageLoader/\(url) Error [\(error!)]")
                self.tryLoad(url: url)
            }
        }
        task.resume()
    }
}
