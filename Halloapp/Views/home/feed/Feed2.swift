//
//  Feed2.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct Feed2: View {
    
    @EnvironmentObject var feedRouterData: FeedRouterData
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    @EnvironmentObject var userData: UserData

    @ObservedObject var feedData: FeedData
    @ObservedObject var contacts: Contacts
    
    @State private var items: [FeedDataItem] = []
    
    @State private var showSheet = false
    
    @State private var showMediaPicker = false
    @State private var showPostMedia = false
    
    @State private var showImagePicker = false
    @State private var showNotifications = false
    @State private var showPostText = false
    @State private var cameraMode = "library"
    
    @State private var isJustText = true

    @State private var showMoreActions = false

    @State private var showMiscActions = false
    @State private var postId = ""
    @State private var username = ""
    @State private var showMessages = false
    
    @State private var UserImage = Image(systemName: "nosign")
    @State private var pickedUIImage: UIImage = UIImage(systemName: "nosign")!
    @State private var imageUrl: String = ""

    @State private var pickerStatus: String = ""
    
    @State private var uploadStatus: String = ""
    
    @State private var imageGetUrl: String = ""
    @State private var imagePutUrl: String = ""
    
    @State private var scroll: String = ""
    
    @EnvironmentObject var metaData: MetaData
    
    @State private var detailsPage = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State private var commentClickable = true
    @State private var lastClickedComment = ""
    
    init(feedData: FeedData, contacts: Contacts) {
        
        self.feedData = feedData
        self.contacts = contacts
        
        self._items = State(initialValue: self.feedData.feedDataItems)
            
    }
    
    var body: some View {
        
        DispatchQueue.main.async {
            
            
            
//            print("insert listener")
            self.cancellableSet.insert(

                self.feedData.xmppController.didGetUploadUrl.sink(receiveValue: { iq in
                    
                    (self.imageGetUrl, self.imagePutUrl) = Utils().parseMediaUrl(iq)
                    
                })

            )
        }

        return VStack() {
            
            WFeedList(
                items: $items,
                showSheet: $showSheet,
                showMessages: $showMessages,
                lastClickedComment: $lastClickedComment,
                scroll: $scroll,
                contacts: contacts)
                .background(Color.red)
            
        }
        
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
            
            
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 76 : 96),
                alignment: .top
        )
        .overlay(
            HStack() {
                
                Text("Home")
                    .font(.custom("Arial", size: 36))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                
//                Text(String(self.metaData.isOffline))
                
                Spacer()

                ZStack() {
                    HStack {
                        
                        Button(action: {
                            self.showNotifications = true
                            self.showSheet = true
                        }) {
                            Image(systemName: "bell")
                                .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)
                        }
                        .padding()
                        .padding(.trailing, 0)
                        
                        
                        Button(action: {
                            self.showMoreActions = true
                        }) {
                            Image(systemName: "plus")
                                .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)

                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 25))

                        }
                        
                    }
                }
               
                
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
        
            if (self.showImagePicker) {

                ImagePicker(showPostText: self.$showPostText,
                            showSheet: self.$showSheet,
                            showImagePicker: self.$showImagePicker,
                            cameraMode: self.$cameraMode,
                            pickedImage: self.$UserImage,
                            pickedUIImage: self.$pickedUIImage,
                            imageUrl: self.$imageUrl,
                            pickerStatus: self.$pickerStatus,
                            uploadStatus: self.$uploadStatus,
                            imageGetUrl: self.$imageGetUrl,
                            imagePutUrl: self.$imagePutUrl,
                            requestUrl: {
                                Utils().requestUploadUrl(xmppStream: self.feedData.xmppController.xmppStream)
                            }
                )
                
            } else if (self.showNotifications) {
                Notifications(onDismiss: {
                    self.showNotifications = false
                    self.showSheet = false
                })
            } else if (self.showPostText) {
                PostTextSheet(feedData: self.feedData,
                              imageUrl: self.$imageUrl,
                              gotImage: self.$UserImage,
                              pickedUIImage: self.$pickedUIImage,
                              pickerStatus: self.$pickerStatus,
                              isJustText: self.$isJustText,
                              onDismiss: {
                                
                                self.imageUrl = ""
                                self.UserImage = Image(systemName: "nosign")
                                self.pickedUIImage = UIImage(systemName: "nosign")!
                                
                                self.showSheet = false
                                self.showPostText = false
                                
                                
                    
                })
                .environmentObject(self.userData)

            } else {
                MessageUser(onDismiss: {
                    self.showSheet = false
                    self.showPostText = false
                    
                })
            }
        })
            
        .actionSheet(isPresented: self.$showMoreActions) {
            ActionSheet(
                title: Text(""),
                buttons: [
//                    .default(Text("Media"), action: {
//                        self.isJustText = false
//
//
//                        self.homeRouteData.gotoPage(page: "media")
//                    }),
                    .default(Text("Photo Library"), action: {
                        
                          self.isJustText = false
                        
                          self.homeRouteData.gotoPage(page: "media")
//                        self.isJustText = false
//                        self.cameraMode = "library"
//                        self.showImagePicker = true
//                        self.showSheet = true
//                        self.showMoreActions = false
                    }),
                    .default(Text("Camera"), action: {
                        self.isJustText = false
                        self.cameraMode = "camera"
                        self.showImagePicker = true
                        self.showSheet = true
                        self.showMoreActions = false
                    }),
                    .default(Text("Text"), action: {
                        self.isJustText = true
                        self.showPostText = true
                        self.showSheet = true
                        self.showMoreActions = false
                        
                    }),
                    .destructive(Text("Cancel"), action: {
                        self.showMoreActions = false
                    })
                ]
            )
        }
        .alert(isPresented: self.$showMiscActions) {
            Alert(title: Text("More actions coming soon"), message: Text(""), dismissButton: .default(Text("OK")))
        }
        .onDisappear {
            self.cancellableSet.forEach {
//                print("cancelling")
                $0.cancel()
            }
            self.cancellableSet.removeAll()
        }

    }
    
}



