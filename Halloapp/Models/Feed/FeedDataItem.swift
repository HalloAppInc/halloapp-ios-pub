//
//  FeedDataItem.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import SwiftUI

class FeedDataItem: Identifiable, ObservableObject, Equatable, Hashable {
    
    var id = UUID().uuidString
    
    var didChange = PassthroughSubject<Void, Never>()
    var commentsChange = PassthroughSubject<Int, Never>()
    
    var itemId: String
    
    var username: String
    var userImageUrl: String
    
    var text: String
    
    var timestamp: TimeInterval = 0
    
    var imageUrl: String
    
    @Published var media: [FeedMedia] = []
    
    @Published var mediaHeight: Int = -1
    @Published var cellHeight: Int = -1
    
    @Published var comments: [FeedComment] = []
    
    var unreadComments: Int {
        didSet {
            commentsChange.send(unreadComments)
        }
    }
    
    var numTries: Int = 0
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(   itemId: String = "",
            username: String = "",
            imageUrl: String = "",
            userImageUrl: String = "",
            text: String = "",
            unreadComments: Int = 0,
            mediaHeight: Int = -1,
            cellHeight: Int = -1,
            timestamp: TimeInterval = 0) {
        
        self.itemId = itemId
        self.username = username
        self.userImageUrl = userImageUrl
        self.imageUrl = imageUrl
        self.text = text
        self.unreadComments = unreadComments
        self.mediaHeight = mediaHeight
        self.cellHeight = cellHeight
        self.timestamp = timestamp
    }
    
    func loadMedia() {
        
        for med in self.media {
            
            if (
                    (med.type == "image" && med.image.size.width < 1) ||
                    (med.type == "video" && med.tempUrl == nil)
                ) {
            
    
                if (med.url != "" && med.numTries < 10) {
                                    
                    cancellableSet.insert(
                        med.didChange.sink(receiveValue: { [weak self] _ in
                            guard let self = self else { return }
                            
    //                        print("feedDataItem got change: \(med.image.size.width)")
                            
                            self.objectWillChange.send()
                            self.didChange.send()
                            
                        })
                    )
                    
                    med.loadImage()
                                    
                }
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
