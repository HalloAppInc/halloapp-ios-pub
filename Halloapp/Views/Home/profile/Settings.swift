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
    
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    var onDismiss: () -> ()
    
    @State var result: Result<MFMailComposeResult, Error>? = nil
    @State var isShowingMailView = false
    
    @State private var isButtonVisible = true

    func appVersion() -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return ""
        }
        guard let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "Version \(version)"
        }
        return "Version \(version) (\(buildNumber))"
    }

    var body: some View {

        VStack() {
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
            
//            Button(action: {
//                self.userData.resyncContacts()
//                self.homeRouteData.gotoPage(page: "messaging")
//            }) {
//                Text("Sync Contacts Again")
//                    .padding(10)
//                    .background(Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(20)
//                    .shadow(radius: 2)
//            }
//            .padding(.top, 100)
            
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
            
            Spacer()

            Text(appVersion())
            Text("\(self.userData.hostName)")

            Button(action: {
                print("lgoging")
                self.userData.logout()
                self.homeRouteData.gotoPage(page: "feed")
                
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
            MailView(result: self.$result, logs: self.userData.logging)
        }
    }
}

//struct Settings_Previews: PreviewProvider {
//    static var previews: some View {
//        Settings()
//    }
//}
