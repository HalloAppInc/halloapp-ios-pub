//
//  InvitePeopleView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

fileprivate struct InvitePeopleTableView: UIViewControllerRepresentable {

    typealias UIViewControllerType = InvitePeopleTableViewController

    let didSelectContact: (ABContact) -> ()

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = InvitePeopleTableViewController(didSelectContact: didSelectContact)
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }
}

fileprivate struct ActivityView: UIViewControllerRepresentable {

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

    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        return dateFormatter
    }()

    var body: some View {
        Group {
            if inviteManager.dataAvailable && inviteManager.numberOfInvitesAvailable > 0 {
                InvitePeopleTableView { (contact) in
                    self.inviteManager.contactToInvite = contact
                    self.isActionSheetPresented = true
                }
                .disabled(self.inviteManager.redeemInProgress)
                .blur(radius: self.inviteManager.redeemInProgress ? 4 : 0)
                .overlay(Text("Please wait")
                    .padding(.horizontal)
                    .opacity(self.inviteManager.redeemInProgress ? 1 : 0)
                )
            } else if inviteManager.dataAvailable {
                Text("You're out of invites. Please check back after \(self.dateFormatter.string(from: inviteManager.nextRefreshDate!))")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
            } else {
                Text("Loading...")
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
            }
        }
        .font(.title)
        .foregroundColor(.secondary)
        .background(Color.feedBackground)
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitle("Invite Friends", displayMode: .inline)
        .navigationBarItems(leading: Button(action: { self.dismiss() }) {
            Image("NavbarClose")
        })
        .actionSheet(isPresented: $isActionSheetPresented) {
            ActionSheet(title: Text("You are about to redeem one invite for \(self.inviteManager.contactToInvite!.fullName!)"),
                        message: nil,
                        buttons: [
                .default(Text("Redeem")) {
                    self.inviteManager.redeemInviteForSelectedContact(presentErrorAlert: self.$isRedeemErrorAlertPresented,
                                                                      presentShareSheet: self.$isShareSheetPresented)
                },
                .cancel() {
                    self.inviteManager.contactToInvite = nil
                }
            ])
        }
        .alert(isPresented: self.$isRedeemErrorAlertPresented) {
            Alert(title: Text("Could not invite"), message: Text("Something went wrong. Please try again later."), dismissButton: .cancel(Text("OK")))
        }
        .sheet(isPresented: self.$isShareSheetPresented, onDismiss: {
            self.inviteManager.contactToInvite = nil
        }) {
            ActivityView(activityItems: [ "Check out this new app called HalloApp. Download it from: http://halloapp.net/dl" ])
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
