//
//  VerificationCodeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

protocol VerificationCodeViewControllerDelegate: AnyObject {
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

        view.backgroundColor = .feedBackgroundColor

        labelTitle.font = .gothamFont(forTextStyle: .title3, weight: .medium)
        textFieldCode.font = .monospacedDigitSystemFont(ofSize: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).pointSize, weight: .regular)

        labelChangePhone.text = "Not \(MainAppContext.shared.userData.formattedPhoneNumber)?"

        codeInputFieldBackground.backgroundColor = .textFieldBackgroundColor
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
        let userData = MainAppContext.shared.userData
        userData.normalizedPhoneNumber = ""
        userData.save()
        self.navigationController?.popViewController(animated: true)
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
        isCodeRequestInProgress = true

        let userData = MainAppContext.shared.userData
        let phoneNumber = userData.countryCode.appending(userData.phoneInput)

        var request = URLRequest(url: URL(string: "https://api.halloapp.net/api/registration/request_sms")!)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["phone": phoneNumber])
        DDLogInfo("reg/request-sms/begin url=[\(request.url!)]  phone=[\(phoneNumber)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            guard error == nil else {
                DDLogError("reg/request-sms/error [\(error!)]")
                DispatchQueue.main.async {
                    self.verificationCodeRequestFailed()
                }
                return
            }
            guard let data = data else {
                DDLogError("reg/request-sms/error Data is empty.")
                DispatchQueue.main.async {
                    self.verificationCodeRequestFailed()
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    self.verificationCodeRequestFailed()
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    self.verificationCodeRequestFailed()
                }
                return
            }
            DDLogInfo("reg/request-sms/http-response  status=[\(httpResponse.statusCode)]  response=[\(response)]")
            DispatchQueue.main.async {
                self.verificationCodeRequestFinished(with: response)
            }
        }
        task.resume()
    }

    private func verificationCodeRequestFailed(with message: String? = nil) {
        isCodeRequestInProgress = false

        labelTitle.isHidden = true
        viewCodeRequestError.isHidden = false
        viewChangePhone.isHidden = false
    }

    private func verificationCodeRequestFinished(with response: [String : Any]) {
        if let error = response["error"] as? String {
            verificationCodeRequestFailed(with: error)
            return
        }
        guard let normalizedPhoneNumber = response["phone"] as? String else {
            verificationCodeRequestFailed()
            return
        }

        let userData = MainAppContext.shared.userData
        userData.normalizedPhoneNumber = normalizedPhoneNumber
        userData.save()

        isCodeRequestInProgress = false

        labelTitle.isHidden = false
        viewCodeRequestError.isHidden = true
        viewChangePhone.isHidden = false

        textFieldCode.becomeFirstResponder()
    }

    // MARK: Code Validation

    private func validateCode() {
        isCodeValidationInProgress = true

        let userData = MainAppContext.shared.userData
        let json: [String : String] = [ "name": userData.name, "phone": userData.normalizedPhoneNumber, "code": verificationCode ]
        var request = URLRequest(url: URL(string: "https://api.halloapp.net/api/registration/register")!)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: json, options: [])
        DDLogInfo("reg/validate-code/begin url=[\(request.url!)]  data=[\(json)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            guard error == nil else {
                DDLogError("reg/validate-code/error [\(error!)]")
                DispatchQueue.main.async {
                    self.codeValidationFailed()
                }
                return
            }
            guard let data = data else {
                DDLogError("reg/validate-code/error Data is empty.")
                DispatchQueue.main.async {
                    self.codeValidationFailed()
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/validate-code/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    self.codeValidationFailed()
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                DDLogError("reg/validate-code/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    self.codeValidationFailed()
                }
                return
            }
            DDLogInfo("reg/validate-code/finished  status=[\(httpResponse.statusCode)]  response=[\(response)]")
            DispatchQueue.main.async {
                self.codeValidationFinished(with: response)
            }
        }
        task.resume()
    }

    private func codeValidationFailed() {
        isCodeValidationInProgress = false
    }

    private func codeValidationFinished(with response: [String: Any]) {
        isCodeValidationInProgress = false

        if let error = response["error"] as? String {
            DDLogInfo("reg/validate-code/invalid [\(error)]")
            labelInvalidCode.alpha = 1
            textFieldCode.text = ""
            textFieldCode.becomeFirstResponder()
            return
        }
        guard let userId = response["uid"] as? String, let password = response["password"] as? String else {
            DDLogInfo("reg/validate-code/invalid Missing userId or password")
            labelInvalidCode.alpha = 1
            textFieldCode.text = ""
            textFieldCode.becomeFirstResponder()
            return
        }

        DDLogInfo("reg/validate-code/success")

        let userData = MainAppContext.shared.userData
        userData.userId = userId
        userData.password = password
        userData.save()
        self.delegate?.verificationCodeViewControllerDidFinish(self)
    }
}
