//
//  DeveloperMenuView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import SwiftUI

private enum MenuTitles {
    static var server: String { "Server" }
    static var userId: String { "User ID" }
    static var useDevServer: String { "Use Dev Server" }
    static var videoResolution: String { "Resolution" }
    static var videoBitRate: String { "BitRate" }
    static var reSyncContacts: String { "Re-Sync Contacts" }
    static var resetNUXDemo: String { "Reset NUX Demo" }
    static var startZeroZoneDemo: String { "Start Welcome Posts Demo" }
    static var clearPushNamesAndNumbers: String { "Clear Pushnames/numbers" }
    static var enableFlatComments: String {"Enable Flat Comments"}
    static var logOut: String { "Log Out" }
}

struct DeveloperMenuView: View {

    @State var useTestServer = MainAppContext.shared.coreService.useTestServer
    @State var enableFlatComments = MainAppContext.shared.feedData.enableFlatComments

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
                    Text(self.service.hostName)
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
                            if value != self.service.useTestServer {
                                (self.service as? ProtoServiceCore)?.useTestServer = value
                                self.service.disconnectImmediately()
                                self.service.connect()
                            }
                        }
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

                Button(action: {
                    MainAppContext.shared.nux.devSetStateZeroZone()
                    MainAppContext.shared.nux.startDemo()
                    MainAppContext.shared.feedData.shouldReloadView.send()
                    self.dismiss?()
                }) {
                    Text(MenuTitles.startZeroZoneDemo)
                }

                Button(action: {
                    MainAppContext.shared.contactStore.deleteAllPushNamesAndNumbers()
                    self.dismiss?()
                }) {
                    Text(MenuTitles.clearPushNamesAndNumbers)
                }

                // Enable Flat Comments
                HStack {
                    Toggle(MenuTitles.enableFlatComments, isOn: $enableFlatComments)
                        .onReceive(Just(self.enableFlatComments)) { value in
                            if value != MainAppContext.shared.feedData.enableFlatComments {
                                MainAppContext.shared.feedData.enableFlatComments = value
                            }
                        }
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
