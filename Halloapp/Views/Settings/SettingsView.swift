//
//  SettingsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import MessageUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var privacySettings = MainAppContext.shared.xmppController.privacySettings

    @State private var isShowingMailView = false
    @State private var mailViewResult: Result<MFMailComposeResult, Error>? = nil

    @State private var isMutedListPresented = false
    @State private var isBlockedListPresented = false

    var body: some View {
        UITableView.appearance().backgroundColor = nil

        return VStack {
            if self.privacySettings.privacyListSyncError != nil {
                HStack {
                    Text(self.privacySettings.privacyListSyncError!)
                        .foregroundColor(.white)
                        .padding(.all)
                        .frame(maxWidth: .infinity)
                }
                .background(Color.lavaOrange)
            }

            Form {
                Section(header: Text("PRIVACY")) {
                    // Feed
                    NavigationLink(destination: FeedPrivacyView().environmentObject(self.privacySettings)) {
                        HStack {
                            Text("Feed")
                            Spacer()
                            Text(self.privacySettings.shortFeedSetting).foregroundColor(.secondary)
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded)

                    // Muted Contacts
                    Button(action: { self.isMutedListPresented = true }) {
                        HStack {
                            Text(PrivacyList.name(forPrivacyListType: .muted))
                            Spacer()
                            Text(self.privacySettings.mutedSetting).foregroundColor(.secondary)
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isMutedListPresented) {
                        PrivacyListView(self.privacySettings.muted!, dismissAction: { self.isMutedListPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }

                    // Blocked Contacts
                    Button(action: { self.isBlockedListPresented = true }) {
                        HStack {
                            Text(PrivacyList.name(forPrivacyListType: .blocked))
                            Spacer()
                            Text(self.privacySettings.blockedSetting).foregroundColor(.secondary)
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isBlockedListPresented) {
                        PrivacyListView(self.privacySettings.blocked!, dismissAction: { self.isBlockedListPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }
                }

                Section {
                    // Invite Contacts
                    NavigationLink(destination: InvitePeopleView()) {
                        Text("Invite Friends")
                            .foregroundColor(.lavaOrange)
                    }
                }

                Section(header: Text("ABOUT")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(UIApplication.shared.version)")
                    }
                }

                Section {
                    Button(action: {
                        if MFMailComposeViewController.canSendMail() {
                            self.isShowingMailView = true
                        }
                    }) {
                        Text("Send Logs").foregroundColor(.lavaOrange)
                    }
                    .sheet(isPresented: self.$isShowingMailView) {
                        MailView(result: self.$mailViewResult)
                    }
                }
            }
        }
        .onAppear(perform: {
            self.privacySettings.downloadListsIfNecessary()
        })
        .onDisappear(perform: {
            self.privacySettings.resetSyncError()
        })
        .navigationBarTitle("Settings", displayMode: .inline)
        .background(Color.feedBackground)
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
