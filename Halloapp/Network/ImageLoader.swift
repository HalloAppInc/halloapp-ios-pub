//
//  ImageLoader.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/27/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Combine
import SwiftUI

class ImageLoader: ObservableObject {
    var didChange = PassthroughSubject<Data, Never>()
    var data = Data() {
        didSet {
            didChange.send(data)
        }
    }
    
    init() {
        
    }
    
    init(urlString: String) {
        
        if urlString == "" {
            return
        }
        
        var url = urlString
        
        if !urlString.lowercased().hasPrefix("http") {
            url = "https://cdn.image4.io/hallo\(url)"
        }
        
        guard let formedUrl = URL(string: url) else {
            return
        }
        
        let apiSecret = "OTAuZPlIJIM8rFOoJUNpYayd7Iubi/0B2HC+PU8WnRo="
        let apiKey = "Heis4jPh62Tuzh9hGP+K4w=="
        let base64 = "\(apiKey):\(apiSecret)".data(using: .utf8)?.base64EncodedString()
        
        var urlRequest = URLRequest(url: formedUrl)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Basic \(base64!)", forHTTPHeaderField: "Authorization")
        
//          print("fetching image")
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            
            guard let data = data else { return }
            DispatchQueue.main.async {
                self.data = data
        
            }
            

        }
        task.resume()
    }
}
