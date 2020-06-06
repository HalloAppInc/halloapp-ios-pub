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

    var dismiss: (() -> ())?

    private let userData = MainAppContext.shared.userData
    private let xmppController = MainAppContext.shared.xmppController

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
                Text("Server: \(self.userData.hostName)")
                    .frame(maxWidth: .infinity)

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
                    MainAppContext.shared.feedData.refetchEverything()

                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Text("Refetch Feed")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }

                Button(action: {
                    self.useTestServer = !self.useTestServer
                    self.userData.useTestServer = self.useTestServer
                    self.xmppController.disconnectImmediately()
                    self.xmppController.connect()

                }) {
                    Text("Use Dev Server \(self.useTestServer ? "👍" : "👎")")
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
