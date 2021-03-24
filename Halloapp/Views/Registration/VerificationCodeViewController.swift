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
    func requestVerificationCode(completion: @escaping (Result<TimeInterval, Error>) -> Void)
    func confirmVerificationCode(_ verificationCode: String, completion: @escaping (Result<Void, Error>) -> Void)
    func verificationCodeViewControllerDidFinish(_ viewController: VerificationCodeViewController)
}

private enum VerificationCodeViewControllerState {
    case requestingCode
    case validatingCode
    case enteringCode
    case invalidCode
    case validatedCode
    case requestError
}

class VerificationCodeViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: VerificationCodeViewControllerDelegate?

    private var state: VerificationCodeViewControllerState = .requestingCode {
        didSet { updateUI() }
    }

    let scrollView = UIScrollView()
    var scrollViewBottomMargin: NSLayoutConstraint?

    let logo = UIImageView()

    let labelTitle = UILabel()
    let labelError = UILabel()

    let textFieldCode = UITextField()
    lazy var codeEntryField: UIView = { textFieldCode.withTextFieldBackground() }()
    var inputVerticalCenterConstraint: NSLayoutConstraint?

    let buttonRetryCodeRequest = UIButton()
    var retryAvailableDate = Date.distantFuture

    let activityIndicatorView = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        labelTitle.translatesAutoresizingMaskIntoConstraints = false
        labelTitle.font = .systemFont(forTextStyle: .title1, weight: .medium)
        labelTitle.numberOfLines = 0
        labelTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        if let formattedNumber = delegate?.formattedPhoneNumber {
            labelTitle.text = Localizations.registrationCodeInstructions(formattedNumber: formattedNumber)
        }

        activityIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        activityIndicatorView.startAnimating()

        let hStackView = UIStackView(arrangedSubviews: [labelTitle, activityIndicatorView])
        hStackView.translatesAutoresizingMaskIntoConstraints = false
        hStackView.axis = .horizontal
        hStackView.distribution = .fill
        hStackView.alignment = .center

        textFieldCode.translatesAutoresizingMaskIntoConstraints = false
        textFieldCode.font = .monospacedDigitSystemFont(ofSize: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).pointSize, weight: .regular)
        textFieldCode.delegate = self
        textFieldCode.textContentType = .oneTimeCode
        textFieldCode.keyboardType = .numberPad
        textFieldCode.addTarget(self, action: #selector(textFieldCodeEditingChanged), for: .editingChanged)

        let stackView = UIStackView(arrangedSubviews: [hStackView, codeEntryField, labelError])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 32

        labelError.textColor = .red
        labelError.textAlignment = .center
        labelError.font = .preferredFont(forTextStyle: .footnote)
        labelError.numberOfLines = 0

        buttonRetryCodeRequest.setTitle(Localizations.registrationCodeResend, for: .normal)
        buttonRetryCodeRequest.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        buttonRetryCodeRequest.setTitleColor(.secondaryLabel, for: .normal)
        buttonRetryCodeRequest.translatesAutoresizingMaskIntoConstraints = false
        buttonRetryCodeRequest.addTarget(self, action: #selector(didTapResendCode), for: .touchUpInside)
        buttonRetryCodeRequest.setContentCompressionResistancePriority(.required, for: .vertical)

        // View hierarchy

        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)
        scrollView.addSubview(buttonRetryCodeRequest)

        view.addSubview(scrollView)

        // Constraints

        scrollView.constrain([.leading, .trailing, .top], to: view)
        scrollViewBottomMargin = scrollView.constrain(anchor: .bottom, to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 32)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 32).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: buttonRetryCodeRequest.topAnchor, constant: -12).isActive = true
        inputVerticalCenterConstraint = stackView.constrain(anchor: .centerY, to: scrollView, priority: .defaultHigh)

        buttonRetryCodeRequest.constrainMargin(anchor: .leading, to: scrollView)
        buttonRetryCodeRequest.constrain(anchor: .bottom, to: scrollView.contentLayoutGuide)

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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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

    @objc
    func textFieldCodeEditingChanged(_ sender: Any) {
        state = .enteringCode
        if verificationCode.count == 6 {
            validateCode()
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.rangeOfCharacter(from: NSCharacterSet.decimalDigits.inverted) == nil else { return false }
        let resultingLength = (textField.text?.count ?? 0) - range.length + string.count
        return resultingLength <= 6
    }

    private var verificationCode: String {
        get { (textFieldCode.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func updateUI() {
        let isWaiting = state == .requestingCode || state == .validatingCode
        let shouldHideInput = state == .requestingCode || state == .requestError
        let canEnterText = state == .enteringCode || state == .invalidCode
        let canRequestNewCode = (state == .enteringCode && Date() > retryAvailableDate) || state == .invalidCode
        let shouldShowError = state == .invalidCode || state == .requestError
        let errorText = state == .invalidCode ? Localizations.registrationCodeIncorrect : Localizations.registrationCodeRequestError

        activityIndicatorView.alpha = isWaiting ? 1 : 0
        labelTitle.isHidden = shouldHideInput
        codeEntryField.isHidden = shouldHideInput
        buttonRetryCodeRequest.isHidden = !canRequestNewCode
        textFieldCode.isEnabled = canEnterText
        labelError.text = errorText
        labelError.alpha = shouldShowError ? 1 : 0
    }

    @objc
    func didTapResendCode() {
        guard state != .requestingCode else { return }
        textFieldCode.text = ""
        requestVerificationCode()
    }

    // MARK: Code Request

    func requestVerificationCode() {
        guard let delegate = delegate else {
            DDLogError("VerificationCodeViewController/validateCode/error missing delegate")
            return
        }

        state = .requestingCode
        retryAvailableDate = .distantFuture

        delegate.requestVerificationCode() { [weak self] result in
            guard let self = self else { return }
            DDLogInfo("VerificationCodeViewController/requestVerificationCode/result: \(result)")
            switch result {
            case .success(let retryDelay):
                self.state = .enteringCode
                self.textFieldCode.becomeFirstResponder()
                self.retryAvailableDate = Date().addingTimeInterval(retryDelay)
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay + 1) {
                    self.updateUI()
                }

            case .failure(let error):
                if let codeRequestError = error as? VerificationCodeRequestError {
                    switch codeRequestError {
                    case .notInvited:
                        let alert = UIAlertController(
                            title: Localizations.registrationInviteOnlyTitle,
                            message: Localizations.registrationInviteOnlyText,
                            preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel))
                        self.present(alert, animated: true)
                    case .invalidClientVersion:
                        let alert = self.getAppUpdateAlertController()
                        self.present(alert, animated: true)
                    default:
                        self.state = .requestError
                    }
                } else {
                    self.state = .requestError
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

        state = .validatingCode

        delegate.confirmVerificationCode(verificationCode) { [weak self] result in
            guard let self = self else { return }
            DDLogInfo("VerificationCodeViewController/validateCode/result: \(result)")
            switch result {
            case .success:
                self.state = .validatedCode
                self.delegate?.verificationCodeViewControllerDidFinish(self)
            case .failure(let error):
                if .invalidClientVersion == error as? VerificationCodeValidationError {
                    let alert = self.getAppUpdateAlertController()
                    self.present(alert, animated: true)
                } else {
                    self.state = .invalidCode
                    self.textFieldCode.becomeFirstResponder()
                }
            }
        }
    }

    private func getAppUpdateAlertController() -> UIAlertController {
        let alert = UIAlertController(
            title: Localizations.appUpdateNoticeTitle,
            message: Localizations.appUpdateNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonUpdate, style: .default, handler: { action in
            DDLogInfo("VerificationCodeViewController/updateNotice/update clicked")
            let urlString = "itms-apps://apple.com/app/1501583052"
            guard let customAppURL = URL(string: urlString),
                  UIApplication.shared.canOpenURL(customAppURL) else
            {
                DDLogError("VerificationCodeViewController/updateNotice/error unable to open \(urlString)")
                return
            }
            UIApplication.shared.open(customAppURL, options: [:], completionHandler: nil)
        }))
        return alert
    }
}
