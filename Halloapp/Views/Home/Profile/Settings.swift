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
            
            HStack() {
                Button(action: {
                    self.userData.resyncContacts()
                    self.onDismiss()
                }) {
                    Text("Re-Sync Contacts")
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                .padding(.top, 100)
                
            }
            
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
            
         

            Text(appVersion())
            Text("\(self.userData.hostName)")

            Spacer()
            
            VStack() {
                Text("Image Compression: \(self.localCompress)")
                
                HStack() {
                    Button(action: {
                        self.userData.compressionQuality = 0.2
                        self.localCompress = 0.2
                    }) {
                        Text("2")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }

                    Button(action: {
                        self.userData.compressionQuality = 0.3
                        self.localCompress = 0.3
                    }) {
                        Text("3")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                    Button(action: {
                        self.userData.compressionQuality = 0.4
                        self.localCompress = 0.4
                    }) {
                        Text("4")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                    Button(action: {
                        self.userData.compressionQuality = 0.5
                        self.localCompress = 0.5
                    }) {
                        Text("5")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                    Button(action: {
                        self.userData.compressionQuality = 0.6
                        self.localCompress = 0.6
                    }) {
                        Text("6")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                    Button(action: {
                        self.userData.compressionQuality = 0.7
                        self.localCompress = 0.7
                    }) {
                        Text("7")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                    Button(action: {
                        self.userData.compressionQuality = 0.8
                        self.localCompress = 0.8
                    }) {
                        Text("8")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                    
                }.padding(.top, 10)
            }
            
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
            MailView(result: self.$result, logs: self.userData.logging)
        }
    }
}
