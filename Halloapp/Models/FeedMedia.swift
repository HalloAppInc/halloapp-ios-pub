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
    
    @Published var image: UIImage = UIImage()
    @Published var origImage: UIImage = UIImage()
    @ObservedObject var imageLoader: ImageLoader = ImageLoader()
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(   feedItemId: String = "",
            order: Int = 0,
            type: String = "",
            url: String = "",
            width: Int = 0,
            height: Int = 0) {
        
        self.feedItemId = feedItemId
        self.order = order
        self.type = type
        self.url = url
        self.width = width
        self.height = height
    }
    
    func loadImage() {
        if (self.url != "") {
            imageLoader = ImageLoader(urlString: self.url)
            cancellableSet.insert(
                imageLoader.didChange.sink(receiveValue: { [weak self] _ in
                    
                    guard let self = self else { return }
                    
                    DispatchQueue.global(qos: .background).async {
                        
                        let orig = UIImage(data: self.imageLoader.data) ?? UIImage()
                    
                        let thumb = orig.getThumbnail() ?? UIImage()

                        
                        
                        DispatchQueue.main.async {
                            
                            self.image = thumb
                            self.didChange.send()
                            
                        }
                        
                        DispatchQueue.global(qos: .background).async {
                            FeedMediaCore().updateImage(feedItemId: self.feedItemId, url: self.url, thumb: thumb, orig: orig)
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
