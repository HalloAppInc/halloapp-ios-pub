//
//  Contacts.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Profile: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    
    @State var msgToSend = ""
    
    var body: some View {
        VStack {
            Spacer()

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
                        // self.feedModel2.sendMessage(text: self.msgToSend)
                        self.msgToSend = ""
                    }

                }) {
//                    Image(systemName: "paperplane.fill")
//                        .imageScale(.large)
//                        .foregroundColor(Color.blue)
                    Text("SEND")

                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
       
                }
            }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))

            
            Navi()
        }
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        Profile()
            .environmentObject(AuthRouteData())
   
    }
}
