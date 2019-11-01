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
                Feed(feedData: feedData)
            } else if homeRouteData.homePage == "messaging" {
                Messaging(contacts: contacts)
            } else if homeRouteData.homePage == "profile" {
                Profile()
            }

        }
    }
}

struct HomeRouter_Previews: PreviewProvider {
    static var previews: some View {
        HomeRouter(
            xmpp: XMPP(user: "xx", password: "xx"),
            contacts: Contacts(xmpp: XMPP(user: "xx", password: "xx")),
            feedData: FeedData(xmpp: XMPP(user: "xx", password: "xx"))
        )
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
            
    }
}
