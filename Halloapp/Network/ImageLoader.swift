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

        guard let formedUrl = URL(string: urlString) else {
            return
        }
        
        var urlRequest = URLRequest(url: formedUrl)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            
            guard let data = data else { return }

//            print("\(response)")
            
            DispatchQueue.main.async {
                self.data = data
        
            }
            
        }
        task.resume()
    }

}
