//
//  VerificationCodeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

protocol VerificationCodeViewControllerDelegate: AnyObject {
    var formattedPhoneNumber: String? { get }
    func requestVerificationCode(completion: @escaping (Result<Void, Error>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void)
    func verificationCodeViewControllerDidRequestNewPhoneNumber(_ viewController: VerificationCodeViewController)
    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController)
}

class VerificationCodeViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: VerificationCodeViewControllerDelegate?

    private var isCodeRequestInProgress: Bool = false {
        didSet {
            if self.isViewLoaded {
                activityIndicatorView.isHidden = !isCodeRequestInProgress
                buttonReenterPhone.isEnabled = !isCodeRequestInProgress
                buttonRetryCodeRequest.isEnabled = !isCodeRequestInProgress
                buttonContinue.isEnabled = !isCodeRequestInProgress && !verificationCode.isEmpty
                textFieldCode.isEnabled = !isCodeRequestInProgress
                labelInvalidCode.alpha = 0
            }
        }
    }
    private var isCodeValidationInProgress: Bool = false {
        didSet {
            if self.isViewLoaded {
                activityIndicatorView.isHidden = !isCodeValidationInProgress
                buttonReenterPhone.isEnabled = !isCodeValidationInProgress
                buttonRetryCodeRequest.isEnabled = !isCodeValidationInProgress
                buttonContinue.isEnabled = !isCodeValidationInProgress && !verificationCode.isEmpty
                textFieldCode.isEnabled = !isCodeValidationInProgress
                labelInvalidCode.alpha = 0
            }
        }
    }

    @IBOutlet weak var labelTitle: UILabel!

    @IBOutlet weak var codeInputContainer: UIStackView!
    @IBOutlet weak var codeInputFieldBackground: UIView!
    @IBOutlet weak var textFieldCode: UITextField!
    @IBOutlet weak var labelInvalidCode: UILabel!
    @IBOutlet weak var buttonContinue: UIButton!

    @IBOutlet weak var viewCodeRequestError: UIView!
    @IBOutlet weak var buttonRetryCodeRequest: UIButton!

    @IBOutlet weak var viewChangePhone: UIStackView!
    @IBOutlet weak var labelChangePhone: UILabel!
    @IBOutlet weak var buttonReenterPhone: UIButton!

    @IBOutlet weak var activityIndicatorView: UIView!

    @IBOutlet weak var scrollViewBottomMargin: NSLayoutConstraint!

    @IBOutlet var buttons: [UIButton]!
    @IBOutlet var labels: [UILabel]!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        labelTitle.font = .gothamFont(forTextStyle: .title3, weight: .medium)
        textFieldCode.font = .monospacedDigitSystemFont(ofSize: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).pointSize, weight: .regular)

        if let formattedPhoneNumber = delegate?.formattedPhoneNumber {
            labelChangePhone.text = "Not \(formattedPhoneNumber)?"
        }

        codeInputFieldBackground.backgroundColor = .textFieldBackground
        codeInputFieldBackground.layer.masksToBounds = true
        codeInputFieldBackground.layer.cornerRadius = 10

        buttonContinue.layer.masksToBounds = true
        buttonContinue.titleLabel?.font = .gothamFont(forTextStyle: .title3, weight: .bold)

        reloadButtonBackground()

        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { (notification) in
            self.updateBottomMargin(with: notification)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { (notification) in
            self.updateBottomMargin(with: notification)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: nil) { (notification) in
            self.updateBottomMargin(with: notification)
        }

        // Update UI.
        if isCodeRequestInProgress {
            isCodeRequestInProgress = true

            self.viewCodeRequestError.isHidden = true
            self.viewChangePhone.isHidden = true
            self.labelTitle.isHidden = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        buttonContinue.layer.cornerRadius = (0.5 * buttonContinue.frame.height).rounded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            reloadButtonBackground()
        }
    }

    private func reloadButtonBackground() {
        buttonContinue.setBackgroundColor(.systemRed, for: .normal)
        buttonContinue.setBackgroundColor(UIColor.systemRed.withAlphaComponent(0.2), for: .highlighted)
        buttonContinue.setBackgroundColor(.systemGray4, for: .disabled)
    }

    private func updateBottomMargin(with keyboardNotification: Notification) {
        let endFrame: CGRect = (keyboardNotification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        let duration: TimeInterval = keyboardNotification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        let bottomMargin = max(endFrame.height - self.view.safeAreaInsets.bottom, 0) + 8
        if scrollViewBottomMargin.constant != bottomMargin {
            UIView.animate(withDuration: duration) {
                self.scrollViewBottomMargin.constant = bottomMargin
                self.view.layoutIfNeeded()
            }
        }
    }

    @IBAction func textFieldCodeEditingChanged(_ sender: Any) {
        self.buttonContinue.isEnabled = verificationCode.count > 4
    }

    @IBAction func tryAgainAction(_ sender: Any) {
        self.requestVerificationCode()
    }

    @IBAction func changePhoneNumberAction(_ sender: Any) {
        delegate?.verificationCodeViewControllerDidRequestNewPhoneNumber(self)
    }

    @IBAction func continueAction(_ sender: Any) {
        validateCode()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.rangeOfCharacter(from: NSCharacterSet.decimalDigits.inverted) == nil else { return false }
        let resultingLength = (textField.text?.count ?? 0) - range.length + string.count
        return resultingLength <= 12
    }

    private var verificationCode: String {
        get { (textFieldCode.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    // MARK: Code Request

    func requestVerificationCode() {
        guard let delegate = delegate else {
            DDLogError("VerificationCodeViewController/validateCode/error missing delegate")
            return
        }

        isCodeRequestInProgress = true

        delegate.requestVerificationCode() { [weak self] result in
            self?.isCodeRequestInProgress = false
            switch result {
            case .success:
                self?.labelTitle.isHidden = false
                self?.viewCodeRequestError.isHidden = true
                self?.viewChangePhone.isHidden = false

                self?.textFieldCode.becomeFirstResponder()

            case .failure(let error):
                self?.labelTitle.isHidden = true
                self?.viewChangePhone.isHidden = false
                if let codeRequestError = error as? VerificationCodeRequestError, case .notInvited = codeRequestError {
                    let message = "We are currently in beta and by invitation only. Please have one of your friends who is a HalloApp user invite you."
                    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel))
                    self?.present(alert, animated: true)
                } else {
                    self?.viewCodeRequestError.isHidden = false
                }
            }
        }
    }

    // MARK: Code Validation

    private func validateCode() {
        guard let delegate = delegate else {
            DDLogError("VerificationCodeViewController/validateCode/error missing delegate")
            return
        }

        isCodeValidationInProgress = true

        delegate.confirmVerificationCode(verificationCode) { [weak self] result in
            guard let self = self else { return }

            self.isCodeValidationInProgress = false
            switch result {
            case .success:
                self.delegate?.verificationCodeViewControllerDidFinish(self)
            case .failure:
                self.labelInvalidCode.alpha = 1
                self.textFieldCode.text = ""
                self.textFieldCode.becomeFirstResponder()
            }
        }
    }
}
