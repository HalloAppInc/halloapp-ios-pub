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
        let removal = AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
  
        return .asymmetric(insertion: insertion, removal: removal)
    }
    
    static var moveAndFadeReverse: AnyTransition {
        let insertion = AnyTransition.move(edge: .leading)
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
            
            ZStack {

                if (homeRouteData.homePage == "commenting") {
                    Commenting(feedData, homeRouteData.getItem(), contacts )
                        .zIndex(2.0)
           
                        .transition(.move(edge: .trailing))
//                        .animation(Animation.easeInOut(duration: 0.3).delay(0.1))
                        .animation(.spring())
                }

                if (homeRouteData.homePage == "feed" || homeRouteData.homePage == "commenting") {
                    FeedRouter(feedData: feedData, contacts: contacts)
                        .environmentObject(FeedRouterData())
    //                    .opacity((homeRouteData.homePage == "feed" || homeRouteData.homePage == "commenting") ? 1.0 : 0.0)
                        .zIndex((homeRouteData.homePage == "feed" || homeRouteData.homePage == "commenting") ? 1.0 : 0.0)
                        .offset(x: homeRouteData.homePage == "commenting" ? -1*UIScreen.main.bounds.size.width : 0.0, y: 0.0)
                        
//                        .animation(Animation.easeInOut(duration: 0.3).delay(0.1))
                        .animation(.spring())
                        
                }
                    
                else if (homeRouteData.homePage == "messaging") {
                    
//                    PickerWrapper()
                    Messaging(contacts: contacts)
    //                    .opacity(homeRouteData.homePage == "messaging" ? 1.0 : 0.0)
                        .zIndex(homeRouteData.homePage == "messaging" ? 1.0 : 0.0)
                }

                else if (homeRouteData.homePage == "profile") {
                    Profile(feedData: feedData)
    //                    .opacity(homeRouteData.homePage == "profile" ? 1.0 : 0.0)
                        .zIndex(homeRouteData.homePage == "profile" ? 1.0 : 0.0)
                }

            }



//            if (homeRouteData.homePage == "feed") {
////                Feed(feedData: feedData, contacts: contacts)
//                FeedRouter(feedData: feedData, contacts: contacts)
//                    .environmentObject(FeedRouterData())
//                .animation(.easeInOut) // spring does not seem to work
//                .transition(.moveAndFadeReverse)
//
//            } else if (homeRouteData.homePage == "back-to-feed") {
//                Feed(feedData: feedData, contacts: contacts)
//                    .animation(.easeInOut)
//                    .transition(.move(edge: .leading))
//            } else if homeRouteData.homePage == "messaging" {
//
//                Messaging(contacts: contacts)
//
//            } else if homeRouteData.homePage == "profile" {
//                Profile(feedData: feedData)
//            } else if homeRouteData.homePage == "postText" {
//                PostText(feedData: feedData)
//            } else if homeRouteData.homePage == "postVideo" {
//                PickerWrapper()
//            } else if homeRouteData.homePage == "commenting" {
//                Commenting()
//                    .animation(.easeInOut) // spring does not seem to work
//                    .transition(.moveAndFade)
//            }
            

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
