//
//  CommentSubCell.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct CommentSubCell: View {
    
    var comment: FeedComment
    @Binding var scroll: String
    
    @Binding var replyTo: String
    @Binding var replyToName: String
    @Binding var msgToSend: String
    
    @ObservedObject var contacts: Contacts
    
    @State private var UserImage = Image(systemName: "nosign")
    
    var body: some View {
      
        VStack(spacing: 0) {
            
            HStack() {

                VStack (spacing: 0) {
                    Button(action: {
                        self.scroll = "0"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.scroll = ""
                        }
                    }) {
                       
                        Image(systemName: "circle.fill")
                            .resizable()

                            .scaledToFit()

                            .clipShape(Circle())
                            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 142/255))

                            .frame(width: 30, height: 30, alignment: .center)
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
  
                    }
                    
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    HStack() {
                        
                        Text(self.contacts.getName(phone: comment.username))
                            .font(.system(size: 14, weight: .bold))
                        
                        +
                        
                        Text("   \(comment.text)")
                            .font(.system(size: 15, weight: .regular))
                        
                        Spacer()
                    }
                    HStack() {
                        Text(Utils().timeForm(dateStr: String(comment.timestamp)))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.gray)
                        
                        
                        Button(action: {
                            
                            self.replyTo = self.comment.id
                            self.replyToName = self.contacts.getName(phone: self.comment.username)
                            self.msgToSend = "@\(self.replyToName) "
                            
                            
                        }) {
                            Text("Reply")
                                .font(.system(size: 13, weight: .bold))
                                .padding(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 20))
                                .foregroundColor(Color.gray)

                        }
                        
                        Spacer()
                        
                    }
                    .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    
                }
                
                Spacer()


            }
            
            
            Spacer()
        }
      
        .padding(EdgeInsets(top: 5, leading: self.comment.parentCommentId == "" ? 0 : 20, bottom: 10, trailing: 0))
        
    }
    

}

