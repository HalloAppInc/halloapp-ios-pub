//
//  Home.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct HomeRouter: View {
        
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @ObservedObject var xmpp: XMPP
    @ObservedObject var contacts: Contacts
    @ObservedObject var feedData: FeedData
    
    var body: some View {
        VStack {
            
            if (homeRouteData.homePage == "feed") {
                Feed(feedData: feedData, contacts: contacts)
            } else if homeRouteData.homePage == "messaging" {
                Messaging(contacts: contacts)
            } else if homeRouteData.homePage == "profile" {
                Profile(feedData: feedData)
            } else if homeRouteData.homePage == "postText" {
                PostText(feedData: feedData)
            } else if homeRouteData.homePage == "postVideo" {
                PickerWrapper()
            }

        }
    }
}

//struct HomeRouter_Previews: PreviewProvider {
//    static var previews: some View {
//        HomeRouter(
//            xmpp: XMPP(userData: UserData()),
//            contacts: Contacts(xmpp: XMPP(userData: UserData())),
//            feedData: FeedData(xmpp: XMPP(userData: UserData()))
//        )
//            .environmentObject(AuthRouteData())
//            .environmentObject(UserData())
//            
//    }
//}
