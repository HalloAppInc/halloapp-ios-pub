//
//  Verify.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import UIKit

struct VerificationPhoneInputContext {
}

struct VerificationVerifyCodeContext {
    let fromUserAction: Bool
}

struct VerificationContactsPermissionsContext {
}

struct VerificationCompleteContext {
}

class VerificationViewController: UINavigationController, PhoneInputViewControllerDelegate, VerificationCodeViewControllerDelegate, ContactsPermissionsViewControllerDelegate {
    enum State {
        case phoneInput(VerificationPhoneInputContext)
        case verifyCode(VerificationVerifyCodeContext)
        case contactsPermissions(VerificationContactsPermissionsContext)
        case complete(VerificationCompleteContext)
    }
    var state: State?
    var registrationManager: RegistrationManager?

    init(registrationManager: RegistrationManager = DefaultRegistrationManager()) {
        self.registrationManager = registrationManager
        super.init(nibName: nil, bundle: nil)

        styleNavigationBar()
        move(to: .phoneInput(VerificationPhoneInputContext()))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    private func styleNavigationBar() {
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = true
        navigationBar.backgroundColor = UIColor.clear
    }

    private func move(to nextState: State) {
        switch nextState {
        case .complete(_):
            registrationManager?.didCompleteRegistrationFlow()

        default:
            state = nextState
            presentViewController(for: nextState)
        }
    }

    private func presentViewController(for state: State) {
        switch state {
        case .phoneInput(_):
            let phoneInputVC = PhoneInputViewController(nibName: nil, bundle: nil)
            phoneInputVC.delegate = self
            pushViewController(phoneInputVC, animated: false)

        case let .verifyCode(verifyCodeContext):
            let verificationCodeVC = self.newVerificationCodeViewController()
            pushViewController(verificationCodeVC, animated: verifyCodeContext.fromUserAction)
            if verifyCodeContext.fromUserAction {
                verificationCodeVC.requestVerificationCode()
            }

        case .contactsPermissions(_):
            let contactsPermissionsVC = ContactsPermissionsViewController()
            contactsPermissionsVC.delegate = self
            pushViewController(contactsPermissionsVC, animated: true)

        default:
            break
        }
    }

    // MARK: View Controllers

    func newVerificationCodeViewController() -> VerificationCodeViewController {
        let viewController = VerificationCodeViewController()
        viewController.delegate = self
        return viewController
    }

    // MARK: PhoneInputViewControllerDelegate

    func phoneInputViewControllerDidFinish(_ viewController: PhoneInputViewController, countryCode: String, nationalNumber: String, name: String) {
        registrationManager?.set(countryCode: countryCode, nationalNumber: nationalNumber, userName: name)
        move(to: .verifyCode(VerificationVerifyCodeContext(fromUserAction: true)))
    }

    // MARK: VerificationCodeViewControllerDelegate

    var formattedPhoneNumber: String? {
        registrationManager?.formattedPhoneNumber
    }

    func requestVerificationCode(completion: @escaping (Result<Void, Error>) -> Void) {
        registrationManager?.requestVerificationCode(completion: completion)
    }

    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        registrationManager?.confirmVerificationCode(verificationCode, completion: completion)
    }

    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController) {
        move(to: .contactsPermissions(.init()))
    }

    // MARK: ContactsPermissionsViewControllerDelegate

    func didAcknowledgeContactsPermissions() {
        registrationManager?.requestContactsPermissions()
        move(to: .complete(VerificationCompleteContext()))
    }
}
