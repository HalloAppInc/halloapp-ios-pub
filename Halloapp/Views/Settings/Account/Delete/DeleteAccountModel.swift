//
//  DeleteAccountModel.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/1/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import CocoaLumberjackSwift

class DeleteAccountModel: ObservableObject {
    @Published var status: DeleteAccountStatus = .notDeleted
    
    func requestAccountDeletion(phoneNumber: String, displayErrorFunc: @escaping () -> ()) {
        withAnimation {
            self.status = .waitingForResponse
        }
        
        MainAppContext.shared.service.requestAccountDeletion(phoneNumber: phoneNumber) { [weak self] result in
            switch result {
                case .failure(_): self?.handleError(displayErrorFunc: displayErrorFunc)
                case .success(): self?.handleSuccess()
            }
        }
    }
    
    private func handleError(displayErrorFunc: @escaping () -> ()) {
        DispatchQueue.main.async {
            displayErrorFunc()
            withAnimation {
                self.status = .notDeleted
            }
        }
    }
    
    private func handleSuccess() {
        DispatchQueue.main.async {
            withAnimation {
                self.status = .deleted
                MainAppContext.shared.userData.logout()
                
                // Wipe user data from device
                MainAppContext.shared.deleteSharedDirectory()
                MainAppContext.shared.deleteLibraryDirectory()
                MainAppContext.shared.deleteDocumentsDirectory()
                try? FileManager().removeItem(atPath: NSTemporaryDirectory())
                UserDefaults.standard.set(true, forKey: Self.deletedAccountKey)
            }
        }
    }
    
    static let deletedAccountKey = "didDeleteAccount" // Also in `PhoneInputViewController` due to being inaccessible
}

enum DeleteAccountStatus {
    case waitingForResponse, notDeleted, deleted
}
