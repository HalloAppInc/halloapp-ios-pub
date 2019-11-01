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

                Button(action: {
                    self.homeRouteData.gotoPage(page: "feed")
                }) {
                    Image(systemName: "house")
                        .imageScale(.large)
                        .foregroundColor(homeRouteData.homePage == "feed" ? Color.blue : Color.white)
                }.padding()
                Spacer()
                Button(action: {
                    self.homeRouteData.gotoPage(page: "messaging")
                }) {
                    Image(systemName: "bookmark")
                        .imageScale(.large)
                        .foregroundColor(homeRouteData.homePage == "messaging" ? Color.blue : Color.white)
                }.padding()
                Spacer()
                Button(action: {
                    self.homeRouteData.gotoPage(page: "profile")
                }) {
                    Image(systemName: "person.crop.circle")
                        .imageScale(.large)
                        .foregroundColor(homeRouteData.homePage == "profile" ? Color.blue : Color.white)
                }.padding()


            }
            .padding(.leading, 45)
            .padding(.trailing, 45)
            .background(Color(red: 64/255, green: 224/255, blue: 208/255))
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
