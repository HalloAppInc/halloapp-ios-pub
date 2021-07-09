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
                
                // FIXME: Instead of fatalErroring, store a UserDefault which gets read in SceneDelegate and display a
                // custom view telling the user their data was deleted, but they need to restart the app to create a new account.
                DDLogInfo("DeleteAccountModel/handleSuccess: User data deleted. fatalErroring out so the default directories are re-instantiated.")
                fatalError("Finished deleting user data. App needs relaunch to restore default iOS directories.")
            }
        }
    }
}

enum DeleteAccountStatus {
    case waitingForResponse, notDeleted, deleted
}
