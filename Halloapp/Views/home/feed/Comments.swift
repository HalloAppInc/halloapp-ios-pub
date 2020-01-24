//
//  Comments.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Comments: View {
    @ObservedObject var feedData: FeedData
    @Binding var postId: String
    @Binding var username: String
    @EnvironmentObject var userData: UserData
    
    var onDismiss: () -> ()
    
    @State var msgToSend = ""
    
    @State private var text: String = "adsfasdfsf"
    
    var body: some View {
        VStack() {
            /* header */
            HStack() {
                Spacer()
                Button(action: {
                    self.onDismiss()
                    
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.black)
                        .padding()
                }
            }
            Spacer()
            
            ForEach(self.feedData.feedCommentItems.reversed()) { item in
                if item.feedItemId  == self.postId {
                    VStack(spacing: 0) {
                        HStack() {
                            Text(item.username + " -> " + item.text)
                                .font(.system(size: 16, weight: .light))
                            Spacer()
                        }.padding(EdgeInsets(top: 0, leading: 20, bottom: 15, trailing: 20))
                        Divider()
                    }
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color(red: 220/255, green: 220/255, blue: 220/255), radius: 5)

                    .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            
//            WUICollectionView()
//                .background(Color.red)
            
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
//                        self.feedData.postComment(self.postId, self.username, self.msgToSend)
                        self.msgToSend = ""
                    }

                }) {
                    Image(systemName: "paperplane.fill")
                        .imageScale(.large)
                        .foregroundColor(Color.blue)
                    Text("SEND")

                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
       
                }
            }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
  
            
            Spacer()

        }
    }
}
