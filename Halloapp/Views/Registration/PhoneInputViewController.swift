//
//  PhoneInputViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import PhoneNumberKit
import UIKit

protocol PhoneInputViewControllerDelegate: AnyObject {
    func phoneInputViewControllerDidFinish(_ viewController: PhoneInputViewController)
}

class PhoneInputViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: PhoneInputViewControllerDelegate?

    enum UserInputStatus {
        case valid(PhoneNumber, String) // phone number, name
        case invalid(UITextField, String)  // text field to activate, error message
    }

    @IBOutlet var titleLabels: [UILabel]!

    @IBOutlet weak var phoneNumberTextFieldContainer: UIView!
    var textFieldPhoneNumber: PhoneNumberTextField!
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

        // It is necessary to create phone number text field in code so that we can provide shared PhoneNumberKit instance.
        textFieldPhoneNumber = PhoneNumberTextField(withPhoneNumberKit: MainAppContext.shared.phoneNumberFormatter)
        textFieldPhoneNumber.withFlag = true
        textFieldPhoneNumber.withPrefix = true
        textFieldPhoneNumber.withExamplePlaceholder = true
        textFieldPhoneNumber.withDefaultPickerUI = true
        textFieldPhoneNumber.delegate = self
        textFieldPhoneNumber.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        textFieldPhoneNumber.addTarget(self, action: #selector(phoneNumberFieldAction), for: .primaryActionTriggered)
        textFieldPhoneNumber.translatesAutoresizingMaskIntoConstraints = false
        phoneNumberTextFieldContainer.addSubview(textFieldPhoneNumber)
        textFieldPhoneNumber.leadingAnchor.constraint(equalTo: phoneNumberTextFieldContainer.layoutMarginsGuide.leadingAnchor).isActive = true
        textFieldPhoneNumber.topAnchor.constraint(equalTo: phoneNumberTextFieldContainer.layoutMarginsGuide.topAnchor).isActive = true
        textFieldPhoneNumber.trailingAnchor.constraint(equalTo: phoneNumberTextFieldContainer.layoutMarginsGuide.trailingAnchor).isActive = true
        textFieldPhoneNumber.bottomAnchor.constraint(equalTo: phoneNumberTextFieldContainer.layoutMarginsGuide.bottomAnchor).isActive = true

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

    private var phoneNumber: String {
        get { (self.textFieldPhoneNumber.text ?? "").strippingNonDigits() }
    }

    private var userName: String {
        get { (self.textFieldUserName.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private func validateUserInput() -> UserInputStatus {
        guard textFieldPhoneNumber.isValidNumber else {
            return .invalid(textFieldPhoneNumber, "Enter phone number")
        }
        guard !userName.isEmpty else {
            return .invalid(textFieldUserName, "Enter your name")
        }
        return .valid(textFieldPhoneNumber.phoneNumber!, userName)
    }

    @IBAction func nameFieldAction(_ sender: Any) {
        textFieldPhoneNumber.becomeFirstResponder()
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
        } else if textFieldPhoneNumber.isValidNumber {
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
        // Name
        if textField == textFieldUserName {
            if resultingStringLength > 25 {
                return false
            }
            return true
        }
        return true
    }

    @IBAction func signInAction(_ sender: Any) {
        let userInputStatus = self.validateUserInput()

        switch userInputStatus {
        case let .valid(phoneNumber, userName):
            let userData = MainAppContext.shared.userData
            userData.countryCode = String(phoneNumber.countryCode)
            userData.phoneInput = String(phoneNumber.nationalNumber)
            userData.name = userName
            userData.save()
            self.delegate?.phoneInputViewControllerDidFinish(self)

        case let .invalid(textField, _):
            textField.becomeFirstResponder()
        }
    }
}
