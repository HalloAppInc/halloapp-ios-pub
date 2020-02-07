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
    
    @ObservedObject var feedData: FeedData
    
    @State var msgToSend = ""
    
    @State var showMoreActions = false
    
    @State var showSheet = false
    @State var showImagePicker = false
    @State private var showPostText = false // ?
    @State var showSettings = false
    
    @State private var cameraMode = "library"
    
    @State private var UserImage = Image(systemName: "nosign")
    @State private var pickedUIImage: UIImage = UIImage(systemName: "nosign")!
    @State private var imageUrl: String = ""

    @State private var pickerStatus: String = ""
    
    @State private var uploadStatus: String = ""
    
    @State private var imageGetUrl: String = ""
    @State private var imagePutUrl: String = ""
    
    
    
    var body: some View {
        
        return VStack(spacing: 0) {
            
            List() {
                
                /*
                 crash alert: "precondition failure: invalid value type for attribute"
                 this crash might happen when scrolling up and down the List, a strange
                 workaround is to wrap a VStack inside List
                */
                VStack(spacing: 0) {
                    
                    Divider()
                        .frame(height: UIScreen.main.bounds.height < 812 ? 80 : 100)
                        .hidden()
                    
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

                        
                        Spacer()
                    }
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    
                    if (self.feedData.feedDataItems.count == 0) {
                        LoadingTimer()
                    } else {
                        ForEach(self.feedData.feedDataItems) { item in
                            
                            if item.username == self.userData.phone {
                            
                                VStack(spacing: 0) {
                                                          
                                    
                                    if item.media.count > 0 {
                                        
                                        Carousel(item, item.mediaHeight)
                                           
                                    } else {
                                        Divider()
                                            .frame(height: 10)
                                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                                            .hidden()
                                    }
                                    
//                                    if (item.imageUrl != "") {
//
//                                        Image(uiImage: item.image)
//
//                                            .resizable()
//                                            .aspectRatio(item.image.size, contentMode: .fit)
//                                            .background(Color.gray)
//                                            .cornerRadius(10)
//                                            .padding(EdgeInsets(top: 10, leading: 10, bottom: 15, trailing: 10))
//                                            
//                                    } else {
//                                        Divider()
//                                            .frame(height: 10)
//                                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
//                                            .hidden()
//                                    }
                                   
                //                                Text(String(item.imageUrl))
                                    
                                    HStack() {
                                        Text(item.text)
                                            .font(.system(size: 16, weight: .light))
                                        Spacer()
                                    }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
                                    
                                    Divider()

                                    
                                    HStack {
                                       

                                            Button(action: {
                //                                            self.showComments = true
                //                                            self.showSheet = true
                                                
                //                                            self.feedRouterData.gotoPage(page: "commenting")

                                            }) {
                                                HStack {

                                                    Image(systemName: "circle.fill")
                                                        .resizable()
                                                    
                                                        .scaledToFit()
                                                        .foregroundColor(Color(red: 192/255, green: 192/255, blue: 192/255))
                                                        .clipShape(Circle())

                                                        .frame(width: 25, height: 25, alignment: .center)
                                                        
                                                    
                                                     Text("Add a comment or tag a friend...")
                                                        .foregroundColor(Color.gray)
                                                }
                                             }
                               
                                            

                                        Spacer()

                                    }
                                    .foregroundColor(Color.black)
                                    .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 35))
                                    .buttonStyle(BorderlessButtonStyle())
                                    
                                }
                                    
                                .background(Color.white)
                                .cornerRadius(10)
                                .shadow(color: Color(red: 220/255, green: 220/255, blue: 220/255), radius: 5)

                                .padding(EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0))
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            
                            }
                                
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
            

//                QGrid(feedData.feedDataItems.filter({
//                    return $0.username == self.userData.phone
//                }),
//                      columns: 3,
//                      columnsInLandscape: 4,
//                      vSpacing: 5,
//                      hSpacing: 5,
//                      vPadding: 0,
//                      hPadding: 0) { item in
//                        GridCell(item: item, phone: self.userData.phone)
//                    }
           
            Spacer()
            
        }
        .background(Color.red)
//        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
            
            } else if (self.showSettings) {

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

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        Profile(feedData: FeedData(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
   
    }
}
