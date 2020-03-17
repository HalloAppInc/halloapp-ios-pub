//
//  ImageLoader.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/27/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import SwiftUI

class ImageLoader: ObservableObject {
    
    var didChange = PassthroughSubject<Data, Never>()
    
    var data = Data() {
        didSet {
            didChange.send(data)
        }
    }
    
    private var retries = 0
    
    init() {
        
    }

    init(urlString: String) {
        
        tryLoad(url: urlString)
        
    }
    
    func tryLoad(url: String) {
        
        
        DDLogInfo("fetch image remotely, retry no: \(self.retries)")
        
        if self.retries < 3 {
            
            let delay = (self.retries < 1) ? 0.0 : 5.0
            
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                self.load(url: url)
            }
        }
        self.retries += 1
    }
    
    func load(url: String) {
        
        if url == "" {
            return
        }

        guard let formedUrl = URL(string: url) else {
            return
        }
        
        var urlRequest = URLRequest(url: formedUrl)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            
            if error == nil {
                
                if let httpResponse = response as? HTTPURLResponse {
                    DDLogInfo("response \(httpResponse.statusCode)")
                    
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
                    
                    DDLogInfo("Got Media Data: \(data.count)")
//                    print("\(response)")
                    
                    self.data = data
            
                }
                
            } else {
         
                self.tryLoad(url: url)
             
            }
            
        }
        task.resume()
        
    }
    
}
