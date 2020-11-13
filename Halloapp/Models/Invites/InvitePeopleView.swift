//
//  InvitePeopleView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

private extension Localizations {

    static var pleaseWait: String {
        NSLocalizedString("invite.please.wait", value: "Please wait...", comment: "Displayed white user is inviting someone.")
    }

    static var inviteLoading: String {
        NSLocalizedString("invite.loading", value: "Loading...", comment: "Displayed when app is checking server for available invites.")
    }

    static func outOfInvitesWith(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        let format = NSLocalizedString("invite.out.of.invites.w.date",
                                       value: "You're out of invites. Please check back after %@",
                                       comment: "Displayed when user does not have any invites left. Parameter is date.")
        return String(format: format, dateFormatter.string(from: date))
    }

    static var titleInviteFriends: LocalizedStringKey {
        LocalizedStringKey(NSLocalizedString("invite.friends.title", value: "Invite Friends & Family", comment: "Title for the screen that allows to select contact to invite."))
    }

    static var buttonRedeem: String {
        NSLocalizedString("invite.button.redeem", value: "Redeem", comment: "Button title. Refers to redeeming an invite to use HalloApp.")
    }

    static func redeemPrompt(contactName: String) -> String {
        let format = NSLocalizedString("invite.redeem.prompt",
                                       value: "You are about to redeem one invite for %@",
                                       comment: "Confirmation prompt when redeeming an invite for someone.")
        return String(format: format, contactName)
    }

    static var inviteErrorTitle: String {
        NSLocalizedString("invite.error.alert.title",
                          value: "Could not invite",
                          comment: "Title of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static var inviteErrorMessage: String {
        NSLocalizedString("invite.error.alert.message",
                          value: "Something went wrong. Please try again later.",
                          comment: "Body of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static var inviteText: String {
        NSLocalizedString("invite.text",
                          value: "Join me on HalloApp – a simple, private, and secure way to stay in touch with friends and family. Get it at https://halloapp.com/dl",
                          comment: "Text of invitation to join HalloApp.")
    }
}

private struct InvitePeopleTableView: UIViewControllerRepresentable {

    typealias UIViewControllerType = InvitePeopleTableViewController

    let didSelectContact: (ABContact) -> ()

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = InvitePeopleViewController(didSelectContact: didSelectContact)
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
}

private struct ActivityView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIActivityViewController

    private let activityItems: [Any]

    init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = UIActivityViewController(activityItems: self.activityItems, applicationActivities: nil)
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }

}


struct InvitePeopleView: View {
    @ObservedObject private var inviteManager = InviteManager.shared

    @State private var isActionSheetPresented = false
    @State private var isRedeemErrorAlertPresented = false
    @State private var isShareSheetPresented = false

    let dismiss: () -> ()

    var body: some View {
        Group {
            if inviteManager.isDataCurrent && inviteManager.numberOfInvitesAvailable > 0 {
                InvitePeopleTableView { (contact) in
                    self.inviteManager.contactToInvite = contact
                    self.isActionSheetPresented = true
                }
                .disabled(self.inviteManager.redeemInProgress)
                .blur(radius: self.inviteManager.redeemInProgress ? 4 : 0)
                .overlay(Text(Localizations.pleaseWait)
                    .padding(.horizontal)
                    .opacity(self.inviteManager.redeemInProgress ? 1 : 0)
                )
            } else if inviteManager.isDataCurrent {
                Text(Localizations.outOfInvitesWith(date: inviteManager.nextRefreshDate!))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
            } else {
                Text(Localizations.inviteLoading)
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
            }
        }
        .font(.title)
        .foregroundColor(.secondary)
        .background(Color.feedBackground)
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitle(Localizations.titleInviteFriends, displayMode: .inline)
        .navigationBarItems(leading: Button(action: { self.dismiss() }) {
            Image("NavbarClose").renderingMode(.template)
        })
        .actionSheet(isPresented: $isActionSheetPresented) {
            ActionSheet(
                title: Text(Localizations.redeemPrompt(contactName: self.inviteManager.contactToInvite!.fullName!)),
                message: nil,
                buttons: [
                    .default(Text(Localizations.buttonRedeem)) {
                        self.inviteManager.redeemInviteForSelectedContact(presentErrorAlert: self.$isRedeemErrorAlertPresented,
                                                                          presentShareSheet: self.$isShareSheetPresented)
                    },
                    .cancel() {
                        self.inviteManager.contactToInvite = nil
                    }
                ])
        }
        .alert(isPresented: self.$isRedeemErrorAlertPresented) {
            Alert(title: Text(Localizations.inviteErrorTitle),
                  message: Text(Localizations.inviteErrorMessage),
                  dismissButton: .cancel(Text(Localizations.buttonOK)))
        }
        .sheet(isPresented: self.$isShareSheetPresented, onDismiss: {
            self.inviteManager.contactToInvite = nil
        }) {
            ActivityView(activityItems: [ Localizations.inviteText ])
        }
        .onDisappear {
            self.inviteManager.contactToInvite = nil
        }
    }

}

struct InvitePeopleView_Previews: PreviewProvider {
    static var previews: some View {
        InvitePeopleView(dismiss: {})
    }
}
