//
//  Feed.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/26/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Feed: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData

    @ObservedObject var feedData: FeedData
    
    var body: some View {
        
        VStack(spacing: 0) {

            HStack {

                ZStack() {
                    Button(action: {}) {
                        Image(systemName: "camera.fill")
                            .imageScale(.large)
                            .foregroundColor(Color.blue)
                    }.padding()
                }.hidden()

                Spacer()
                Text("Halloapp")
                    .font(.custom("BanglaSangamMN-Bold", size: 20))
                    .foregroundColor(Color.white)

                Spacer()

                ZStack() {
                    Button(action: {}) {
                        Image(systemName: "camera.fill")
                            .imageScale(.large)
                            .foregroundColor(Color.blue)
                    }.padding()
                }.hidden()

            }.background(Color(red: 64/255, green: 224/255, blue: 208/255))
 
            
            VStack() {
                List() {
         
                    ForEach(feedData.feedDataItems) { item in
                        VStack(spacing: 0) {
                            HStack() {
                                HStack() {
                        
                                    Image(uiImage: item.userImage)
                                        .resizable()
                                    
                                        .scaledToFit()
                                        .clipShape(Circle())
                                        .frame(width: 50, height: 50, alignment: .center)
                       
                                    
                         
                                    Text(item.username)
                                }
                                
                                
                                Spacer()
                               
                                Text("...")
                                    .padding(.trailing, 15)
                            }
                            
                            
                            Text(item.text)
                                .padding()

                            
           
                            Image(uiImage: item.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                            
                            
                                
                        }
                        
                        .listRowInsets(EdgeInsets(top: self.feedData.firstItemId == item.id.uuidString ? 0 : 25, leading: 0, bottom: 0, trailing: 0))

                    }
                    
                }
            
            }
            
            Navi()
                     
        }

        .padding(0)
 
    
        
    }
}

struct Feed_Previews: PreviewProvider {
    static var previews: some View {
        Feed(feedData: FeedData(xmpp: XMPP(user: "xx", password: "xx")))
            .environmentObject(AuthRouteData())
            
    }
}


