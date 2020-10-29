//
//  SettingsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

private struct TableViewCellChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(UIColor.placeholderText))
    }
}

struct SettingsView: View {
    @ObservedObject private var privacySettings = MainAppContext.shared.privacySettings
    @ObservedObject private var notificationSettings = NotificationSettings.current

    @State private var isBlockedListPresented = false

    init() {
        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<SettingsView>.self ]).backgroundColor = .feedBackground
    }

    var body: some View {
        VStack {
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
                // Notifications
                Section(header: Text("Notifications".uppercased())) {
                    Toggle("Posts", isOn: $notificationSettings.isPostsEnabled)

                    Toggle("Comments", isOn: $notificationSettings.isCommentsEnabled)
                }

                // Privacy
                Section(header: Text("Privacy".uppercased())) {
                    // Feed
                    NavigationLink(destination: FeedPrivacyView().environmentObject(self.privacySettings)) {
                        HStack {
                            Text("Posts")
                            Spacer()
                            Text(self.privacySettings.shortFeedSetting).foregroundColor(.secondary)
                        }
                    }
                    .disabled(!self.privacySettings.isDownloaded)

                    // Blocked Contacts
                    Button(action: { self.isBlockedListPresented = true }) {
                        HStack {
                            Text(PrivacyList.name(forPrivacyListType: .blocked))
                            Spacer()
                            Text(self.privacySettings.blockedSetting).foregroundColor(.secondary)
                            TableViewCellChevron()
                        }
                    }
                    .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isBlockedListPresented) {
                        PrivacyListView(self.privacySettings.blocked, dismissAction: { self.isBlockedListPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }
                }
            }
        }
        .onDisappear(perform: {
            self.privacySettings.resetSyncError()
        })
        .navigationBarTitle("Settings", displayMode: .inline)
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
