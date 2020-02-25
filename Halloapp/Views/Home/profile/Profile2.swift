//
//  Contacts.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Profile2: View {
    
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var authRouteData: AuthRouteData
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @ObservedObject var feedData: FeedData
    @ObservedObject var contacts: Contacts
    
    @State var msgToSend = ""
    
    @State var showMoreActions = false
    
    @State var showSheet = false
    @State var showImagePicker = false
    @State private var showPostText = false // ?
    @State var showSettings = false
    
    @State private var cameraMode = "library"
    
    @State private var pickedImages: [FeedMedia] = []
    
    @State private var UserImage = Image(systemName: "nosign")
    @State private var pickedUIImage: UIImage = UIImage(systemName: "nosign")!
    @State private var imageUrl: String = ""

    @State private var pickerStatus: String = ""
    
    @State private var uploadStatus: String = ""
    
    @State private var imageGetUrl: String = ""
    @State private var imagePutUrl: String = ""
    
    
    @State private var showMessages = false

    @State private var lastClickedComment = ""
    
    @State private var scroll: String = ""
    
    @State private var pageNum: Int = 0
    
    
    var body: some View {
        
        return VStack() {
            
    
            HStack {
                Spacer()
                VStack(spacing: 0) {

                    Button(action: {
//                                self.showMoreActions = true
                    }) {
                        Image(systemName: "circle.fill")
                            .resizable()

                            .scaledToFit()
                            .foregroundColor(Color(red: 192/255, green: 192/255, blue: 192/255))
                            .clipShape(Circle())

                            .frame(width: 50, height: 50, alignment: .center)
                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

                    }

                    Text("\(userData.phone)")
                }
            }
            
            
            WFeedList(
                isOnProfilePage: true,
                items: self.feedData.feedDataItems,
                showSheet: $showSheet,
                showMessages: $showMessages,
                lastClickedComment: $lastClickedComment,
                scroll: $scroll,
                pageNum: $pageNum,
                homeRouteData: homeRouteData,
                contacts: contacts,
                paging: { num in
//                   print("pagenum: \(num)")
                },
                getItemMedia: { itemId in
                    self.feedData.getItemMedia(itemId)
                },
                removeItemMedia: { itemId in
                },
                setItemCellHeight: { itemId, cellHeight in
                    self.feedData.setItemCellHeight(itemId, cellHeight)
                }
            )
            
        }
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
        
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 80 : 100),
            alignment: .top
        )
                        
        .overlay(
            HStack() {
                
                VStack(spacing: 0) {
                    
                    HStack() {
                        Text("Profile")
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
                              Image(systemName: "person.crop.square.fill")
                                  .font(Font.title.weight(.regular))
                                  .foregroundColor(Color.black)
                            }
                            .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 18))

                            Button(action: {
                                self.showSettings = true
                                self.showSheet = true
                            }) {
                              Image(systemName: "gear")
                                .font(Font.title.weight(.regular))
                                  .foregroundColor(Color.black)
                            }
                            .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 25))
                          
                        }.padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                    

                    
                    
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
               
                
            }
            .padding(EdgeInsets(top: UIScreen.main.bounds.height < 812 ? 5 : 25, leading: 0, bottom: 0, trailing: 0))
            .background(Color.clear),
            alignment: .top
        )
            
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 60 : 85),
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
        
            
        .actionSheet(isPresented: self.$showMoreActions) {
            ActionSheet(
                title: Text(""),
                buttons: [
                    .default(Text("Photo Library"), action: {
                    
                        self.cameraMode = "library"
                        self.showImagePicker = true
                        self.showSheet = true
                        self.showMoreActions = false
                        
                        
                    }),
                    .default(Text("Camera"), action: {
                        self.cameraMode = "camera"
                        self.showImagePicker = true
                        self.showSheet = true
                        self.showMoreActions = false
                        
                        
                    }),
                    .destructive(Text("Cancel"), action: {
                        self.showMoreActions = false
                    })
                ]
            )
        }
    }
}

//struct Profile_Previews: PreviewProvider {
//    static var previews: some View {
//        Profile(feedData: FeedData(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
//            .environmentObject(AuthRouteData())
//            .environmentObject(UserData())
//   
//    }
//}
