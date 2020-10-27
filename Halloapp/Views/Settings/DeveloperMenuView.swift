//
//  DeveloperMenuView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct DeveloperMenuView: View {

    @State var useTestServer: Bool
    @State var useProtobuf: Bool
    @State var showRestartAlert = false
    @State var showRegistrationDemo = false

    var dismiss: (() -> ())?

    private let userData = MainAppContext.shared.userData
    private let service = MainAppContext.shared.service

    var body: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: {
                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Image("NavbarClose")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .padding()
                }
            }

            Spacer()

            Image(systemName: "hammer")
                .resizable()
                .foregroundColor(Color.secondary)
                .frame(width: 120, height: 120, alignment: .center)

            Spacer()

            VStack(alignment: .center, spacing: 24) {

                VStack(spacing: 4) {
                    Text("Server: \(self.userData.hostName)")
                        .frame(maxWidth: .infinity)

                    Text("User ID: \(self.userData.userId)")
                        .frame(maxWidth: .infinity)
                }

                Button(action: {
                    MainAppContext.shared.syncManager.requestFullSync()

                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Text("Re-Sync Contacts")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }

                Button(action: {
                    useProtobuf = !useProtobuf
                    userData.useProtobuf = useProtobuf
                    service.disconnectImmediately()
                    showRestartAlert = true
                }) {
                    Text("Use Protobuf \(self.useProtobuf ? "👍" : "👎")")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }
                .alert(isPresented: $showRestartAlert) {
                    Alert(title: Text("Please restart the app for this to take effect"))
                }

                Button(action: {
                    self.useTestServer = !self.useTestServer
                    self.userData.useTestServer = self.useTestServer
                    self.service.disconnectImmediately()
                    self.service.connect()

                }) {
                    Text("Use Dev Server \(self.useTestServer ? "👍" : "👎")")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }


                Button(action: {
                    showRegistrationDemo = true
                }) {
                    Text("Registration Demo")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }
                .sheet(isPresented: $showRegistrationDemo) {
                    RegistrationDemo() {
                        showRegistrationDemo = false
                    }
                }

                Button(action: {
                    MainAppContext.shared.nux.startDemo()
                }) {
                    Text("Reset NUX demo")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }

                Button(action: {
                    self.userData.logout()

                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Text("Log out")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }
            }
            .padding(.bottom, 32)
        }
    }
}
