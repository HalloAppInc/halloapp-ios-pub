//
//  Home.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

extension AnyTransition {
    static var moveAndFade: AnyTransition {
        let insertion = AnyTransition.move(edge: .trailing)
            .combined(with: .opacity)
        let removal = AnyTransition.scale
            .combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

struct HomeRouter: View {
        
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @ObservedObject var xmpp: XMPP
    @ObservedObject var contacts: Contacts
    @ObservedObject var feedData: FeedData
    
    var body: some View {
        
        VStack {
            
            
//            ZStack {
//                FeedRouter(feedData: feedData, contacts: contacts)
//                    .environmentObject(FeedRouterData())
//                    .zIndex(homeRouteData.homePage == "feed" ? 1.0 : 0.0)
//
//                Messaging(contacts: contacts)
//                    .zIndex(homeRouteData.homePage == "messaging" ? 1.0 : 0.0)
//
//                Profile(feedData: feedData)
//                    .zIndex(homeRouteData.homePage == "profile" ? 1.0 : 0.0)
//
//            }



            if (homeRouteData.homePage == "feed") {
//                Feed(feedData: feedData, contacts: contacts)
                FeedRouter(feedData: feedData, contacts: contacts)
                    .environmentObject(FeedRouterData())
            } else if (homeRouteData.homePage == "back-to-feed") {
                Feed(feedData: feedData, contacts: contacts)
                    .animation(.easeInOut)
                    .transition(.move(edge: .leading))
            } else if homeRouteData.homePage == "messaging" {

                Messaging(contacts: contacts)

            } else if homeRouteData.homePage == "profile" {
                Profile(feedData: feedData)
            } else if homeRouteData.homePage == "postText" {
                PostText(feedData: feedData)
            } else if homeRouteData.homePage == "postVideo" {
                PickerWrapper()
            } else if homeRouteData.homePage == "commenting" {
                Commenting()
                    .animation(.easeInOut) // spring does not seem to work
                    .transition(.moveAndFade)
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
