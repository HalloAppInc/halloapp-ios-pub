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
    
    @State private var showImagePicker = false
    @State private var showNotifications = false
    @State private var showPostText = false
    @State private var cameraMode = "library"
    
    @State private var isJustText = true

    @State private var showMoreActions = false

    @State private var showMiscActions = false
    @State private var showComments = false
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
    
    @EnvironmentObject var metaData: MetaData
    
    @State private var detailsPage = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State private var commentClickable = true
    @State private var lastClickedComment = ""
    
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
            
            List() {
                
                /*
                 crash alert: "precondition failure: invalid value type for attribute"
                 this crash might happen when scrolling up and down the List, a strange
                 workaround is to wrap a VStack inside List
                */
                VStack(spacing: 0) {
                    
                    Divider()
                        .frame(height: 70)
                        .hidden()
                    
                    if (self.feedData.feedDataItems.count == 0) {
                        LoadingTimer()
                    } else {
                        ForEach(self.feedData.feedDataItems) { item in
                            
                            VStack(spacing: 0) {
                                
                                HStack() {

                                    HStack() {

                                        Image(uiImage: item.userImage)
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
                  
                                
                                if (item.imageUrl != "") {
                               
                                    Image(uiImage: item.image)

                                        .resizable()
                                        .aspectRatio(item.image.size, contentMode: .fit)
                                        .background(Color.gray)
                                        .cornerRadius(10)
                                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 15, trailing: 10))
                                        
                                        
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
                                            
                                            
//                                            self.showComments = true
//                                            self.showSheet = true
//                                            self.postId = item.itemId
//                                            self.username = item.username

//                                            self.showComments = true
//                                            self.showSheet = true                                            

//                                            self.feedRouterData.gotoPage(page: "commenting")
                                          
                                        }) {
                                            HStack {
                                                 Image(systemName: "message")
                                                     .font(.system(size: 20, weight: .regular))
                                                     .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                    
                                                Text("Comments")
                                                    
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
                                            .padding(EdgeInsets(top: 10, leading: 25, bottom: 10, trailing: 25))
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
                .frame(height: 96),
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

                
            } else if (self.showMessages) {
                MessageUser(onDismiss: {
                    self.showSheet = false
                    self.showMessages = false
                    
                })
            } else if (self.showComments) {
                Comments(feedData: self.feedData,
                         postId: self.$postId,
                         username: self.$username,
                         onDismiss: {
                            self.showSheet = false
                            self.showComments = false
                            self.postId = ""
                            self.username = ""
                        }).environmentObject(self.userData)
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
                        self.cameraMode = "library"
                        self.showImagePicker = true
                        self.showSheet = true
                        self.showMoreActions = false
                        
                        
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
        

        
        
    }
    
}

//struct Feed_Previews: PreviewProvider {
//    static var previews: some View {
//        Feed(feedData: FeedData(xmpp: XMPP(userData: UserData(), metaData: MetaData())), contacts: Contacts(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
//            .environmentObject(AuthRouteData())
//            .environmentObject(HomeRouteData())
//
//    }
//}


