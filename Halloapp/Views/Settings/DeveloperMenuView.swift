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
    static var useNoise: String { "Use Noise" }
    static var videoResolution: String { "Resolution" }
    static var videoBitRate: String { "BitRate" }
    static var reSyncContacts: String { "Re-Sync Contacts" }
    static var resetNUXDemo: String { "Reset NUX Demo" }
    static var logOut: String { "Log Out" }
}

struct DeveloperMenuView: View {

    @State var useTestServer = MainAppContext.shared.userData.useTestServer
    @State var useNoise = MainAppContext.shared.userData.useNoise
    @State var showRestartAlert = false

    @ObservedObject var videoSettings = VideoSettings.shared
    @State var showVideoResolutionActionSheet = false

    var dismiss: (() -> ())?

    private let userData = MainAppContext.shared.userData
    private let service = MainAppContext.shared.service

    init() {
        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<DeveloperMenuView>.self ]).backgroundColor = .feedBackground
    }

    private func incrementVideoBitrate() {
        videoSettings.bitrateMultiplier = min(videoSettings.bitrateMultiplier + 10, 100)
    }

    private func decrementVideoBitrate() {
        videoSettings.bitrateMultiplier = max(videoSettings.bitrateMultiplier - 10, 30)
    }

    var body: some View {
        Form {
            // Connection Settings
            Section(header: Text("CONNECTION")) {

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

                // Use Noise?
                HStack {
                    Toggle(MenuTitles.useNoise, isOn: $useNoise)
                        .onReceive(Just(self.useNoise)) { value in
                            if value != self.userData.useNoise && self.userData.setNoiseEnabled(value)
                            {
                                self.userData.useNoise = value
                                self.showRestartAlert = true
                            }
                        }
                }
                .alert(isPresented: $showRestartAlert) {
                    Alert(
                        title: Text("Please restart your app"),
                        message: Text("Restart the app for this setting to take effect"),
                        dismissButton: .default(Text("OK")))
                }
            }

            Section(header: Text("VIDEO")) {

                Button(action: {
                    self.showVideoResolutionActionSheet = true
                }) {
                    HStack {
                        Text(MenuTitles.videoResolution)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(videoSettings.resolution)
                            .foregroundColor(.secondary)
                    }
                }
                .actionSheet(isPresented: $showVideoResolutionActionSheet) {
                    ActionSheet(title: Text(MenuTitles.videoResolution), message: nil, buttons: [
                        .default(Text(VideoSettings.resolution(from: .preset1920x1080)), action: {
                            self.videoSettings.preset = .preset1920x1080
                        }),
                        .default(Text(VideoSettings.resolution(from: .preset1280x720)), action: {
                            self.videoSettings.preset = .preset1280x720
                        }),
                        .default(Text(VideoSettings.resolution(from: .preset960x540)), action: {
                            self.videoSettings.preset = .preset960x540
                        }),
                        .default(Text(VideoSettings.resolution(from: .preset640x480)), action: {
                            self.videoSettings.preset = .preset640x480
                        }),
                        .cancel()
                    ])
                }

                Stepper(onIncrement: incrementVideoBitrate,
                        onDecrement: decrementVideoBitrate) {
                    HStack {
                        Text(MenuTitles.videoBitRate)
                        Spacer()
                        Text(String(videoSettings.bitrateMultiplier) + "%")
                    }
                }
            }

            // Debug Actions
            Section {

                // Re-Sync Contacts
                Button(action: {
                    MainAppContext.shared.syncManager.requestSync(forceFullSync: true)
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
