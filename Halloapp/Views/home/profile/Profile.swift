//
//  Contacts.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import QGrid

struct GridCell: View {
    var item: FeedDataItem
    var phone: String

    var body: some View {
        VStack() {
     
            ZStack() {
                if (item.imageUrl != "") {
                    Image(uiImage: item.image)
                        .resizable()
                        .aspectRatio(item.image.size, contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.size.width/3 - 10, height: UIScreen.main.bounds.size.width/3 - 10)
                        .background(Color.gray)
                        .cornerRadius(5)
                        .padding(0)
                } else {
                    
                    Text(item.text)
                        .font(.system(size: 12, weight: .light))
                        .frame(width: UIScreen.main.bounds.size.width/3 - 10, height: UIScreen.main.bounds.size.width/3 - 10)
                        .aspectRatio(contentMode: .fit)
                        .background(Color.white)
                        .cornerRadius(5)
                        .padding(0)
                        .multilineTextAlignment(.leading)

                }
                
//                Button(action: {
//                }) {
//                    Image(systemName: "circle.fill")
//                        .font(.system(size: 8, weight: .regular))
//                        .foregroundColor(Color.green)
//                }
//                .offset(x: UIScreen.main.bounds.size.width/3/2 - 15, y: UIScreen.main.bounds.size.width/3/2 - 15)
                

            }
   
        }
    }
}

struct Profile: View {
    
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var authRouteData: AuthRouteData
    
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @State var msgToSend = ""
    
    @State var showSheet = false
    @State var showSettings = false
    
    @ObservedObject var feedData: FeedData
    
    var body: some View {
        return VStack {
            VStack() {
                HStack {
                    
                    Image(systemName: "circle.fill")
                        .resizable()
                    
                        .scaledToFit()
                        .foregroundColor(Color(red: 192/255, green: 192/255, blue: 192/255))
                        .clipShape(Circle())
                    
                        .frame(width: 30, height: 30, alignment: .center)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                        
                    
                    Text("\(userData.phone)")
                    
                    Button(action: {
                        self.showSheet = true
                    }) {
                        Text("edit")
                            .padding(.leading, 10)
                    }
                    
                    Spacer()
                }
                Spacer()
                
//                ScrollView() {
//                    VStack(spacing: 0) {
//                        ForEach(feedData.feedDataItems) { item in
//
//                            if (item.imageUrl != "") {
//                                Image(uiImage: item.image)
//                                    .resizable()
//                                    .frame(width: 100, height: 100)
//                                    .aspectRatio(contentMode: .fit)
//                                    .background(Color.gray)
//                                    .cornerRadius(5)
//                                    .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))
//                            }
//
//
//                        }
//
//                    }
//                    .padding(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
//                }
                

                QGrid(feedData.feedDataItems.filter({
                    return $0.username == self.userData.phone
                }),
                      columns: 3,
                      columnsInLandscape: 4,
                      vSpacing: 5,
                      hSpacing: 5,
                      vPadding: 0,
                      hPadding: 0) { item in
                        GridCell(item: item, phone: self.userData.phone)
                    }
               

                
                Spacer()
                

                
                HStack {
                    TextField("", text: $msgToSend, onEditingChanged: { (changed) in
                        if changed {
                            
                        } else {
                
                        }
                    }) {

                        if (self.msgToSend != "") {
                            // self.feedModel2.sendMessage(text: self.msgToSend)
                            self.msgToSend = ""
                        }
                    }
                    .padding(.all)
                    .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                    .cornerRadius(10)
                    
                    
                    Button(action: {
                        if (self.msgToSend != "") {
                            self.feedData.sendMessage(text: self.msgToSend)
                            self.msgToSend = ""
                        }

                    }) {
    //                    Image(systemName: "paperplane.fill")
    //                        .imageScale(.large)
    //                        .foregroundColor(Color.blue)
                        Text("SEND")

                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
           
                    }
                }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .hidden()
                

                
            }
            .padding(EdgeInsets(top: 120, leading: 10, bottom: 0, trailing: 10))

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
                
                Text("profile")
                    .font(.custom("Arial", size: 36))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                Spacer()
 
                HStack {

                    Button(action: {
                        self.showSettings = true
                      self.showSheet = true
                    }) {
                      Image(systemName: "gear")
                          .font(Font.title.weight(.regular))
                          .foregroundColor(Color.black)
                    }
                    .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 18))

                    Button(action: {
                        self.showSettings = true
                      self.showSheet = true
                    }) {
                      Image(systemName: "person.crop.square.fill")
                        .font(Font.title.weight(.regular))
                          .foregroundColor(Color.black)
                    }
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 25))
                  
                }
                
                
            }
            .padding(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
            .background(Color.clear),
            alignment: .top
        )
            
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: 85),
            alignment: .bottom
        )
        .overlay(

          Navi(),

          alignment: .bottom
        )
        .edgesIgnoringSafeArea(.all)
        
        .sheet(isPresented: self.$showSheet, content: {
            
            if (self.showSettings) {

                Settings(onDismiss: {
                    self.showSheet = false
                    
              
                    
                })
                .environmentObject(self.userData)
                .environmentObject(self.homeRouteData)
                
            } else if (self.showSheet) {

                
                
            }
        })
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        Profile(feedData: FeedData(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
   
    }
}
