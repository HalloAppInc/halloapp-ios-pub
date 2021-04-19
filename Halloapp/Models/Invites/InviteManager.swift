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
    @Published private(set) var fetchError: Bool = false
    @Published private(set) var numberOfInvitesAvailable: Int = 0
    @Published private(set) var nextRefreshDate: Date? = nil
    @Published private(set) var redeemInProgress: Bool = false
    @Published private(set) var isLoading: Bool = false

    private static let sharedManager = InviteManager()
    class var shared: InviteManager {
        sharedManager
    }

    init() {
        loadFromUserDefaults()
    }

    // MARK: Server Sync

    var isDataCurrent: Bool {
        nextRefreshDate != nil && nextRefreshDate!.timeIntervalSinceNow > 0
    }

    func requestInvitesIfNecessary() {
        guard !isLoading else {
            DDLogInfo("invite-manager/fetch-request/aborting [in progress]")
            return
        }

        DDLogInfo("invite-manager/fetch-request/start")
        fetchError = false
        isLoading = true

        MainAppContext.shared.service.requestInviteAllowance { [weak self] result in
            guard let self = self else { return }

            self.isLoading = false
            switch result {
            case .success(let (inviteCount, refreshDate)):
                DDLogInfo("invite-manager/fetch-request/complete Count: [\(inviteCount)] Refresh Date: [\(refreshDate)]")

                self.nextRefreshDate = refreshDate
                self.numberOfInvitesAvailable = inviteCount
                self.saveToUserDefaults()

            case .failure(let error):
                DDLogError("invite-manager/fetch-request/error \(error)")
                self.fetchError = true
            }
        }
    }

    func redeemInviteForPhoneNumber(_ normalizedPhoneNumber: String, completion: @escaping (InviteResult) -> Void) {
        DDLogInfo("invite-manager/redeem-request/start")
        self.redeemInProgress = true

        let phoneNumber = "+\(normalizedPhoneNumber)"
        MainAppContext.shared.service.sendInvites(phoneNumbers: [phoneNumber]) { result in
            self.redeemInProgress = false

            switch result {
            case .success(let (inviteResults, inviteCount, refreshDate)):
                guard let inviteResult = inviteResults[phoneNumber] else {
                    completion(.failure(.unknown))
                    return
                }

                DDLogInfo("invite-manager/redeem-request/complete Result: [\(inviteResult)] Count: [\(inviteCount)] Refresh Date: [\(refreshDate)]")

                self.numberOfInvitesAvailable = inviteCount
                self.nextRefreshDate = refreshDate
                self.saveToUserDefaults()

                completion(inviteResult)

            case .failure(let error):
                DDLogInfo("invite-manager/redeem-request/error \(error)")

                completion(.failure(.unknown))
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
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(numberOfInvitesAvailable, forKey: UserDefaultsKeys.numberOfInvites)
        UserDefaults.standard.set(nextRefreshDate, forKey: UserDefaultsKeys.refreshDate)
    }
}
