//
//  WFeedListCell.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedListCell: View {
    
    var isOnProfilePage: Bool
    var item: FeedDataItem
    
    @Binding var showSheet: Bool
    @Binding var showMessages: Bool

    @Binding var lastClickedComment: String

    @Binding var scroll: String
    
    @ObservedObject var homeRouteData: HomeRouteData
    @ObservedObject var contacts: Contacts
    
    var body: some View {
      
        return VStack(spacing: 0) {
                
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

            if (!item.text.isEmpty) {
                HStack() {
                    Text(item.text)
                        .font(.system(size: 16, weight: .light))
                    Spacer()
                }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
            }
            
            Divider()

            
            HStack {
                
                    Button(action: {
                        
                        if !self.homeRouteData.isGoingBack ||
                            self.homeRouteData.lastClickedComment == self.item.itemId {

                            self.lastClickedComment = self.item.itemId
                            
                            self.homeRouteData.setItem(value: self.item)
                            if (self.isOnProfilePage) {
                                self.homeRouteData.fromPage = "profile"
                            }
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

                if (self.contacts.xmpp.userData.phone != item.username) {
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

            }
            .foregroundColor(Color.black)
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
            .buttonStyle(BorderlessButtonStyle())
            

        }
            
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color(red: 220/255, green: 220/255, blue: 220/255), radius: 5)
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        
    }

    
}
