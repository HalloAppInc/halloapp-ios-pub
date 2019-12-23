//
//  Comments.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Comments: View {
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
            
            WUICollectionView()
                .background(Color.red)
            
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
//                         self.feedData.sendMessage(text: self.msgToSend)
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
