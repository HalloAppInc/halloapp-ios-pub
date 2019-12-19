//
//  Details.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/13/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Commenting: View {
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @EnvironmentObject var feedRouterData: FeedRouterData
    
    var body: some View {
      TabView {
          Content()
              .tabItem {
                  Image(systemName: "list.dash")
                  Text("Menu")
              }

          GroupChat()
              .tabItem {
                  Image(systemName: "square.and.pencil")
                  Text("Order")
              }
      }
      .background(Color(red: 248/255, green: 248/255, blue: 248/255))
      .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

      
      .overlay(
          BlurView(style: .extraLight)
              .frame(height: 96),
          alignment: .top
      )
                      
      .overlay(
          HStack() {
              
            Button(action: {
                self.homeRouteData.gotoPage(page: "back-to-feed")
            }) {
                Image(systemName: "chevron.left")
                  .font(Font.title.weight(.regular))
                    .foregroundColor(Color.black)
                    .padding()
                

            }
            

              
              Spacer()
              
              
              HStack {

                  Button(action: {

                  }) {
                      Image(systemName: "square.and.pencil")
                        .font(Font.title.weight(.regular))
                          .foregroundColor(Color.black)
                  }
                  
                  .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 25))
                  
              }
              
          }
          .padding(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
          .background(Color.clear), alignment: .top
      )

      .overlay(
          BlurView(style: .extraLight)
              .frame(height: 85),
          alignment: .bottom
      )

  
      

    }
}

struct Commenting_Previews: PreviewProvider {
    static var previews: some View {
        Commenting()
    }
}
