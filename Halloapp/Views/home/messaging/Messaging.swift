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
        return VStack() {
            
            List() {
            
                Divider()
                    .frame(height: 100)
                    .hidden()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                
                ForEach(contacts.normalizedContacts.filter( {

                    return $0.isConnected

                } )) { (contact: NormContact) in
                
                    HStack {
                        
                        Image(systemName: "circle.fill")
                            .resizable()

                            .scaledToFit()
                            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 142/255))
                            .clipShape(Circle())

                            .frame(width: 50, height: 50, alignment: .center)
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                        
                        VStack {
                            HStack() {
                                Text(contact.name)
                                   
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                Spacer()
                            }
                            HStack() {
                                Text(contact.phone)
                                    .font(.system(size: 12, weight: .regular))
                                     .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                                    .foregroundColor(Color(red: 162/255, green: 162/255, blue: 162/255))
                                    
                                Spacer()
                            }
                        }
                        
                        Spacer()
                        

                        Button(action: {
                            self.showCameraAll = true
                            self.showSheet = true
                        }) {
                          Image(systemName: "photo")
                              .font(Font.title.weight(.regular))
                              .foregroundColor(Color(red: 192/255, green: 192/255, blue: 192/255))
                        }.padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 10))
                            
                    }.padding(EdgeInsets(top: 10, leading: 5, bottom: 0, trailing: 5))

                }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                
                if contacts.normalizedContacts.filter( {return $0.isConnected } ).count == 0 {
                    Divider()
                        .frame(height: 75)
                        .hidden()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    Text("Your contacts aren't on Hallo yet")
                }
                
                
                
                Divider()
                    .frame(height: 100)
                    .hidden()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
       
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
                .frame(height: 96),
            alignment: .top
        )
                        
        .overlay(
            HStack() {
                
                Text("messages")
                    .font(.custom("Arial", size: 36))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                Spacer()
                
                HStack {

                    if (self.contacts.idsToWhiteList.count > 0) {
                        Text(String(self.contacts.idsToWhiteList.count))
                            .font(.system(size: 8, weight: .regular))
                            .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 18))
                            .foregroundColor(Color.gray)
                    }
                    
                    Button(action: {
                        self.showCameraAll = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "camera.circle.fill")
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
            .padding(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
            .background(Color.clear), alignment: .top
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

struct Messaging_Previews: PreviewProvider {
    static var previews: some View {
        Messaging(contacts: Contacts(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
            .environmentObject(AuthRouteData())
    }
}
