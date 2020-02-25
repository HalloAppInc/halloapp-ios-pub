//
//  FeedRouter.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/16/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI


struct FeedRouter: View {
        
    @EnvironmentObject var feedRouterData: FeedRouterData

    @ObservedObject var feedData: FeedData
    @ObservedObject var contacts: Contacts
    
    var body: some View {
        
        VStack {
            
            if (self.feedRouterData.currentPage == "feed") {
//                Feed(feedData: feedData, contacts: contacts)
                Feed2(feedData: feedData, contacts: contacts)
            } else if self.feedRouterData.currentPage == "commenting" {

            }

        }
    }
}

