//
//  DeleteAccountModel.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/1/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import CocoaLumberjackSwift

protocol DeleteAccountModelDelegate: AnyObject {
    func deleteAccountModelDidRequestCancel(_ model: DeleteAccountModel)
}

class DeleteAccountModel: ObservableObject {

    enum DeleteAccountStatus {
        case warning, confirm, waitingForResponse, deleted
    }

    @Published var status: DeleteAccountStatus = .warning
    @Published var isShowingErrorMessage: Bool = false

    @Published var phoneNumber = ""
    @Published var feedback = ""

    weak var delegate: DeleteAccountModelDelegate?

    func requestAccountDeletion() {
        guard !phoneNumber.isEmpty else {
            withAnimation {
                isShowingErrorMessage = true
            }
            return
        }

        withAnimation {
            self.status = .waitingForResponse
        }

        MainAppContext.shared.service.requestAccountDeletion(phoneNumber: phoneNumber, feedback: feedback) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                    case .failure(_): self?.handleError()
                    case .success(): self?.handleSuccess()
                }
            }
        }
    }

    func cancel() {
        delegate?.deleteAccountModelDidRequestCancel(self)
    }
    
    private func handleError() {
        withAnimation {
            status = .confirm
            isShowingErrorMessage = true
        }
    }
    
    private func handleSuccess() {
        withAnimation {
            status = .deleted
        }

        MainAppContext.shared.userData.logout()

        // Wipe user data from device
        MainAppContext.shared.deleteSharedDirectory()
        MainAppContext.shared.deleteLibraryDirectory()
        MainAppContext.shared.deleteDocumentsDirectory()
        try? FileManager().removeItem(atPath: NSTemporaryDirectory())
        UserDefaults.standard.set(true, forKey: Self.deletedAccountKey)
    }
    
    static let deletedAccountKey = "didDeleteAccount" // Also in `PhoneInputViewController` due to being inaccessible
}
