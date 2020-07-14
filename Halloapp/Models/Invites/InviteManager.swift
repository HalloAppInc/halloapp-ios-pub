//
//  InviteManager.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CocoaLumberjack
import Foundation
import MessageUI
import SwiftUI

class InviteManager: ObservableObject {

    // MARK: SwiftUI Support
    @Published private(set) var dataAvailable: Bool = false
    @Published private(set) var fetchError: Bool = false
    @Published private(set) var numberOfInvitesAvailable: Int = 0
    @Published private(set) var nextRefreshDate: Date? = nil

    var contactToInvite: ABContact?
    @Published private(set) var redeemInProgress: Bool = false

    private static let sharedManager = InviteManager()
    class var shared: InviteManager { get { sharedManager } }

    init() {
        loadFromUserDefaults()
        dataAvailable = nextRefreshDate != nil && nextRefreshDate!.timeIntervalSinceNow > 0
    }

    // MARK: Server Sync

    func requestInvitesIfNecessary() {
        guard !dataAvailable else {
            DDLogInfo("invite-manager/fetch-request Not necessary")
            return
        }

        DDLogInfo("invite-manager/fetch-request/start")
        self.fetchError = false

        let request = XMPPGetInviteAllowanceRequest { (inviteCount, refreshDate, error) in
            if error != nil {
                DDLogError("invite-manager/fetch-request/error \(error!)")
                self.fetchError = true
            } else {
                DDLogInfo("invite-manager/fetch-request/complete Count: [\(inviteCount!)] Refresh Date: [\(refreshDate!)]")

                self.numberOfInvitesAvailable = inviteCount!
                self.nextRefreshDate = refreshDate
                self.saveToUserDefaults()

                self.dataAvailable = true
            }
        }
        MainAppContext.shared.xmppController.enqueue(request: request)
    }

    func redeemInviteForSelectedContact(presentErrorAlert: Binding<Bool>, presentMessageComposer: Binding<Bool>) {
        guard let contact = contactToInvite else {
            assert(false, "Contact not selected.")
            return
        }

        DDLogInfo("invite-manager/redeem-request/start")
        self.redeemInProgress = true

        let phoneNumber = "+\(contact.normalizedPhoneNumber!)"
        let request = XMPPRegisterInvitesRequest(phoneNumbers: [ phoneNumber ]) { (results, inviteCount, refreshDate,  error) in
            self.redeemInProgress = false

            if error != nil {
                DDLogInfo("invite-manager/redeem-request/error \(error!)")
                presentErrorAlert.wrappedValue = true
            } else if let result = results?[phoneNumber] {
                DDLogInfo("invite-manager/redeem-request/complete Result: [\(result)] Count: [\(inviteCount!)] Refresh Date: [\(refreshDate!)]")

                self.numberOfInvitesAvailable = inviteCount!
                self.nextRefreshDate = refreshDate
                self.saveToUserDefaults()

                if case .success = result {
                    if MFMessageComposeViewController.canSendText() {
                        presentMessageComposer.wrappedValue = true
                    } else {
                        ///TODO: present generic sheet
                    }
                } else {
                    presentErrorAlert.wrappedValue = true
                }
            } else {
                assert(false, "Invalid server response.")
            }
        }
        MainAppContext.shared.xmppController.enqueue(request: request)
    }

    // MARK: Store & load data

    private struct UserDefaultsKeys {
        static let numberOfInvites = "invite.count"
        static let refreshDate = "invite.refreshDate"
    }

    private func loadFromUserDefaults() {
        numberOfInvitesAvailable = UserDefaults.standard.integer(forKey: UserDefaultsKeys.numberOfInvites)
        nextRefreshDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.refreshDate) as? Date
        DDLogInfo("invite-manager/loaded  Available: [\(numberOfInvitesAvailable)]  Refresh Date: [\(String(describing: nextRefreshDate))]")
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(numberOfInvitesAvailable, forKey: UserDefaultsKeys.numberOfInvites)
        UserDefaults.standard.set(nextRefreshDate, forKey: UserDefaultsKeys.refreshDate)
    }
}
