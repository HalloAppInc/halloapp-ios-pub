//
//  PhoneInputViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import PhoneNumberKit
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 30
}

protocol PhoneInputViewControllerDelegate: AnyObject {
    func phoneInputViewControllerDidFinish(_ viewController: PhoneInputViewController, countryCode: String, nationalNumber: String, name: String)
    func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void)
}

class PhoneInputViewController: UIViewController, UITextFieldDelegate {
    
    private var cancellableSet: Set<AnyCancellable> = []

    weak var delegate: PhoneInputViewControllerDelegate?

    struct CustomPhoneNumber {
        var countryCode: String
        var nationalNumber: String
    }

    enum UserInputStatus {
        case valid(CustomPhoneNumber, String) // phone number, name
        case invalid(UITextField)  // text field to activate
    }

    let logo = UIImageView()
    let groupInviteLabel = UILabel()
    let phoneNumberKit: PhoneNumberKit = AppContext.shared.phoneNumberFormatter
    let textFieldPhoneNumber = PhoneNumberTextField(withPhoneNumberKit: AppContext.shared.phoneNumberFormatter)
    let textFieldUserName = UITextField()
    let buttonSignIn = UIButton()
    var inputVerticalCenterConstraint: NSLayoutConstraint?

    let disclaimer = UILabel()

    let scrollView = UIScrollView()
    var scrollViewBottomMargin: NSLayoutConstraint?
    
    static let deletedAccountKey = "didDeleteAccount" // Also in `DeletedAccountModel.swift` due to being inaccessible

    override func viewDidLoad() {
        super.viewDidLoad()

        cancellableSet.insert(
            AppContext.shared.didGetGroupInviteToken.sink { [weak self] in
                guard let self = self else { return }
                self.getGroupNameIfNeeded()
            }
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        navigationItem.backButtonTitle = ""

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        groupInviteLabel.font = .systemFont(forTextStyle: .headline, weight: .regular, maximumPointSize: Constants.MaxFontPointSize - 12)
        groupInviteLabel.numberOfLines = 0

        textFieldUserName.translatesAutoresizingMaskIntoConstraints = false
        textFieldUserName.autocapitalizationType = .words
        textFieldUserName.autocorrectionType = .no
        textFieldUserName.returnKeyType = .next
        textFieldUserName.textContentType = .name
        textFieldUserName.placeholder = Localizations.registrationNamePlaceholder
        textFieldUserName.addTarget(self, action: #selector(nameFieldAction), for: .primaryActionTriggered)
        textFieldUserName.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        textFieldUserName.becomeFirstResponder()

        buttonSignIn.layer.masksToBounds = true
        buttonSignIn.setTitle(Localizations.buttonNext, for: .normal)
        buttonSignIn.setBackgroundColor(.systemBlue, for: .normal)
        buttonSignIn.setBackgroundColor(UIColor.systemBlue.withAlphaComponent(0.5), for: .highlighted)
        buttonSignIn.setBackgroundColor(.systemGray4, for: .disabled)
        buttonSignIn.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        buttonSignIn.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)
        buttonSignIn.isEnabled = false

        let nameField = textFieldUserName.withTextFieldBackground()
        let phoneField = textFieldPhoneNumber.withTextFieldBackground()

        let stackView = UIStackView(arrangedSubviews: [groupInviteLabel, nameField, phoneField, buttonSignIn, disclaimer])
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 17
        stackView.setCustomSpacing(14, after: buttonSignIn)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        disclaimer.text = Localizations.registrationCodeDisclaimer
        disclaimer.font = .systemFont(forTextStyle: .footnote, maximumPointSize: Constants.MaxFontPointSize - 14)
        disclaimer.textColor = .secondaryLabel
        disclaimer.numberOfLines = 0
        disclaimer.textAlignment = .center
        disclaimer.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .feedBackground

        textFieldPhoneNumber.withFlag = true
        textFieldPhoneNumber.withPrefix = true
        textFieldPhoneNumber.withExamplePlaceholder = true
        textFieldPhoneNumber.withDefaultPickerUI = true
        textFieldPhoneNumber.delegate = self
        textFieldPhoneNumber.textContentType = .telephoneNumber
        textFieldPhoneNumber.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        textFieldPhoneNumber.addTarget(self, action: #selector(phoneNumberFieldAction), for: .primaryActionTriggered)
        textFieldPhoneNumber.translatesAutoresizingMaskIntoConstraints = false

        // View hierarchy

        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)

        view.addSubview(scrollView)

        // Constraints

        scrollView.constrain([.leading, .trailing, .top], to: view)
        scrollViewBottomMargin = scrollView.constrain(anchor: .bottom, to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 32)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 30).isActive = true
        inputVerticalCenterConstraint = stackView.constrain(anchor: .centerY, to: scrollView, priority: .defaultHigh)

        // Notifications
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] notification in
            self?.updateBottomMargin(with: notification)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] notification in
            self?.updateBottomMargin(with: notification)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: nil) { [weak self] notification in
            self?.updateBottomMargin(with: notification)
        }
        
        if UserDefaults.standard.bool(forKey: Self.deletedAccountKey) == true {
            UserDefaults.standard.set(false, forKey: Self.deletedAccountKey)
            
            let alert = UIAlertController(title: Localizations.accountDeletedTitle, message: Localizations.accountDeletedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { _ in
                exit(0)
            }))
            
            present(alert, animated: true, completion: nil)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        buttonSignIn.layer.cornerRadius = (0.5 * buttonSignIn.frame.height).rounded()
        let effectiveContentHeight = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom + scrollView.adjustedContentInset.top
        scrollView.isScrollEnabled = effectiveContentHeight > self.scrollView.frame.height

        inputVerticalCenterConstraint?.constant = -scrollView.adjustedContentInset.top
    }

    private func updateBottomMargin(with notification: Notification) {
        guard let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else
        {
            return
        }
        let heightInView = endFrame.intersection(view.bounds).height
        let bottomMargin = -max(heightInView, 0)
        if scrollViewBottomMargin?.constant != bottomMargin {
            UIView.animate(withDuration: duration) {
                self.scrollViewBottomMargin?.constant = bottomMargin
                self.view.layoutIfNeeded()
            }
        }
    }

    private var phoneNumber: String {
        get { (self.textFieldPhoneNumber.text ?? "").strippingNonDigits() }
    }

    private var userName: String {
        get { (self.textFieldUserName.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private func validateUserInput() -> UserInputStatus {
        let regionID = textFieldPhoneNumber.currentRegion
        guard let countryCode = phoneNumberKit.countryCode(for: regionID) else {
            // We dont expect this to happen.
            DDLogError("PhoneInputViewController/validateUserInput - missing countryCode for regionID \(regionID)")
            return .invalid(textFieldPhoneNumber)
        }
        let nationalNumber = textFieldPhoneNumber.nationalNumber
        // Check only possible lengths for the national phone number
        let possibleLengths = phoneNumberKit.possiblePhoneNumberLengths(forCountry: regionID, phoneNumberType: .mobile, lengthType: .national)
        guard possibleLengths.contains(nationalNumber.count) else {
            DDLogError("PhoneInputViewController/validateUserInput - invalid phone number \(nationalNumber), possibleLengths: \(possibleLengths)")
            return .invalid(textFieldPhoneNumber)
        }
        guard !userName.isEmpty else {
            return .invalid(textFieldUserName)
        }
        return .valid(CustomPhoneNumber(countryCode: String(countryCode), nationalNumber: nationalNumber), userName)
    }
    
    private func getGroupNameIfNeeded() {
        guard let groupInviteToken = AppContext.shared.userData.groupInviteToken else {
            return
        }
        delegate?.getGroupName(groupInviteToken: groupInviteToken) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let groupName):
                if let groupName = groupName {
                    DDLogInfo("PhoneInputViewController/getGroupNameIfNeeded/fetched group name \(groupName)")
                    AppContext.shared.userData.groupName = groupName
                    let font = UIFont.systemFont(forTextStyle: .headline, weight: .regular, maximumPointSize: Constants.MaxFontPointSize - 12)
                    let inviteString = Localizations.registrationGroupName(formattedGroupName: groupName)
                    self.groupInviteLabel.attributedText = self.getAttributedText(withString: inviteString, boldString: groupName, font: font)
                } else {
                    DDLogInfo("PhoneInputViewController/getGroupNameIfNeeded/group name not found")
                }
            case .failure(let error):
                //TODO(@dini) : Ask if we should flag invalid client?
                DDLogError("PhoneInputViewController/getGroupNameIfNeeded/error fetching group name got group token \(groupInviteToken) with error [\(error)]")
            }
        }
    }
    
    private func getAttributedText(withString string: String, boldString: String, font: UIFont) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: string, attributes: [NSAttributedString.Key.font: font])
        let boldFontAttribute: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: font.pointSize)]
        let range = (string as NSString).range(of: boldString, options: NSString.CompareOptions.caseInsensitive)
        attributedString.addAttributes(boldFontAttribute, range: range)
        return attributedString
    }

    @objc
    func nameFieldAction(_ sender: Any) {
        textFieldPhoneNumber.becomeFirstResponder()
    }

    @objc
    func phoneNumberFieldAction(_ sender: Any) {
        if userName.isEmpty {
            textFieldUserName.becomeFirstResponder()
        } else if textFieldPhoneNumber.isValidNumber {
            didTapNext()
        }
    }

    @objc
    func textFieldEditingChanged(_ sender: Any) {
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

    @objc
    private func didTapNext() {
        let userInputStatus = self.validateUserInput()

        switch userInputStatus {
        case let .valid(phoneNumber, userName):
            view.endEditing(true)
            delegate?.phoneInputViewControllerDidFinish(
                self,
                countryCode: String(phoneNumber.countryCode),
                nationalNumber: String(phoneNumber.nationalNumber),
                name: userName)

        case let .invalid(textField):
            textField.becomeFirstResponder()
        }
    }
}

extension UIView {
    func withTextFieldBackground() -> UIView {
        let background = UIView()
        background.backgroundColor = .textFieldBackground
        background.layer.masksToBounds = true
        background.layer.cornerRadius = 5
        background.addSubview(self)
        background.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        constrainMargins(to: background)
        return background
    }
}

extension Localizations {
    static var accountDeletedTitle = {
        NSLocalizedString("settings.account.deleted.title", value: "Account successfully deleted", comment: "Alert title telling the user that their account was successfully deleted")
    }()
    
    static var accountDeletedDescription = {
        NSLocalizedString("settings.account.deleted.message", value: "You will not be able to log in until you restart the application", comment: "Message for alert telling the user that they need to restart the application before trying to log in again since they deleted their account")
    }()
}
