//
//  Feed.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/26/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

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
    @State private var showMessages = false
    
    @State private var UserImage = Image(systemName: "nosign")
    @State private var pickedUIImage: UIImage = UIImage(systemName: "nosign")!
    @State private var imageUrl: String = ""

    @State private var pickerStatus: String = ""
    
    @EnvironmentObject var metaData: MetaData
    
    @State private var detailsPage = ""
    
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

                                        Text(Utils().timeForm(dateStr: String(item.timestamp)))
                                            .foregroundColor(Color.gray)
                                    }

                                    Spacer()

                                    Button(action: {
                                        self.showMiscActions = true

                                    }) {
                                        Image(systemName: "ellipsis")
                                            .font(Font.title.weight(.regular))
                                            .foregroundColor(Color.gray)
                                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 25))
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
                               
                                
                                HStack() {
                                    Text(item.text)
                                        .font(.system(size: 16, weight: .light))
                                    Spacer()
                                }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
                                
                                Divider()

                                
                                HStack {
                                   
 
                                        Button(action: {
                                            self.showMessages = true
                                            self.showSheet = true
//                                            self.feedRouterData.gotoPage(page: "commenting")

                                        }) {
                                            HStack {
                                                 Image(systemName: "message")
                                                     .font(.system(size: 20, weight: .regular))
                                                     .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                 Text("Comments")
                                            }
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
                                     }

                                }
                                .foregroundColor(Color.black)
                                .padding(EdgeInsets(top: 20, leading: 35, bottom: 20, trailing: 35))
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
                
                Text("home")
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
                            callback: {
                       
        //                                self.feedData.postText(self.userData.phone, "", self.imageUrl)
        //                                self.pickerStatus = "success"
        //                                self.imageUrl = ""
                                
        //                                self.showPostText = true
                                
                                
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
                    self.showPostText = false
                    
                })
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


