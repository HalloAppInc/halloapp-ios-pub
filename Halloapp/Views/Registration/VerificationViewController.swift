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

struct VerificationCompleteContext {
}

class VerificationViewController: UINavigationController, PhoneInputViewControllerDelegate, VerificationCodeViewControllerDelegate {
    enum State {
        case phoneInput(VerificationPhoneInputContext)
        case verifyCode(VerificationVerifyCodeContext)
        case complete(VerificationCompleteContext)
    }
    var state: State?
    var registrationManager: RegistrationManager?

    class func loadedFromStoryboard(registrationManager: RegistrationManager = DefaultRegistrationManager()) -> VerificationViewController {
        let vc = UIStoryboard(name: "Registration", bundle: nil).instantiateInitialViewController() as! VerificationViewController
        vc.registrationManager = registrationManager
        return vc
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        if let phoneInputViewController = self.viewControllers.first as? PhoneInputViewController {
            phoneInputViewController.delegate = self
        }

        if registrationManager?.hasRequestedVerificationCode ?? false {
            move(to: .verifyCode(VerificationVerifyCodeContext(fromUserAction: false)))
        } else {
            move(to: .phoneInput(VerificationPhoneInputContext()))
        }
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
            // Should not be necessary at this point because PhoneInputViewController is loaded from the storyboard.
            break

        case let .verifyCode(verifyCodeContext):
            let verificationCodeVC = self.newVerificationCodeViewController()
            pushViewController(verificationCodeVC, animated: verifyCodeContext.fromUserAction)
            if verifyCodeContext.fromUserAction {
                verificationCodeVC.requestVerificationCode()
            }

        default:
            break
        }
    }

    // MARK: View Controllers

    func newVerificationCodeViewController() -> VerificationCodeViewController {
        let viewController = UIStoryboard(name: "Registration", bundle: nil).instantiateViewController(withIdentifier: "VerificationCodeViewController") as! VerificationCodeViewController
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

    func verificationCodeViewControllerDidRequestNewPhoneNumber(_ viewController: VerificationCodeViewController) {
        registrationManager?.resetPhoneNumber()
        popViewController(animated: true)
    }

    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController) {
        move(to: .complete(VerificationCompleteContext()))
    }
}
