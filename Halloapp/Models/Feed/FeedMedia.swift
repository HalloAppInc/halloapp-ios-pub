//
//  FeedMedia.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import Combine
import SwiftUI

class FeedMedia: Identifiable, ObservableObject, Hashable {
    
    var id = UUID().uuidString
    
    var didChange = PassthroughSubject<Void, Never>()
    
    var feedItemId: String = ""
    var order: Int = 0
    
    var type: String = ""
    var url: String = ""
    var width: Int = 0
    var height: Int = 0
    var numTries: Int = 0
    
    var key: String = ""
    var hash: String = ""
    @Published var encryptedData: Data?
    
    @Published var image: UIImage = UIImage()
    
    @Published var data: Data?
    @Published var tempUrl: URL?
    
    @Published var origImage: UIImage = UIImage()
    
    @ObservedObject var imageLoader: ImageLoader = ImageLoader()
    

    private var cancellableSet: Set<AnyCancellable> = []
    
    init(   feedItemId: String = "",
            order: Int = 0,
            type: String = "",
            url: String = "",
            width: Int = 0,
            height: Int = 0,
            numTries: Int = 0) {
        
        self.feedItemId = feedItemId
        self.order = order
        self.type = type
        self.url = url
        self.width = width
        self.height = height
        self.numTries = numTries
    }
    
    func loadImage() {
        if (self.url != "") {

            
            DispatchQueue.global(qos: .default).async {
                print("updating numTries on media count to \(self.numTries + 1)")
                FeedMediaCore().updateNumTries(feedItemId: self.feedItemId, url: self.url, numTries: self.numTries + 1)
            }
            
            imageLoader = ImageLoader(urlString: self.url)
            cancellableSet.insert(
                imageLoader.didChange.sink(receiveValue: { [weak self] _ in
                    
                    print("got didchange")
                    
                    guard let self = self else { return }
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        
                        print("processing media for \(self.feedItemId)")
                        
                        var imageData: Data = Data()
                        
                        var isEncryptedMedia: Bool = false
                        var isEncryptedMediaSafe: Bool = false
                        
                        if self.key != "" && self.hash != "" {
                        
                            isEncryptedMedia = true
                            print("encrypted media")
                            
                            if let decryptedData = HAC().decryptData(   data: self.imageLoader.data,
                                                                        key: self.key,
                                                                        hash: self.hash,
                                                                        type: "image") {
                                isEncryptedMediaSafe = true
                                imageData = decryptedData
                            }
                            
                        }
                        
                        if isEncryptedMedia {
                            if !isEncryptedMediaSafe {
                                print("encrypted media is not safe, abort")
                                return
                            }
                        } else {
                            print("not encrypted for \(self.feedItemId) \(self.imageLoader.data.count)")
                            imageData = self.imageLoader.data
                        }
   
                        
                        let orig = UIImage(data: imageData) ?? UIImage()
                    
                        /* we could have an uploaded image that is corrupted */
                        if (orig.size.width > 0) {
                        

                            DispatchQueue.main.async {
                                self.image = orig
                                self.didChange.send()
                            }
                            
                            DispatchQueue.global(qos: .default).async {
                                
                                var res: Int = 640

                                if UIScreen.main.bounds.width <= 375 {
                                    res = 480
                                }
                                
                                /* thumbnails are currently not used right now but will be used in the future */
                                let thumb = orig.getNewSize(res: res) ?? UIImage() // note: getNewSize will not resize if the pic is lower than res
                                
                                FeedMediaCore().updateImage(feedItemId: self.feedItemId, url: self.url, thumb: thumb, orig: orig)
                            }
                            
                        }
                        
                        
                    }
                        
                })
            )
        }
    }
    
    static func == (lhs: FeedMedia, rhs: FeedMedia) -> Bool {
        return lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
}
