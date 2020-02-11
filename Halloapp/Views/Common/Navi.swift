//
//  Navi.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Navi: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack {
                    Button(action: {
                        self.homeRouteData.gotoPage(page: "feed")
                    }) {
                       
                        Image(systemName: "house.fill")
                            .imageScale(.large)
                            .foregroundColor(homeRouteData.homePage == "feed" ? Color.black : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 7, trailing: 25))
                        
                            
                    }

                    Image(systemName: "circle")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor((homeRouteData.homePage == "feed" || homeRouteData.homePage == "back-to-feed") ? Color(red:  40/255, green:  40/255, blue:  40/255) : Color.clear)
                        .padding(0)
                    .hidden()
                }
                
                Spacer()
                
                VStack {
                    Button(action: {
                        self.homeRouteData.gotoPage(page: "messaging")
                    }) {
                        
                        Image(systemName: "envelope.fill")
                            .imageScale(.large)
                            .foregroundColor(homeRouteData.homePage == "messaging" ? Color.black : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 5, trailing: 25))
                       
                    }
                    
                    Image(systemName: "circle")
                         .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(homeRouteData.homePage == "messaging" ? Color(red: 40/255, green: 40/255, blue: 40/255) : Color.clear)
                     .padding(0)
                    .hidden()
                    
                }
                Spacer()
                VStack {
                    Button(action: {
                        self.homeRouteData.gotoPage(page: "profile")
                    }) {
                        Image(systemName: "person.fill")
                            .imageScale(.large)
                            .foregroundColor(homeRouteData.homePage == "profile" ? Color.black : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 5, trailing: 25))
                            
                    }
                    
                    Image(systemName: "circle")
                         .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(homeRouteData.homePage == "profile" ? Color(red:  40/255, green:  40/255, blue:  40/255) : Color.clear)
                     .padding(0)
                    .hidden()
                    
                }

            }
            // 30 instead of 40 on sides cause it looks better on older phones
            .padding(EdgeInsets(top: 0, leading: 30, bottom: UIScreen.main.bounds.height < 812 ? 8 : 33, trailing: 30))
            .background(Color.clear)
        }
    }
}

struct Navi_Previews: PreviewProvider {
    static var previews: some View {
        Navi()
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
    }
}
