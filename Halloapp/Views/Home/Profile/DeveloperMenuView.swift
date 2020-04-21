//
//  DeveloperMenuView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct DeveloperMenuView: View {

    var dismiss: (() -> ())?

    private let userData = AppContext.shared.userData
    private let xmppController = AppContext.shared.xmppController

    var body: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: {
                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Image(systemName: "xmark")
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

            VStack(alignment: .center, spacing: 32) {
                Text("Server: \(self.userData.hostName)")
                
                Button(action: {
                    AppContext.shared.syncManager.requestFullSync()

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
                    AppContext.shared.feedData.refetchEverything()

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
                    self.userData.switchToNetwork()
                    self.xmppController.xmppStream.disconnect()
                    self.xmppController.connect()

                    if self.dismiss != nil {
                        self.dismiss!()
                    }
                }) {
                    Text("Switch Network")
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

struct DeveloperMenuView_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperMenuView()
    }
}
