//
//  Feed.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/26/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct Feed: View {
    
    @EnvironmentObject var feedRouterData: FeedRouterData
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    @EnvironmentObject var userData: UserData

    @ObservedObject var feedData: FeedData
    @ObservedObject var contacts: Contacts
    
    @State private var showSheet = false
    
    @State private var showMediaPicker = false
    @State private var showPostMedia = false
    
    @State private var showImagePicker = false
    @State private var showNotifications = false
    @State private var showPostText = false

    
    @State private var isJustText = true

    @State private var showMoreActions = false

    @State private var showNetworkAlert = false
    @State private var postId = ""
    @State private var username = ""
    @State private var showMessages = false
    
    @State private var pickedImages: [FeedMedia] = []
    
   

    
    @EnvironmentObject var metaData: MetaData
    
    @State private var detailsPage = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State private var commentClickable = true
    @State private var lastClickedComment = ""
    
    var body: some View {
        
        return VStack() {
            
            List() {
                
                /*
                 crash alert: "precondition failure: invalid value type for attribute"
                 this crash might happen when scrolling up and down the List, a strange
                 workaround is to wrap a VStack inside List
                */
                VStack(spacing: 0) {
                    
                    Divider()
                        .frame(height: UIScreen.main.bounds.height < 812 ? 40 : 70)
                        .hidden()
                    
                    if (self.feedData.feedDataItems.count == 0) {
                        LoadingTimer()
                    } else {
                        ForEach(self.feedData.feedDataItems) { item in
                            
                            VStack(spacing: 0) {
                                
                                HStack() {

                                    HStack() {

                                        Image(uiImage: UIImage())
                                            .resizable()

                                            .scaledToFit()
                                            .background(Color(red: 192/255, green: 192/255, blue: 192/255))
                                            .clipShape(Circle())

                                            .frame(width: 30, height: 30, alignment: .center)
                                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))

                                        Text(self.contacts.getName(phone: item.username))
                                            .font(.system(size: 14, weight: .regular))

 
                                    }

                                    Spacer()

                                    Button(action: {
//                                        self.showMiscActions = true

                                    }) {
//                                        Image(systemName: "ellipsis")
//                                            .font(Font.title.weight(.regular))
//                                            .foregroundColor(Color.gray)
//                                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 25))
                                        Text(Utils().timeForm(dateStr: String(item.timestamp)))
                                             .foregroundColor(Color.gray)
                                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 15))
                                    }
                                    
                                }
                                .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                                .buttonStyle(BorderlessButtonStyle())
                  
                                
                                if item.media.count > 0 {
                               
                                    MediaSlider(item, item.mediaHeight)
                                        
                                } else {
                                    Divider()
                                        .frame(height: 10)
                                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                                        .hidden()
                                }
                               
//                                Text(String(item.imageUrl))
                                
                                HStack() {
                                    Text(item.text)
                                        .font(.system(size: 16, weight: .light))
                                    Spacer()
                                }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
                                
                                Divider()

                                
                                HStack {
                                    
                                        Button(action: {
                                            
                                            if !self.homeRouteData.isGoingBack ||
                                                self.homeRouteData.lastClickedComment == item.itemId {
   
                                                self.lastClickedComment = item.itemId
                                                
                                                self.homeRouteData.setItem(value: item)
                                                self.homeRouteData.gotoPage(page: "commenting")
                                            }
                                          
                                        }) {
                                            HStack {
                                                 Image(systemName: "message")
                                                     .font(.system(size: 20, weight: .regular))
                                                     .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                    
                                                Text("Comment")
                                                    
                                                if (item.unreadComments > 0) {
                                                    Image(systemName: "circle.fill")
                                                        .resizable()

                                                        .scaledToFit()
                                                        .foregroundColor(Color.green)
                                                        .clipShape(Circle())
                                                        
                                                        .frame(width: 10, height: 10, alignment: .center)
                                                        .padding(EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 0))
                                                    
                                                }
                                            }
                                            // careful on padding, greater than 15 on sides wraps on smaller phones
                                            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
//                                            .cornerRadius(10)
//                                            .border((self.lastClickedComment == item.itemId) ? Color.red : Color.blue)
//
                                         }
                           
                                        
                                    Spacer()

                                    Button(action: {
                                        
                                        self.showMessages = true
                                        self.showSheet = true

                                     }) {
                                        HStack {
                                             Image(systemName: "envelope")
                                                 .font(.system(size: 20, weight: .regular))
                                                 .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                
                                             Text("Message")
                                        }
                                        .padding(EdgeInsets(top: 10, leading: 25, bottom: 10, trailing: 25))
                                        
                                     }

                                }
                                .foregroundColor(Color.black)
                                .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
                                .buttonStyle(BorderlessButtonStyle())
                                
                            }
                                
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: Color(red: 220/255, green: 220/255, blue: 220/255), radius: 5)

                            .padding(EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0))
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            

                        }

                    }
                    Divider()
                        .frame(height: 100)
                        .hidden()
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            }
        
            .onAppear {
                
                UITableViewCell.appearance().selectionStyle = .none
                UITableView.appearance().backgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 1)
                UITableViewCell.appearance().backgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 1)
                UITableView.appearance().separatorStyle = .none
                
                UITableView.appearance().showsVerticalScrollIndicator = false // mainly so transitions won't show it
                
            }
            
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
                
                
                if (self.feedData.isConnecting) {
                    Text("connecting...")
                        .font(.custom("Arial", size: 16))
                        .foregroundColor(Color.green)
                }
                
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
                            if (self.feedData.isConnecting) {
                                self.showNetworkAlert = true
                            } else {
                                self.showMoreActions = true
                            }
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
                            pickedImages: self.$pickedImages,
                            goToPostMedia: {
                                Utils().requestMultipleUploadUrl(xmppStream: self.feedData.xmppController.xmppStream, num: self.pickedImages.count)
                            }
                )
                
            } else if (self.showNotifications) {
                Notifications(onDismiss: {
                    self.showNotifications = false
                    self.showSheet = false
                })
            } else if (self.showPostText) {
                
                PostMedia(
                    feedData: self.feedData,
                    pickedImages: self.pickedImages,
                    onDismiss: {
                        
                        self.pickedImages.removeAll()
                        
                        self.showSheet = false
                        self.showPostText = false
                    }
                )
                .environmentObject(self.homeRouteData)
                
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
                    .default(Text("Photo Library"), action: {
                          self.isJustText = false
                          self.homeRouteData.gotoPage(page: "media")
                    }),
                    .default(Text("Camera"), action: {
                        self.isJustText = false
        
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
        .alert(isPresented: $showNetworkAlert) {
            Alert(title: Text("Couldn't connect to Halloapp"), message: Text("We'll keep trying, but there may be a problem with your connection"), dismissButton: .default(Text("Ok")))
        }


    }
    
}

