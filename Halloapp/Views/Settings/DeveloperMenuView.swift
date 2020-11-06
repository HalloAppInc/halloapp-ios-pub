//
//  DeveloperMenuView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import SwiftUI

private enum MenuTitles {
    static var server: String { "Server" }
    static var userId: String { "User ID" }
    static var useDevServer: String { "Use Dev Server" }
    static var reSyncContacts: String { "Re-Sync Contacts" }
    static var resetNUXDemo: String { "Reset NUX Demo" }
    static var logOut: String { "Log Out" }
}

struct DeveloperMenuView: View {

    @State var useTestServer = MainAppContext.shared.userData.useTestServer
    @State var showRestartAlert = false

    var dismiss: (() -> ())?

    private let userData = MainAppContext.shared.userData
    private let service = MainAppContext.shared.service

    init() {
        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<DeveloperMenuView>.self ]).backgroundColor = .feedBackground
    }

    var body: some View {
        Form {
            // Connection Settings
            Section {

                // Current Server
                HStack {
                    Text(MenuTitles.server)
                    Spacer()
                    ///FIXME: this does not update in real time
                    Text(self.userData.hostName)
                }

                // User ID
                HStack {
                    Text(MenuTitles.userId)
                    Spacer()
                    Text(self.userData.userId)
                }

                // Use Dev Server?
                HStack {
                    Toggle(MenuTitles.useDevServer, isOn: $useTestServer)
                        .onReceive(Just(self.useTestServer)) { value in
                            if value != self.userData.useTestServer {
                                self.userData.useTestServer = value
                                self.service.disconnectImmediately()
                                self.service.connect()
                            }
                        }
                }
            }

            // Debug Actions
            Section {

                // Re-Sync Contacts
                Button(action: {
                    MainAppContext.shared.syncManager.requestFullSync()
                    self.dismiss?()
                }) {
                    Text(MenuTitles.reSyncContacts)
                }

                // NUX Demo
                Button(action: {
                    MainAppContext.shared.nux.startDemo()
                }) {
                    Text(MenuTitles.resetNUXDemo)
                }

                // Log Out
                Button(action: {
                    self.userData.logout()
                    self.dismiss?()
                }) {
                    Text(MenuTitles.logOut)
                }
            }
            .foregroundColor(.blue)
        }
    }
}
