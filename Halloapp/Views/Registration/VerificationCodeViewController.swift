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

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 30
}

protocol VerificationCodeViewControllerDelegate: AnyObject {
    var formattedPhoneNumber: String? { get }
    func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, Error>) -> Void)
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
    let errorLabel = UILabel()

    let textFieldCode = UITextField()
    lazy var codeEntryField: UIView = { textFieldCode.withTextFieldBackground() }()
    var inputVerticalCenterConstraint: NSLayoutConstraint?

    let buttonRetryCodeRequest = UIButton()
    let buttonRetryCodeByVoiceRequest = UIButton()
    var retryAvailableDate = Date.distantFuture

    let activityIndicatorView = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .primaryBg

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        labelTitle.translatesAutoresizingMaskIntoConstraints = false
        labelTitle.font = .systemFont(forTextStyle: .title1, weight: .medium, maximumPointSize: Constants.MaxFontPointSize)
        labelTitle.numberOfLines = 0
        labelTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        if let formattedNumber = delegate?.formattedPhoneNumber {
            labelTitle.text = Localizations.registrationCodeInstructions(formattedNumber: formattedNumber)
        }

        activityIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        activityIndicatorView.startAnimating()

        let phoneRow = UIStackView(arrangedSubviews: [labelTitle, activityIndicatorView])
        phoneRow.translatesAutoresizingMaskIntoConstraints = false
        phoneRow.axis = .horizontal
        phoneRow.distribution = .fill
        phoneRow.alignment = .center

        textFieldCode.translatesAutoresizingMaskIntoConstraints = false
        textFieldCode.font = .systemFont(forTextStyle: .title3, weight: .regular, maximumPointSize: Constants.MaxFontPointSize - 2)
        textFieldCode.delegate = self
        textFieldCode.textContentType = .oneTimeCode
        textFieldCode.keyboardType = .numberPad
        textFieldCode.addTarget(self, action: #selector(textFieldCodeEditingChanged), for: .editingChanged)

        let stackView = UIStackView(arrangedSubviews: [phoneRow, codeEntryField, errorLabel, resendSMSRow, callMeRow])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 30
        stackView.setCustomSpacing(10, after: codeEntryField)
        stackView.setCustomSpacing(10, after: errorLabel)
        stackView.setCustomSpacing(15, after: resendSMSRow)

        errorLabel.textColor = .red
        errorLabel.textAlignment = .center
        errorLabel.font = .systemFont(forTextStyle: .footnote, maximumPointSize: Constants.MaxFontPointSize - 14)
        errorLabel.numberOfLines = 0

        buttonRetryCodeRequest.setTitle(Localizations.registrationCodeResend, for: .normal)
        buttonRetryCodeRequest.titleLabel?.font = .systemFont(forTextStyle: .footnote, maximumPointSize: Constants.MaxFontPointSize - 10)
        buttonRetryCodeRequest.setTitleColor(.secondaryLabel, for: .normal)
        buttonRetryCodeRequest.translatesAutoresizingMaskIntoConstraints = false
        buttonRetryCodeRequest.addTarget(self, action: #selector(didTapResendCode), for: .touchUpInside)
        buttonRetryCodeRequest.setContentCompressionResistancePriority(.required, for: .vertical)
        buttonRetryCodeRequest.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        buttonRetryCodeByVoiceRequest.setTitle(Localizations.registrationCodeResendByVoice, for: .normal)
        buttonRetryCodeByVoiceRequest.titleLabel?.font = .systemFont(forTextStyle: .footnote, maximumPointSize: Constants.MaxFontPointSize - 10)
        buttonRetryCodeByVoiceRequest.setTitleColor(.secondaryLabel, for: .normal)
        buttonRetryCodeByVoiceRequest.translatesAutoresizingMaskIntoConstraints = false
        buttonRetryCodeByVoiceRequest.addTarget(self, action: #selector(didTapResendCodeByVoice), for: .touchUpInside)
        buttonRetryCodeByVoiceRequest.setContentCompressionResistancePriority(.required, for: .vertical)
        buttonRetryCodeByVoiceRequest.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // View hierarchy

        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)

        view.addSubview(scrollView)

        // Constraints

        scrollView.constrain([.leading, .trailing, .top, .bottom], to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 10)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 32).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor).isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let effectiveContentHeight = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom + scrollView.adjustedContentInset.top
        scrollView.isScrollEnabled = effectiveContentHeight > self.scrollView.frame.height

        inputVerticalCenterConstraint?.constant = -scrollView.adjustedContentInset.top
    }

    private lazy var resendSMSRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ buttonRetryCodeRequest, spacer ])
        view.axis = .horizontal
        view.alignment = .leading
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var callMeRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ buttonRetryCodeByVoiceRequest, spacer ])
        view.axis = .horizontal
        view.alignment = .leading
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

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
        resendSMSRow.isHidden = !canRequestNewCode
        callMeRow.isHidden = !canRequestNewCode

        textFieldCode.isEnabled = canEnterText
        errorLabel.text = errorText
        errorLabel.alpha = shouldShowError ? 1 : 0
    }

    @objc
    func didTapResendCode() {
        guard state != .requestingCode else { return }
        DDLogInfo("VerificationCodeViewController/didTapResendCode")
        textFieldCode.text = ""
        requestVerificationCode()
    }

    @objc
    func didTapResendCodeByVoice() {
        guard state != .requestingCode else { return }
        DDLogInfo("VerificationCodeViewController/didTapResendCodeByVoice")
        textFieldCode.text = ""
        requestVerificationCode(byVoice: true)
    }

    // MARK: Code Request

    func requestVerificationCode(byVoice: Bool = false) {
        guard let delegate = delegate else {
            DDLogError("VerificationCodeViewController/validateCode/error missing delegate")
            return
        }

        state = .requestingCode
        retryAvailableDate = .distantFuture

        delegate.requestVerificationCode(byVoice: byVoice) { [weak self] result in
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
                        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel, handler: { [weak self] _ in
                            self?.navigationController?.popViewController(animated: true)
                        }))
                        self.present(alert, animated: true)

                    case .invalidClientVersion:
                        // TODO : how to handle this for AppClip?
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
            title: "Localizations.appUpdateNoticeTitle",
            message: "Localizations.appUpdateNoticeText",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonUpdate, style: .default, handler: { action in
            DDLogInfo("VerificationCodeViewController/updateNotice/update clicked")
            guard let customAppURL = AppContext.appStoreURL,
                  UIApplication.shared.canOpenURL(customAppURL) else
            {
                DDLogError("VerificationCodeViewController/updateNotice/error unable to open [\(AppContext.appStoreURL?.absoluteString ?? "nil")]")
                return
            }
            UIApplication.shared.open(customAppURL, options: [:], completionHandler: nil)
        }))
        return alert
    }
}
