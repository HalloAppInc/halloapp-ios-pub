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

private extension Localizations {

    static var notifications: String {
        NSLocalizedString("settings.notifications", value: "Notifications", comment: "Settings menu section.")
    }

    static var postNotifications: String {
        NSLocalizedString("settings.notifications.posts", value: "Posts", comment: "Settings > Notifications: label for the toggle that turns new post notifications on or off.")
    }

    static var commentNotifications: String {
        NSLocalizedString("settings.notifications.comments", value: "Comments", comment: "Settings > Notifications: label for the toggle that turns new comment notifications on or off.")
    }

    static var privacy: String {
        NSLocalizedString("settings.privacy", value: "Privacy", comment: "Settings menu section")
    }

    static var postsPrivacy: String {
        NSLocalizedString("settings.privacy.posts", value: "Posts", comment: "Settings > Privacy: name of a setting that defines who can see your posts.")
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
                Section(header: Text(Localizations.notifications.uppercased())) {
                    Toggle(Localizations.postNotifications, isOn: $notificationSettings.isPostsEnabled)

                    Toggle(Localizations.commentNotifications, isOn: $notificationSettings.isCommentsEnabled)
                }

                // Privacy
                Section(header: Text(Localizations.privacy.uppercased())) {
                    // Feed
                    NavigationLink(destination: FeedPrivacyView()
                                    .navigationBarTitle(LocalizedStringKey(Localizations.postsPrivacy))
                                    .environmentObject(self.privacySettings)) {
                        HStack {
                            Text(Localizations.postsPrivacy)
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
        .navigationBarTitle(LocalizedStringKey(Localizations.titleSettings), displayMode: .inline)
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
