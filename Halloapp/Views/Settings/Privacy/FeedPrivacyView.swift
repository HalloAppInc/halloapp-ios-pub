//
//  FeedPrivacyView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedPrivacyView: View {
    @EnvironmentObject var privacySettings: PrivacySettings

    @State private var isBlacklistScreenPresented: Bool = false
    @State private var isWhitelistScreenPresented: Bool = false

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
                    Button(action: { self.selectAllContacts() }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .foregroundColor(self.privacySettings.activeType == .all ? .lavaOrange : .clear)

                            VStack(alignment: .leading) {
                                Text(PrivacyList.name(forPrivacyListType: .all))
                                    .font(self.privacySettings.activeType == .all ? Font.body.bold() : Font.body)

                                Text("Share with all of your contacts")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded || self.privacySettings.isSyncing)

                    Button(action: { self.isBlacklistScreenPresented = true }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .foregroundColor(self.privacySettings.activeType == .blacklist ? .lavaOrange : .clear)

                            VStack(alignment: .leading) {
                                Text(PrivacyList.name(forPrivacyListType: .blacklist))
                                    .font(self.privacySettings.activeType == .blacklist ? Font.body.bold() : Font.body)

                                Text(self.privacySettings.activeType == .blacklist ? self.privacySettings.longFeedSetting : "Share with your contacts except people you select")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isBlacklistScreenPresented) {
                        PrivacyListView(self.privacySettings.blacklist!, dismissAction: { self.isBlacklistScreenPresented = false })
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

                                Text(self.privacySettings.activeType == .whitelist ? self.privacySettings.longFeedSetting : "Only share with selected contacts")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded || self.privacySettings.isSyncing)
                    .sheet(isPresented: self.$isWhitelistScreenPresented) {
                        PrivacyListView(self.privacySettings.whitelist!, dismissAction: { self.isWhitelistScreenPresented = false })
                            .environmentObject(self.privacySettings)
                            .edgesIgnoringSafeArea(.bottom)
                    }
                }
            }
        }
        .navigationBarTitle("Feed", displayMode: .inline)
        .background(Color.feedBackground)
        .edgesIgnoringSafeArea(.bottom)
    }

    private func selectAllContacts() {
        guard self.privacySettings.activeType != .all else { return }

        privacySettings.setFeedSettingToAllContacts()
    }

}

struct FeedPrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        FeedPrivacyView()
    }
}
