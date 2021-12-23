//
//  VerificationCodeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 30
}

protocol VerificationCodeViewControllerDelegate: AnyObject {
    var formattedPhoneNumber: String? { get }
    func requestVerificationCode(byVoice: Bool, completion: @escaping (Result<TimeInterval, RegistrationErrorResponse>) -> Void)
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

    let progressBar = UIProgressView(progressViewStyle: .bar)
    var progressTimer = Timer()
    var sMSTimer = Timer()

    var retryDelayInSeconds = 0
    var progressCounter = 0.0

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
            let formattedNumberNonBreakingLines = formattedNumber.replacingOccurrences(of: " ", with: "\u{00a0}")
            labelTitle.text = Localizations.registrationCodeInstructions(formattedNumber: formattedNumberNonBreakingLines)
        }

        let phoneRow = UIStackView(arrangedSubviews: [labelTitle])
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
        stackView.setCustomSpacing(25, after: codeEntryField)
        stackView.setCustomSpacing(10, after: errorLabel)
        stackView.setCustomSpacing(10, after: resendSMSRow)

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

        // Progress indicator
        progressBar.progressTintColor = .systemBlue
        progressBar.trackTintColor = .secondaryLabel
        progressBar.progress = 0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true

        // View hierarchy

        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)

        scrollView.addSubview(progressBar)
        view.addSubview(scrollView)

        // Constraints

        scrollView.constrain([.leading, .trailing, .top, .bottom], to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 10)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        progressBar.constrain(anchor: .bottom, to: scrollView.contentLayoutGuide, constant: 5)
        progressBar.constrainMargin(anchor: .leading, to: scrollView)
        progressBar.constrainMargin(anchor: .trailing, to: scrollView)

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
        sMSTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateResendCodeTimer), userInfo: nil, repeats: true)
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
    private func updateResendCodeTimer() {
        if (retryDelayInSeconds > 0) {
            let seconds: Int = retryDelayInSeconds % 60
            let minutes: Int = (retryDelayInSeconds / 60) % 60
            buttonRetryCodeRequest.setTitle(Localizations.registrationCodeResend + " \(String(format: "%02d:%02d", minutes, seconds))", for: .normal)
            buttonRetryCodeRequest.isEnabled = false
            buttonRetryCodeRequest.setTitleColor(.secondaryLabel, for: .normal)
            // Voice Row
            buttonRetryCodeByVoiceRequest.setTitle(Localizations.registrationCodeResendByVoice + " \(String(format: "%02d:%02d", minutes, seconds))", for: .normal)
            buttonRetryCodeByVoiceRequest.isEnabled = false
            buttonRetryCodeByVoiceRequest.setTitleColor(.secondaryLabel, for: .normal)
            retryDelayInSeconds -= 1
        }
        if (retryDelayInSeconds <= 0) {
            sMSTimer.invalidate()
            buttonRetryCodeRequest.setTitle(Localizations.registrationCodeResend, for: .normal)
            buttonRetryCodeRequest.isEnabled = true
            buttonRetryCodeRequest.setTitleColor(.systemBlue, for: .normal)
            // Voice Row
            buttonRetryCodeByVoiceRequest.setTitle(Localizations.registrationCodeResendByVoice, for: .normal)
            buttonRetryCodeByVoiceRequest.isEnabled = true
            buttonRetryCodeByVoiceRequest.setTitleColor(.systemBlue, for: .normal)
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
        if (state == .invalidCode) {
            errorLabel.text =  Localizations.registrationCodeIncorrect
            errorLabel.alpha = 1
        } else {
            errorLabel.alpha = 0
        }

        let canEnterText = state == .enteringCode || state == .invalidCode || state == .requestError
        textFieldCode.isEnabled = canEnterText
        if (canEnterText) {
            self.textFieldCode.becomeFirstResponder()
        }

        let canRequestNewCodeByVoice = (state == .enteringCode && Date() > retryAvailableDate) || state == .invalidCode || state == .requestError
        buttonRetryCodeByVoiceRequest.isEnabled = canRequestNewCodeByVoice

        let isWaiting = state == .requestingCode || state == .validatingCode
        if (isWaiting) {
            progressTimer = Timer.scheduledTimer(timeInterval: 0.001, target: self, selector: #selector(setWaitingProgress), userInfo: nil, repeats: true)
            progressBar.isHidden = false
        } else {
            progressTimer.invalidate()
            progressBar.isHidden = true
        }
    }

    @objc
    func setWaitingProgress() {
        progressCounter += 0.01
        progressBar.setProgress(Float(progressCounter) / 100, animated: true)
        if progressCounter >= 100 {
            progressCounter = 0.01
            progressBar.progress = 0
            let color = self.progressBar.progressTintColor
            self.progressBar.progressTintColor = progressBar.trackTintColor
            self.progressBar.trackTintColor = color
        }
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
                self.setRetryTimers(retryDelay: retryDelay)
                DispatchQueue.main.async() {
                    self.updateUI()
                }

            case .failure(let errorResponse):
                switch errorResponse.error as? VerificationCodeRequestError {
                    case .notInvited:
                        let alert = UIAlertController(
                            title: Localizations.registrationInviteOnlyTitle,
                            message: Localizations.registrationInviteOnlyText,
                            preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel, handler: { [weak self] _ in
                            self?.navigationController?.popViewController(animated: true)
                        }))
                        self.present(alert, animated: true)

                    case .invalidPhoneNumber:
                        let alert = UIAlertController(
                            title: Localizations.registrationInvalidPhoneTitle,
                            message: Localizations.registrationInvalidPhoneText,
                            preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel, handler: { [weak self] _ in
                            self?.navigationController?.popViewController(animated: true)
                        }))
                        self.present(alert, animated: true)

                    case .invalidClientVersion:
                        let alert = self.getAppUpdateAlertController()
                        self.present(alert, animated: true)

                    case .retriedTooSoon:
                        DispatchQueue.main.async {
                            self.state = .requestError
                        }
                        
                        if let retryDelay = errorResponse.retryDelay {
                            self.setRetryTimers(retryDelay: retryDelay)
                        }
                    case .smsFailure, .requestCreationError, .malformedResponse, .none:
                        DispatchQueue.main.async {
                            self.state = .requestError
                        }
                    }
            }
        }
    }

    private func setRetryTimers(retryDelay: TimeInterval) {
        self.retryAvailableDate = Date().addingTimeInterval(retryDelay)
        self.retryDelayInSeconds = Int(retryDelay)
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
                // todo: handle errors better (e.g., request timeout)
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
