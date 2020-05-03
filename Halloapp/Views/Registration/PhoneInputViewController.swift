//
//  PhoneInputViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

protocol PhoneInputViewControllerDelegate: AnyObject {
    func phoneInputViewControllerDidFinish(_ viewController: PhoneInputViewController)
}

class PhoneInputViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: PhoneInputViewControllerDelegate?

    enum UserInputStatus {
        case valid(String, String, String) // code, phone number, name
        case invalid(UITextField, String)  // text field to activate, error message
    }

    @IBOutlet var titleLabels: [UILabel]!

    @IBOutlet weak var labelPlusSign: UILabel!
    @IBOutlet weak var textFieldCountryCode: UITextField!
    @IBOutlet weak var textFieldPhoneNumber: UITextField!
    @IBOutlet weak var textFieldUserName: UITextField!
    @IBOutlet var textFieldBackgrounds: [UIView]!

    @IBOutlet weak var buttonSignIn: UIButton!

    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewBottomMargin: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackgroundColor

        titleLabels.forEach { $0.font = .gothamFont(forTextStyle: .largeTitle, weight: .bold) }
        buttonSignIn.layer.masksToBounds = true
        buttonSignIn.titleLabel?.font = .gothamFont(forTextStyle: .title3, weight: .bold)
        textFieldBackgrounds.forEach { (textFieldBackground) in
            textFieldBackground.backgroundColor = .textFieldBackgroundColor
            textFieldBackground.layer.masksToBounds = true
            textFieldBackground.layer.cornerRadius = 10
        }

        textFieldCountryCode.text = AppContext.shared.userData.countryCode

        reloadButtonBackground()

        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { (notification) in
            self.updateBottomMargin(with: notification)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { (notification) in
            self.updateBottomMargin(with: notification)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            reloadButtonBackground()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.isScrollEnabled = self.scrollView.contentSize.height > self.scrollView.frame.height
        buttonSignIn.layer.cornerRadius = (0.5 * buttonSignIn.frame.height).rounded()
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

    private func reloadButtonBackground() {
        buttonSignIn.setBackgroundColor(.systemRed, for: .normal)
        buttonSignIn.setBackgroundColor(UIColor.systemRed.withAlphaComponent(0.2), for: .highlighted)
        buttonSignIn.setBackgroundColor(.systemGray4, for: .disabled)
    }

    private var countryCode: String {
        get { (self.textFieldCountryCode.text ?? "").strippingNonDigits() }
    }

    private var phoneNumber: String {
        get { (self.textFieldPhoneNumber.text ?? "").strippingNonDigits() }
    }

    private var userName: String {
        get { (self.textFieldUserName.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private func validateUserInput() -> UserInputStatus {
        guard !countryCode.isEmpty else {
            return .invalid(textFieldCountryCode, "Enter country code")
        }
        guard phoneNumber.count > 5 else {
            return .invalid(textFieldPhoneNumber, "Enter phone number")
        }
        guard !userName.isEmpty else {
            return .invalid(textFieldUserName, "Enter your name")
        }
        return .valid(countryCode, phoneNumber, userName)
    }

    @IBAction func nameFieldAction(_ sender: Any) {
        if !countryCode.isEmpty && phoneNumber.isEmpty {
            textFieldPhoneNumber.becomeFirstResponder()
        } else {
            textFieldCountryCode.becomeFirstResponder()
        }
    }

    @IBAction func countryCodeFieldAction(_ sender: Any) {
        if !phoneNumber.isEmpty && userName.isEmpty {
            textFieldUserName.becomeFirstResponder()
        } else {
            textFieldPhoneNumber.becomeFirstResponder()
        }
    }

    @IBAction func phoneNumberFieldAction(_ sender: Any) {
        if userName.isEmpty {
            textFieldUserName.becomeFirstResponder()
        } else if countryCode.isEmpty {
            textFieldCountryCode.becomeFirstResponder()
        } else {
            signInAction(buttonSignIn!)
        }
    }

    @IBAction func textFieldEditingChanged(_ sender: Any) {
        let userInputStatus = self.validateUserInput()
        if case .valid = userInputStatus {
            self.buttonSignIn.isEnabled = true
        } else {
            self.buttonSignIn.isEnabled = false
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let resultingStringLength = (textField.text ?? "").count - range.length + string.count
        // Country code
        if textField == textFieldCountryCode {
            // Only allow digits.
            if string.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
                return false
            }
            // Max length is 3.
            if resultingStringLength > 3 {
                return false
            }
            return true
        }
        // Phone Number
        if textField == textFieldPhoneNumber {
            // Only allow certain characters.
            if string.rangeOfCharacter(from: CharacterSet.phoneNumberCharacters.inverted) != nil {
                return false
            }
            // Max Length is 15.
            if resultingStringLength > 15 {
                return false
            }
            return true
        }
        // Name
        if textField == textFieldUserName {
            if resultingStringLength > 30 {
                return false
            }
            return true
        }
        return true
    }

    @IBAction func signInAction(_ sender: Any) {
        let userInputStatus = self.validateUserInput()

        switch userInputStatus {
        case let .valid(countryCode, phoneNumber, userName):
            let userData = AppContext.shared.userData
            userData.countryCode = countryCode
            userData.phoneInput = phoneNumber
            userData.name = userName
            userData.save()
            self.delegate?.phoneInputViewControllerDidFinish(self)

        case let .invalid(textField, _):
            textField.becomeFirstResponder()
        }
    }
}
