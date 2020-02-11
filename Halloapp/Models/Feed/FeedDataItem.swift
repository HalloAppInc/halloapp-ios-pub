//
//  FeedDataItem.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import Foundation
import SwiftUI
import Combine

class FeedDataItem: Identifiable, ObservableObject, Equatable, Hashable {
    
    var id = UUID().uuidString
    
    var didChange = PassthroughSubject<Void, Never>()
    
    var itemId: String
    
    var username: String
    var userImageUrl: String
    
    var text: String
    
    var timestamp: Double = 0
    
    var imageUrl: String
    
    @Published var media: [FeedMedia] = []
    @Published var mediaHeight: CGFloat = 0
    
    @Published var comments: [FeedComment] = []
    var unreadComments: Int
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(   itemId: String = "",
            username: String = "",
            imageUrl: String = "",
            userImageUrl: String = "",
            text: String = "",
            unreadComments: Int = 0,
            timestamp: Double = 0) {
        
        self.itemId = itemId
        self.username = username
        self.userImageUrl = userImageUrl
        self.imageUrl = imageUrl
        self.text = text
        self.unreadComments = unreadComments
        self.timestamp = timestamp
    }
    
    func loadMedia() {
        
        for med in self.media {
            
            if (med.url != "" && med.image.size.width < 1) {
                                
                cancellableSet.insert(
                    med.didChange.sink(receiveValue: { [weak self] _ in
                        guard let self = self else { return }
                        
//                        print("feedDataItem got change: \(med.image.size.width)")
                        
                        self.objectWillChange.send()
                        self.didChange.send()
                        
                    })
                )
//                print("load image \(med.url) \(med.width) \(med.height)")

                med.loadImage()
            }
            
        }
        
    }
    
    
    static func == (lhs: FeedDataItem, rhs: FeedDataItem) -> Bool {
        return lhs.itemId == rhs.itemId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(itemId)
    }
    
}
