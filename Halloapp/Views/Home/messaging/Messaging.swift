//
//  Favorites.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Contacts

struct Messaging: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    
    @ObservedObject var contacts: Contacts
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @State var showSheet = false
    @State var showWrite = false
    @State var showCameraAll = false
       
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
                        .frame(height: UIScreen.main.bounds.height < 812 ? 70 : 100)
                        .hidden()
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    
//                    Divider()
//                        .frame(height: 100)
//                        .hidden()
                    
//                    PlayerContainerView(
//                        url: URL(string: "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8")!)
//                        .frame(width: 300, height: 100)
                        
 
                    /* id is required else it crashes every now and then */
                    ForEach(contacts.connectedContacts, id: \.id) { contact in
                    
                        HStack {

                            Image(systemName: "circle.fill")
                                .resizable()

                                .scaledToFit()
                                .foregroundColor(Color(red: 142/255, green: 142/255, blue: 142/255))
                                .clipShape(Circle())

                                .frame(width: 50, height: 50, alignment: .center)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                            VStack {
                                HStack() {
                                    Text(contact.name)

                                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    Spacer()
                                }
                                HStack() {
                                    Text(contact.normPhone != "" ? contact.normPhone : contact.phone)
                                        .font(.system(size: 12, weight: .regular))
                                         .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                                        .foregroundColor(Color(red: 162/255, green: 162/255, blue: 162/255))

                                    Spacer()
                                }
                            }

                            Spacer()


    //                        Button(action: {
    //                            self.showCameraAll = true
    //                            self.showSheet = true
    //                        }) {
    //                          Image(systemName: "photo")
    //                              .font(Font.title.weight(.regular))
    //                              .foregroundColor(Color(red: 192/255, green: 192/255, blue: 192/255))
    //                        }.padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 10))

                        }.padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5))


                    }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    /* todo: this is crashing when the contacts list is empty, filter and then rendering might be too
                     intensive for the ui */
    //                if contacts.normalizedContacts.filter( {return $0.isConnected } ).isEmpty {
    //                    Divider()
    //                        .frame(height: 75)
    //                        .hidden()
    //                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    //                    Text("Your contacts aren't on Hallo yet")
    //                }
                    
                    
                    
                    Divider()
                        .frame(height: 100)
                        .hidden()
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
       
            }
            
            .onAppear {
                UITableView.appearance().backgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 1)
                UITableViewCell.appearance().backgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 1)
                UITableView.appearance().separatorStyle = .none
            }
            .background(Color(red: 248/255, green: 248/255, blue: 248/255))
        

        }
        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        
            
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 76 : 96),
            alignment: .top
        )
                        
        .overlay(
            HStack() {
                
                Text("Messages")
                    .font(.custom("Arial", size: 36))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                Spacer()
                
                HStack {
                    
                    Button(action: {
                        self.showCameraAll = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.black)
                    }
  
                    .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 18))
                    
                    
                    Button(action: {
                        self.showWrite = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                          .font(Font.title.weight(.regular))
                            .foregroundColor(Color.black)
                    }
                    
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 25))
                    
                }
                
            }
            .padding(EdgeInsets(top: UIScreen.main.bounds.height < 812 ? 5 : 25, leading: 0, bottom: 0, trailing: 0))
            .background(Color.clear), alignment: .top
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
            
            if (self.showCameraAll) {

                  MessageUser(onDismiss: {
                    
                      self.showSheet = false
                      
                
                      
                  })
                
            } else if (self.showWrite) {
                  MessageUser(onDismiss: {
                    
                      self.showSheet = false
                      
                
                      
                  })
            }
        })
        
    }
    
}

//struct Messaging_Previews: PreviewProvider {
//    static var previews: some View {
//        Messaging(contacts: Contacts(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
//            .environmentObject(AuthRouteData())
//    }
//}
