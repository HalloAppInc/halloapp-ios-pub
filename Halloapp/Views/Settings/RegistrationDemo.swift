//
//  RegistrationDemo.swift
//  HalloApp
//
//  Created by Garrett on 10/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI

struct RegistrationDemo: UIViewControllerRepresentable {
    typealias UIViewControllerType = VerificationViewController

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    let completion: () -> Void

    func makeUIViewController(context: Context) -> VerificationViewController {
        return VerificationViewController.loadedFromStoryboard(
            registrationManager: DemoRegistrationManager(completion: completion))
    }

    func updateUIViewController(_ uiViewController: VerificationViewController, context: Context) {
        // no-op
    }
}

final class DemoRegistrationManager: RegistrationManager {

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    var hasRequestedVerificationCode = false
    var correctCode = "111111"
    var completion: () -> Void
    var formattedPhoneNumber: String?

    func resetPhoneNumber() {
        hasRequestedVerificationCode = false
    }

    func set(countryCode: String, nationalNumber: String, userName: String) {
        formattedPhoneNumber = "+\(countryCode) \(nationalNumber)"
    }

    func requestVerificationCode(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
            self.hasRequestedVerificationCode = true
            completion(.success(()))
        }
    }

    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(2)) {
            if verificationCode == self.correctCode {
                completion(.success(()))
            } else {
                completion(.failure(VerificationCodeValidationError.incorrectCode))
            }
        }

    }

    func didCompleteRegistrationFlow() {
        completion()
    }
}
