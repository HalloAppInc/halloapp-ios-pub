//
//  SettingsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import MessageUI
import SwiftUI

fileprivate struct ProfilePictureView: UIViewRepresentable {

    typealias UIViewType = AvatarView

    private let userId: UserID

    init(userId: UserID) {
        self.userId = userId
    }

    func makeUIView(context: Context) -> AvatarView {
        let avatarView = AvatarView()
        avatarView.configure(with: self.userId, using: MainAppContext.shared.avatarStore)
        return avatarView
    }

    func updateUIView(_ uiView: AvatarView, context: Context) { }
}

struct SettingsView: View {
    @ObservedObject private var privacySettings = MainAppContext.shared.xmppController.privacySettings
    @ObservedObject private var userData = MainAppContext.shared.userData
    @ObservedObject private var inviteManager = InviteManager.shared

    @State private var isShowingMailView = false
    @State private var mailViewResult: Result<MFMailComposeResult, Error>? = nil

    @State private var isEditingProfile = false
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
                // Profile
                Section {
                    NavigationLink(destination: ProfileEditView(dismiss: { self.isEditingProfile = false }), isActive: self.$isEditingProfile) {
                        HStack(spacing: 15) {
                            ProfilePictureView(userId: userData.userId)
                                .frame(width: 60, height: 60)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(userData.name)
                                    .font(Font(UIFont.preferredFont(forTextStyle: .title3))).fontWeight(.medium)

                                Text(userData.formattedPhoneNumber)
                                    .font(.footnote)
                            }
                        }
                        .padding(.vertical, 2) // default padding is 6pt - add 2 pt to make standard 8
                    }
                }

                // Notifications
                Section(header: Text("Notifications".uppercased())) {
                    Toggle("Posts", isOn: .constant(true))
                        .disabled(true)

                    Toggle("Comments", isOn: .constant(true))
                        .disabled(true)
                }

                // Privacy
                Section(header: Text("Privacy".uppercased())) {
                    // Feed
                    NavigationLink(destination: FeedPrivacyView().environmentObject(self.privacySettings)) {
                        HStack {
                            Text("Feed")
                            Spacer()
                            Text(self.privacySettings.shortFeedSetting).foregroundColor(.secondary)
                        }
                    }
                    .disabled(!self.privacySettings.isLoaded)

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

                    // Privacy Policy
                    NavigationLink(destination: Text("Coming Soon")) {
                        Text("Terms and Privacy Policy")
                    }
                }

                // Help / About
                Section(header: Text("About".uppercased()),
                        footer: VStack {
                            Text("HalloApp")
                            Text("Version \(MainAppContext.appVersion)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                ) {
                    // FAQ
                    NavigationLink(destination: Text("Coming Soon")) {
                        Text("FAQ")
                    }

                    // Send Logs
                    if MFMailComposeViewController.canSendMail() {
                        Button(action: { self.isShowingMailView = true }) {
                            Text("Send Logs")
                        }
                        .sheet(isPresented: self.$isShowingMailView) {
                            MailView(result: self.$mailViewResult)
                        }
                    }

                    // Invite Friends
                    NavigationLink(destination: InvitePeopleView()) {
                        HStack {
                            Text("Invite Friends")

                            Spacer()

                            Text(self.inviteManager.dataAvailable ? "\(self.inviteManager.numberOfInvitesAvailable) Invites" : "...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear(perform: {
            self.privacySettings.downloadListsIfNecessary()
            self.inviteManager.requestInvitesIfNecessary()
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
