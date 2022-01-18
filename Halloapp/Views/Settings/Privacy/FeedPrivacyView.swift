//
//  FeedPrivacyView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

public extension Localizations {
    static var header: String {
        NSLocalizedString("feed.privacy.header", value: "Who will see my posts", comment: "Header describing what these options are for")
    }
}

struct FeedPrivacyView: View {
    @ObservedObject var privacySettings: PrivacySettings

    @State private var isBlacklistScreenPresented: Bool = false
    @State private var isWhitelistScreenPresented: Bool = false
    @State private var shouldShowEnableContactPermissionView: Bool = false

    init(privacySettings: PrivacySettings) {
        self.privacySettings = privacySettings
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.feedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {

                if self.privacySettings.privacyListSyncError != nil {
                    HStack {
                        Text(self.privacySettings.privacyListSyncError!)
                            .foregroundColor(.white)
                            .padding(.all)
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color.lavaOrange)
                }

                Spacer()
                    .frame(height: 15)

                Text(Localizations.header.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primaryBlackWhite.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 7, trailing: 0))

                Button(action: {
                        self.selectAllContacts()
                        self.shouldShowEnableContactPermissionView = !ContactStore.contactsAccessAuthorized
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(self.privacySettings.activeType == .all ? .blue : .clear)

                        VStack(alignment: .leading) {
                            Text(PrivacyList.name(forPrivacyListType: .all))
                                .font(.body)

                            Text(Localizations.feedPrivacyShareWithAllContacts)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }
                .frame(height: 54)
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                .background(Color.feedPostBackground)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 0.5)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                .sheet(isPresented: self.$shouldShowEnableContactPermissionView) {
                    PrivacyPermissionDeniedView(dismissAction: { self.shouldShowEnableContactPermissionView = false })
                }

                Button(action: { self.isBlacklistScreenPresented = true }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(self.privacySettings.activeType == .blacklist ? .blue : .clear)

                        VStack(alignment: .leading) {
                            Text(PrivacyList.name(forPrivacyListType: .blacklist))
                                .font(.body)

                            Text(self.privacySettings.activeType == .blacklist ? self.privacySettings.longFeedSetting : Localizations.feedPrivacyShareWithContactsExcept)
                                .lineLimit(1)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .renderingMode(.template)
                            .foregroundColor(.primaryBlackWhite.opacity(0.3))
                    }
                }
                .frame(height: 54)
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                .background(Color.feedPostBackground)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 0.5)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                .sheet(isPresented: self.$isBlacklistScreenPresented) {
                    PrivacyListView(self.privacySettings.blacklist, dismissAction: { self.isBlacklistScreenPresented = false })
                        .environmentObject(self.privacySettings)
                        .edgesIgnoringSafeArea(.bottom)
                }

                Button(action: { self.isWhitelistScreenPresented = true }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(self.privacySettings.activeType == .whitelist ? .blue : .clear)

                        VStack(alignment: .leading) {
                            Text(PrivacyList.name(forPrivacyListType: .whitelist))
                                .font(.body)

                            Text(self.privacySettings.activeType == .whitelist ? self.privacySettings.longFeedSetting : Localizations.feedPrivacyShareWithSelected)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .renderingMode(.template)
                            .foregroundColor(.primaryBlackWhite.opacity(0.3))
                    }
                }
                .frame(height: 54)
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                .background(Color.feedPostBackground)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 0.5)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .disabled(!self.privacySettings.isDownloaded || self.privacySettings.isSyncing)
                .sheet(isPresented: self.$isWhitelistScreenPresented) {
                    PrivacyListView(self.privacySettings.whitelist, dismissAction: { self.isWhitelistScreenPresented = false })
                        .environmentObject(self.privacySettings)
                        .edgesIgnoringSafeArea(.bottom)
                }

                Spacer()
            }
        }
    }

    private func selectAllContacts() {
        guard self.privacySettings.activeType != .all else { return }

        privacySettings.setFeedSettingToAllContacts()
    }

}
