//
//  VerificationViewController.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/10/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
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
            let verificationCodeVC = VerificationCodeViewController()
            verificationCodeVC.delegate = self
            pushViewController(verificationCodeVC, animated: verifyCodeContext.fromUserAction)
            if verifyCodeContext.fromUserAction {
                verificationCodeVC.requestVerificationCode()
            }
        default:
            break
        }
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

    func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        registrationManager?.requestVerificationCode(byVoice: byVoice, completion: completion)
    }

    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        registrationManager?.confirmVerificationCode(verificationCode, completion: completion)
    }

    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController) {
        move(to: .complete(.init()))
    }

}
