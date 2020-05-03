//
//  Verify.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

struct VerificationView: UIViewControllerRepresentable {
    typealias UIViewControllerType = VerificationViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return UIStoryboard(name: "Registration", bundle: nil).instantiateInitialViewController() as! VerificationViewController
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) { }

    class Coordinator: NSObject {
        var parent: VerificationView

        init(_ verificationView: VerificationView) {
            self.parent = verificationView
        }
    }

}

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

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        if let phoneInputViewController = self.viewControllers.first as? PhoneInputViewController {
            phoneInputViewController.delegate = self
        }

        if AppContext.shared.userData.normalizedPhoneNumber.isEmpty {
            self.move(to: .phoneInput(VerificationPhoneInputContext()))
        } else {
            self.move(to: .verifyCode(VerificationVerifyCodeContext(fromUserAction: false)))
        }
    }

    private func move(to nextState: State) {
        switch nextState {
        case .complete(_):
            AppContext.shared.userData.tryLogIn()
            break

        default:
            self.state = nextState
            self.presentViewController(for: nextState)
        }
    }

    private func presentViewController(for state: State) {
        switch state {
        case .phoneInput(_):
            // Should not be necessary at this point because PhoneInputViewController is loaded from the storyboard.
            break

        case let .verifyCode(verifyCodeContext):
            let verificationCodeVC = self.newVerificationCodeViewController()
            self.pushViewController(verificationCodeVC, animated: verifyCodeContext.fromUserAction)
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

    func phoneInputViewControllerDidFinish(_ viewController: PhoneInputViewController) {
        self.move(to: .verifyCode(VerificationVerifyCodeContext(fromUserAction: true)))
    }

    // MARK: VerificationCodeViewControllerDelegate

    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController) {
        self.move(to: .complete(VerificationCompleteContext()))
    }
}
