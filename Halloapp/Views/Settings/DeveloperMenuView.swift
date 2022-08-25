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
    // TODO: Temporarily turn off and potentially remove
//    static var videoResolution: String { "Resolution" }
//    static var videoBitRate: String { "BitRate" }
    static var reSyncContacts: String { "Re-Sync Contacts" }
    static var resetNUXDemo: String { "Reset NUX Demo" }
    static var startZeroZoneDemo: String { "Start Welcome Posts Demo" }
    static var clearPushNamesAndNumbers: String { "Clear Pushnames/numbers" }
    static var clearHiddenSuggestedContacts: String { "Clear hidden suggested contacts" }
    static var resetFavoritesZeroState: String { "Reset Favorites Zero State" }
    static var addFavoritesNotification: String { "Add Favorites Notification" }
    static var manageWebClient: String { "Manage web client" }
    static var enableGroupChat: String { "Enable Group Chat" }
    static var enableUIKitComposer: String { "Enable UIKit Composer" }
    static var showDecryptionResults: String { "Show decryption results  ✅ ❌" }
    static var forceCompactShare: String { "Force Compact Share UI" }
    static var forcePickerShare: String { "Force Destination Picker Share UI" }
    static var resetMomentsFTUX: String { "Reset Moments FTUX" }
    static var logOut: String { "Log Out" }
}

struct DeveloperSetting {
    static var showDecryptionResults: Bool {
        get { AppContext.shared.userDefaults.bool(forKey: "showDecryptionResults", defaultValue: true) }
        set { AppContext.shared.userDefaults.set(newValue, forKey: "showDecryptionResults") }
    }
}

struct DeveloperMenuView: View {

    @State var useTestServer = MainAppContext.shared.coreService.useTestServer
    @State var enableGroupChat = AppContext.shared.userDefaults.bool(forKey: "enableGroupChat")
    @State var showDecryptionResults = DeveloperSetting.showDecryptionResults
    @State var enableUIKitComposer = AppContext.shared.userDefaults.bool(forKey: "enableUIKitComposer")
    @State var forceCompactShare = AppContext.shared.userDefaults.bool(forKey: "forceCompactShare")
    @State var forcePickerShare = AppContext.shared.userDefaults.bool(forKey: "forcePickerShare")
    @State var isShowingWebClientManager = false

    // TODO: Temporarily turn off and potentially remove
//    @ObservedObject var videoSettings = VideoSettings.shared
    @State var showVideoResolutionActionSheet = false

    var dismiss: (() -> ())?

    private let userData = MainAppContext.shared.userData
    private let service = MainAppContext.shared.service

    init() {
        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<DeveloperMenuView>.self ]).backgroundColor = .feedBackground
    }

    // TODO: Temporarily turn off and potentially remove
//    private func incrementVideoBitrate() {
//        videoSettings.bitrateMultiplier = min(videoSettings.bitrateMultiplier + 10, 100)
//    }
//
//    private func decrementVideoBitrate() {
//        videoSettings.bitrateMultiplier = max(videoSettings.bitrateMultiplier - 10, 30)
//    }

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

            // TODO: Temporarily turn off and potentially remove
//            Section(header: Text("VIDEO")) {
//
//                Button(action: {
//                    self.showVideoResolutionActionSheet = true
//                }) {
//                    HStack {
//                        Text(MenuTitles.videoResolution)
//                            .foregroundColor(.blue)
//                        Spacer()
//                        Text(videoSettings.resolution)
//                            .foregroundColor(.secondary)
//                    }
//                }
//                .actionSheet(isPresented: $showVideoResolutionActionSheet) {
//                    ActionSheet(title: Text(MenuTitles.videoResolution), message: nil, buttons: [
//                        .default(Text(VideoSettings.resolution(from: .preset1920x1080)), action: {
//                            self.videoSettings.preset = .preset1920x1080
//                        }),
//                        .default(Text(VideoSettings.resolution(from: .preset1280x720)), action: {
//                            self.videoSettings.preset = .preset1280x720
//                        }),
//                        .default(Text(VideoSettings.resolution(from: .preset960x540)), action: {
//                            self.videoSettings.preset = .preset960x540
//                        }),
//                        .default(Text(VideoSettings.resolution(from: .preset640x480)), action: {
//                            self.videoSettings.preset = .preset640x480
//                        }),
//                        .cancel()
//                    ])
//                }
//
//                Stepper(onIncrement: incrementVideoBitrate,
//                        onDecrement: decrementVideoBitrate) {
//                    HStack {
//                        Text(MenuTitles.videoBitRate)
//                        Spacer()
//                        Text(String(videoSettings.bitrateMultiplier) + "%")
//                    }
//                }
//            }

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

                // Clear hidden suggested contacts
                Button {
                    MainAppContext.shared.contactStore.resetHiddenSuggestedContacts()
                    self.dismiss?()
                } label: {
                    Text(MenuTitles.clearHiddenSuggestedContacts)
                }

                Button(action: {
                    AppContext.shared.userDefaults.set(false, forKey: "hasFavoritesModalBeenShown")
                    AppContext.shared.userDefaults.set(false, forKey: "hasFavoritesNotificationBeenSent")
                    self.dismiss?()
                }) {
                    Text(MenuTitles.resetFavoritesZeroState)
                }

                Button {
                    MainAppContext.shared.feedData.updateFavoritesPromoNotification()
                    dismiss?()
                } label: {
                    Text(MenuTitles.addFavoritesNotification)
                }
                // SwuiftUI supports a maximum of 10 subvies, add any new items to this group.
                Group {
                    Button {
                        self.isShowingWebClientManager = true
                    } label: {
                        Text(MenuTitles.manageWebClient)
                    }

                    Toggle(MenuTitles.showDecryptionResults, isOn: $showDecryptionResults)
                        .onReceive(Just(self.showDecryptionResults)) { value in
                            DeveloperSetting.showDecryptionResults = value
                        }

                    Toggle(MenuTitles.enableGroupChat, isOn: $enableGroupChat)
                        .onReceive(Just(self.enableGroupChat)) { value in
                            AppContext.shared.userDefaults.set(value, forKey: "enableGroupChat")
                        }

                    Toggle(MenuTitles.enableUIKitComposer, isOn: $enableUIKitComposer)
                        .onReceive(Just(enableUIKitComposer)) { value in
                            AppContext.shared.userDefaults.set(value, forKey: "enableUIKitComposer")
                        }

                    if enableUIKitComposer {
                        Toggle(MenuTitles.forceCompactShare, isOn: $forceCompactShare)
                            .onReceive(Just(forceCompactShare)) { value in
                                AppContext.shared.userDefaults.set(value, forKey: "forceCompactShare")
                            }

                        Toggle(MenuTitles.forcePickerShare, isOn: $forcePickerShare)
                            .onReceive(Just(forcePickerShare)) { value in
                                AppContext.shared.userDefaults.set(value, forKey: "forcePickerShare")
                            }
                    }
                }
                Button {
                    AppContext.shared.userDefaults.set(false, forKey: "shown.moment.explainer")
                    AppContext.shared.userDefaults.set(false, forKey: "shown.moment.unlock.explainer")
                    AppContext.shared.userDefaults.set(false, forKey: "shown.replace.moment.disclaimer")
                    AppContext.shared.userDefaults.set(false, forKey: "shown.moment.stack.indicator")
                    dismiss?()
                } label: {
                    Text(MenuTitles.resetMomentsFTUX)
                }
                // Log Out
                Button(action: {
                    self.userData.logout(using: self.userData.viewContext)
                    self.dismiss?()
                }) {
                    Text(MenuTitles.logOut)
                }
            }
            .foregroundColor(.blue)
        }
        .sheet(isPresented: self.$isShowingWebClientManager) {
            WebClientView()
        }
    }
}

struct WebClientView: UIViewControllerRepresentable {
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // no-op
    }

    typealias UIViewControllerType = UIViewController

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return WebClientConnectionViewController(manager: MainAppContext.shared.webClientManager)
    }
}
