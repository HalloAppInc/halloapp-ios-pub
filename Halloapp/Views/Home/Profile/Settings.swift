//
//  Settings.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import MessageUI

struct Settings: View {
    @EnvironmentObject var mainViewController: MainViewController

    private let userData = AppContext.shared.userData

    var onDismiss: () -> ()
    
    @State var result: Result<MFMailComposeResult, Error>? = nil
    @State var isShowingMailView = false
    
    @State private var isButtonVisible = true

    @State var localCompress: Float = 0.4
    
    var body: some View {
        
        DispatchQueue.main.async {
            self.localCompress = self.userData.compressionQuality
        }
        
        return VStack() {
            HStack() {
                Spacer()
                Button(action: {
                    self.onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .padding()
                }
            }
            
//            HStack() {
//                Button(action: {
//                    self.userData.resyncContacts()
//                    self.onDismiss()
//                }) {
//                    Text("Re-Sync Contacts")
//                        .padding(10)
//                        .background(Color.blue)
//                        .foregroundColor(.white)
//                        .cornerRadius(20)
//                }
//                .padding(.top, 100)
//            }
            
//            Button(action: {
//                self.userData.hostName = "s-test.halloapp.net"
//            }) {
//                Text("Switch To Test Network")
//                    .padding(10)
//                    .background(Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(20)
//                    .shadow(radius: 2)
//            }
//            .padding(.top, 100)
            
         

            Text("Version \(Utils().appVersion())")
            Text("\(self.userData.hostName)")

            Spacer()
            
            Button(action: {
                self.userData.logout()
                self.mainViewController.selectFeedTab()
                
            }) {
                Text("Log out")
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
            }
            .padding(.top, 100)
            
            
            Spacer()
            
            Button(action: {
                self.isShowingMailView.toggle()
            }) {
                Text("Send Logs")
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
            }
            .padding(.top, 100)
            
            Spacer()

        }
        
//        .disabled(!MFMailComposeViewController.canSendMail())
        .sheet(isPresented: self.$isShowingMailView) {
            MailView(result: self.$result)
        }
    }
}
