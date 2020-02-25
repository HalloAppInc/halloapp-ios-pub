//
//  HomeRouter.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

final class HomeRouteData: ObservableObject {

    @Published var homePage = "feed"
    @Published var isGoingBack = false
    
    public var lastClickedComment = ""
    
    public var item = FeedDataItem()
    
    public var fromPage = ""
    
    func gotoPage(page: String) {
        self.homePage = page
    }
    
    func setIsGoingBack(value: Bool) {
        self.isGoingBack = value
        
        // 1.3 is too quick, 1.4 works
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            if self.lastClickedComment == self.item.itemId { // todo: debouncing this is preferred
                self.isGoingBack = false
            }
        }
    }
    
    func setItem(value: FeedDataItem) {
        self.item = value
    }
    
    func getItem() -> FeedDataItem {
        return self.item
    }
    
}
