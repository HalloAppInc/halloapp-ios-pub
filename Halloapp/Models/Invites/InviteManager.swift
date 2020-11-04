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
import SwiftUI

class InviteManager: ObservableObject {

    // MARK: SwiftUI Support
    @Published private(set) var isDataCurrent: Bool = false
    @Published private(set) var fetchError: Bool = false
    @Published private(set) var numberOfInvitesAvailable: Int = 0
    @Published private(set) var nextRefreshDate: Date? = nil

    var contactToInvite: ABContact?
    @Published private(set) var redeemInProgress: Bool = false

    private static let sharedManager = InviteManager()
    class var shared: InviteManager {
        sharedManager
    }

    init() {
        loadFromUserDefaults()
    }

    private func validateCachedData() {
        isDataCurrent = nextRefreshDate != nil && nextRefreshDate!.timeIntervalSinceNow > 0
    }

    // MARK: Server Sync

    func requestInvitesIfNecessary() {
        validateCachedData()

        guard !isDataCurrent else {
            DDLogInfo("invite-manager/fetch-request Not necessary")
            return
        }

        DDLogInfo("invite-manager/fetch-request/start")
        fetchError = false

        MainAppContext.shared.service.requestInviteAllowance { result in
            switch result {
            case .success(let (inviteCount, refreshDate)):
                DDLogInfo("invite-manager/fetch-request/complete Count: [\(inviteCount)] Refresh Date: [\(refreshDate)]")

                self.numberOfInvitesAvailable = inviteCount
                self.nextRefreshDate = refreshDate
                self.saveToUserDefaults()

            case .failure(let error):
                DDLogError("invite-manager/fetch-request/error \(error)")
                self.fetchError = true
            }
        }
    }

    func redeemInviteForSelectedContact(presentErrorAlert: Binding<Bool>, presentShareSheet: Binding<Bool>) {
        guard let contact = contactToInvite else {
            assert(false, "Contact not selected.")
            return
        }

        DDLogInfo("invite-manager/redeem-request/start")
        self.redeemInProgress = true

        let phoneNumber = "+\(contact.normalizedPhoneNumber!)"
        MainAppContext.shared.service.sendInvites(phoneNumbers: [phoneNumber]) { result in
            self.redeemInProgress = false

            switch result {
            case .success(let (inviteResults, inviteCount, refreshDate)):
                let inviteResult = inviteResults[phoneNumber]!

                DDLogInfo("invite-manager/redeem-request/complete Result: [\(inviteResult)] Count: [\(inviteCount)] Refresh Date: [\(refreshDate)]")

                self.numberOfInvitesAvailable = inviteCount
                self.nextRefreshDate = refreshDate
                self.saveToUserDefaults()

                if case .success = inviteResult {
                    presentShareSheet.wrappedValue = true
                } else if case .failure(let reason) = inviteResult, reason == .existingUser {
                    presentShareSheet.wrappedValue = true
                } else {
                    presentErrorAlert.wrappedValue = true
                }

            case .failure(let error):
                DDLogInfo("invite-manager/redeem-request/error \(error)")
                presentErrorAlert.wrappedValue = true
            }
        }
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
        validateCachedData()
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(numberOfInvitesAvailable, forKey: UserDefaultsKeys.numberOfInvites)
        UserDefaults.standard.set(nextRefreshDate, forKey: UserDefaultsKeys.refreshDate)
        validateCachedData()
    }
}
