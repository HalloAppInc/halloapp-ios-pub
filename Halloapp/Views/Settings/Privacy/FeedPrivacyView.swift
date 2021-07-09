//
//  FeedPrivacyView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

private extension Localizations {

    static var shareWithAllContacts: String {
        return NSLocalizedString("feed.privacy.descr.all",
                                 value: "Share with all of your contacts",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }

    static var shareWithContactsExcept: String {
        return NSLocalizedString("feed.privacy.descr.except",
                                 value: "Share with your contacts except people you select",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }

    static var shareWithSelected: String {
        return NSLocalizedString("feed.privacy.descr.only",
                                 value: "Only share with selected contacts",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }
}

struct FeedPrivacyView: View {
    @ObservedObject var privacySettings: PrivacySettings

    @State private var isBlacklistScreenPresented: Bool = false
    @State private var isWhitelistScreenPresented: Bool = false
    @State private var shouldShowEnableContactPermissionView: Bool = false

    init(privacySettings: PrivacySettings) {
        self.privacySettings = privacySettings
        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<FeedPrivacyView>.self ]).backgroundColor = .feedBackground
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
                Section {
                    Button(action: {
                            self.selectAllContacts()
                            self.shouldShowEnableContactPermissionView = !ContactStore.contactsAccessAuthorized
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .foregroundColor(self.privacySettings.activeType == .all ? .lavaOrange : .clear)

                            VStack(alignment: .leading) {
                                Text(PrivacyList.name(forPrivacyListType: .all))
                                    .font(self.privacySettings.activeType == .all ? Font.body.bold() : Font.body)

                                Text(Localizations.shareWithAllContacts)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$shouldShowEnableContactPermissionView) {
                        PrivacyPermissionDeniedView(dismissAction: { self.shouldShowEnableContactPermissionView = false })
                    }
                    Button(action: { self.isBlacklistScreenPresented = true }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .foregroundColor(self.privacySettings.activeType == .blacklist ? .lavaOrange : .clear)

                            VStack(alignment: .leading) {
                                Text(PrivacyList.name(forPrivacyListType: .blacklist))
                                    .font(self.privacySettings.activeType == .blacklist ? Font.body.bold() : Font.body)

                                Text(self.privacySettings.activeType == .blacklist ? self.privacySettings.longFeedSetting : Localizations.shareWithContactsExcept)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isBlacklistScreenPresented) {
                        PrivacyListView(self.privacySettings.blacklist, dismissAction: { self.isBlacklistScreenPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }

                    Button(action: { self.isWhitelistScreenPresented = true }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .foregroundColor(self.privacySettings.activeType == .whitelist ? .lavaOrange : .clear)

                            VStack(alignment: .leading) {
                                Text(PrivacyList.name(forPrivacyListType: .whitelist))
                                    .font(self.privacySettings.activeType == .whitelist ? Font.body.bold() : Font.body)

                                Text(self.privacySettings.activeType == .whitelist ? self.privacySettings.longFeedSetting : Localizations.shareWithSelected)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isWhitelistScreenPresented) {
                        PrivacyListView(self.privacySettings.whitelist, dismissAction: { self.isWhitelistScreenPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }
                }
            }
        }
        .background(Color.feedBackground)
        .edgesIgnoringSafeArea(.bottom)
    }

    private func selectAllContacts() {
        guard self.privacySettings.activeType != .all else { return }

        privacySettings.setFeedSettingToAllContacts()
    }

}
