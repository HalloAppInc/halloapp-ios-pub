//
//  InvitePeopleView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import MessageUI
import SwiftUI

struct InvitePeopleTableView: UIViewControllerRepresentable {

    typealias UIViewControllerType = InvitePeopleTableViewController

    let didSelectContact: (ABContact) -> ()

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = InvitePeopleTableViewController(didSelectContact: didSelectContact)
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
}


struct InvitePeopleView: View {
    @ObservedObject private var inviteManager = InviteManager.shared

    @State private var isActionSheetPresented = false
    @State private var isRedeemErrorAlertPresented = false
    @State private var isMessageComposerPresented = false

    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        return dateFormatter
    }()

    var body: some View {
        Group {
            if inviteManager.dataAvailable && inviteManager.numberOfInvitesAvailable > 0 {
                ZStack {
                    VStack(spacing: .zero) {
                        Text("You have \(inviteManager.numberOfInvitesAvailable) invites available")
                            .font(.headline)
                            .padding()

                        Divider()

                        InvitePeopleTableView { (contact) in
                            self.inviteManager.contactToInvite = contact
                            self.isActionSheetPresented = true
                        }
                    }
                    .disabled(self.inviteManager.redeemInProgress)
                    .blur(radius: self.inviteManager.redeemInProgress ? 4 : 0)

                    Text("Please wait")
                        .font(.title)
                        .foregroundColor(.primary)
                        .padding()
                        .opacity(self.inviteManager.redeemInProgress ? 1 : 0)
                }
            } else if inviteManager.dataAvailable {
                Text("You're out of invites. Please check back after \(self.dateFormatter.string(from: inviteManager.nextRefreshDate!))")
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Text("Loading...")
                    .font(.title)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .navigationBarTitle("Invite Friends", displayMode: .inline)
        .actionSheet(isPresented: $isActionSheetPresented) {
            ActionSheet(title: Text("You are about to redeem one invite for \(self.inviteManager.contactToInvite!.fullName!)"),
                        message: nil,
                        buttons: [
                .default(Text("Redeem")) {
                    self.inviteManager.redeemInviteForSelectedContact(presentErrorAlert: self.$isRedeemErrorAlertPresented,
                                                                      presentMessageComposer: self.$isMessageComposerPresented)
                },
                .cancel() {
                    self.inviteManager.contactToInvite = nil
                }
            ])
        }
        .alert(isPresented: self.$isRedeemErrorAlertPresented) {
            Alert(title: Text("Could not invite"), message: Text("Something went wrong. Please try again later."), dismissButton: .cancel(Text("OK")))
        }
        .sheet(isPresented: self.$isMessageComposerPresented, onDismiss: {
            self.inviteManager.contactToInvite = nil
        }) {
            MFMessageComposeView(isPresented: self.$isMessageComposerPresented,
                                 recipients: ["+\(self.inviteManager.contactToInvite!.normalizedPhoneNumber!)"],
                                 messageText: "Check out this new cool app called HalloApp. Download here: http://halloapp.net/dl")
        }
        .onAppear {
            self.inviteManager.requestInvitesIfNecessary()
        }
        .onDisappear {
            self.inviteManager.contactToInvite = nil
        }
    }

}

struct InvitePeopleView_Previews: PreviewProvider {
    static var previews: some View {
        InvitePeopleView()
    }
}
