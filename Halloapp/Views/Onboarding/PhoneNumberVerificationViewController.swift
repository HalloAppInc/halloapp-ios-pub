//
//  PhoneNumberVerificationViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/15/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core
import CocoaLumberjackSwift

extension PhoneNumberVerificationViewController {

    private enum State {
        case requestingCode
        case enteringCode
        case confirmingCode
        case invalidCode
        case validCode
        case requestError
    }
}

class PhoneNumberVerificationViewController: UIViewController {

    let registrationManager: RegistrationManager
    let registrationNumber: RegistrationPhoneNumber

    private var state: State = .requestingCode {
        didSet { updateState() }
    }

    private var requestCodeTask: Task<Void, Never>?
    private var hasEnteredValidCode = false

    private var cancellables: Set<AnyCancellable> = []
    private var timeoutCancellable: AnyCancellable?

    private lazy var logoView: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = image
        view.tintColor = .lavaOrange
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var scrollViewBottomConstraint: NSLayoutConstraint = {
        let constraint = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        return constraint
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [numberLabel, codeTextField, invalidCodeLabel, buttonStack, UIView()])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 0, right: 20)
        stack.axis = .vertical

        stack.spacing = 50
        stack.setCustomSpacing(20, after: numberLabel)
        stack.setCustomSpacing(20, after: invalidCodeLabel)

        return stack
    }()

    private lazy var numberLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .body)
        label.text = Localizations.registrationCodeInstructions(formattedNumber: registrationNumber.formattedNumber)
        return label
    }()

    private lazy var codeTextField: VerificationCodeTextField = {
        let textField = VerificationCodeTextField()
        textField.tintColor = .systemBlue
        textField.delegate = self
        textField.addTarget(self, action: #selector(codeTextFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [resendStack, requestVoiceStack, wrongNumberButton])
        stack.axis = .vertical
        stack.alignment = .leading
        return stack
    }()

    private lazy var resendStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [resendCodeButton, resendCodeTimeoutLabel])
        stack.axis = .horizontal
        stack.spacing = 20
        return stack
    }()

    private lazy var resendCodeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizations.registrationCodeResend, for: .normal)
        button.titleLabel?.font = .systemFont(forTextStyle: .footnote, weight: .regular, maximumPointSize: 30)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(resendCodeButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var resendCodeTimeoutLabel: UILabel = {
        let label = UILabel()
        label.font = resendCodeButton.titleLabel?.font
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var timeoutFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]
        return formatter
    }()

    private lazy var requestVoiceStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [requestVoiceButton, requestVoiceTimeoutLabel])
        stack.axis = .horizontal
        stack.spacing = 20
        return stack
    }()

    private lazy var requestVoiceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizations.registrationCodeResendByVoice, for: .normal)
        button.titleLabel?.font = resendCodeButton.titleLabel?.font
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(requestVoiceButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var requestVoiceTimeoutLabel: UILabel = {
        let label = UILabel()
        label.font = requestVoiceButton.titleLabel?.font
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var wrongNumberButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizations.registrationWrongNumber, for: .normal)
        button.titleLabel?.font = .systemFont(forTextStyle: .footnote, weight: .medium, maximumPointSize: 30)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(wrongNumberButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var invalidCodeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.text = Localizations.registrationCodeIncorrect
        label.numberOfLines = 0
        return label
    }()

    private lazy var registrationSuccessStack: UIStackView = {
        let emojiLabel = UILabel()
        let messageLabel = UILabel()

        emojiLabel.text = "🎉"
        emojiLabel.font = .systemFont(ofSize: 46)

        messageLabel.text = Localizations.registrationSuccess
        messageLabel.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        messageLabel.textColor = .lavaOrange

        let stack = UIStackView(arrangedSubviews: [emojiLabel, messageLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10

        stack.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
        stack.alpha = 0

        return stack
    }()

    init(registrationManager: RegistrationManager, registrationNumber: RegistrationPhoneNumber) {
        self.registrationManager = registrationManager
        self.registrationNumber = registrationNumber
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PhoneNumberVerificationViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        view.backgroundColor = .feedBackground

        view.addSubview(logoView)
        view.addSubview(scrollView)
        scrollView.addSubview(vStack)
        vStack.addSubview(registrationSuccessStack)

        NSLayoutConstraint.activate([
            logoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            logoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logoView.heightAnchor.constraint(equalToConstant: 30),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 10),
            scrollViewBottomConstraint,

            vStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            registrationSuccessStack.topAnchor.constraint(equalTo: codeTextField.bottomAnchor, constant: 30),
            registrationSuccessStack.centerXAnchor.constraint(equalTo: vStack.centerXAnchor),
            registrationSuccessStack.leadingAnchor.constraint(greaterThanOrEqualTo: vStack.leadingAnchor),
            registrationSuccessStack.trailingAnchor.constraint(lessThanOrEqualTo: vStack.trailingAnchor),
        ])

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(keyboardSwipe))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)

        formSubscriptions()
        requestCodeTask = Task { await requestVerificationCode(byVoice: false) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        requestCodeTask?.cancel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        codeTextField.becomeFirstResponder()
    }

    private func formSubscriptions() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in
                self?.animateKeyboardDisplay(info: $0, showing: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in
                self?.animateKeyboardDisplay(info: $0, showing: false)
            }
            .store(in: &cancellables)
    }

    private func updateState() {
        var resendButtonsEnabled = timeoutCancellable == nil
        let hideResendTimeout = timeoutCancellable == nil
        var hideButtonStack = false
        var hideErrorLabel = true

        switch state {
        case .requestingCode:
            resendButtonsEnabled = false
        case .enteringCode:
            break
        case .requestError:
            resendButtonsEnabled = true
        case .confirmingCode:
            resendButtonsEnabled = false
        case .validCode:
            hideButtonStack = true
        case .invalidCode:
            hideErrorLabel = false
        }

        resendCodeButton.isEnabled = resendButtonsEnabled
        requestVoiceButton.isEnabled = resendButtonsEnabled

        resendCodeTimeoutLabel.alpha = hideResendTimeout ? 0 : 1
        requestVoiceTimeoutLabel.alpha = hideResendTimeout ? 0 : 1
        buttonStack.alpha = hideButtonStack ? 0 : 1

        if hideErrorLabel != invalidCodeLabel.isHidden {
            invalidCodeLabel.isHidden = hideErrorLabel
        }

        switch state {
        case .confirmingCode:
            codeTextField.resignFirstResponder()
        case .validCode where !hasEnteredValidCode:
            hasEnteredValidCode = true
            transitionAfterSuccess()
        default:
            break
        }
    }

    private func animateKeyboardDisplay(info: KeyboardNotificationInfo, showing: Bool) {
        scrollViewBottomConstraint.constant = showing ? -info.endFrame.height : 0
        UIView.animate(withKeyboardNotificationInfo: info) {
            self.view.layoutIfNeeded()
        }
    }

    private func transitionAfterSuccess() {
        let vc = NameInputViewController(registrationManager: registrationManager)

        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
            self.registrationSuccessStack.alpha = 1
            self.registrationSuccessStack.transform = .identity
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    @MainActor
    private func requestVerificationCode(byVoice: Bool) async {
        state = .requestingCode
        DDLogInfo("PhoneNumberVerificationViewController/requestVerificationCode byVoice [\(byVoice)]")
        let result = await registrationManager.requestVerificationCode(byVoice: byVoice)

        if Task.isCancelled {
            DDLogInfo("PhoneNumberVerificationViewController/requestVerificationCode byVoice [\(byVoice)] cancelled")
            return
        }

        switch result {
        case .success(let interval):
            DDLogInfo("PhoneNumberVerificationViewController/requestVerificationCode byVoice [\(byVoice) success")
            handleVerificationCodeRequestSuccess(interval)
            state = .enteringCode
        case .failure(let errorResponse):
            DDLogError("PhoneNumberVerificationViewController/requestVerificationCode byVoice [\(byVoice) failure")
            handleVerificationCodeRequestError(errorResponse)
            state = .requestError
        }
    }

    private func handleVerificationCodeRequestSuccess(_ timeInterval: TimeInterval) {
        setupRetryTimer(interval: timeInterval)
    }

    private func setupRetryTimer(interval: TimeInterval) {
        DDLogInfo("PhoneNumberVerificationViewController/setupRetryTimer with interval [\(interval)]")
        updateTimerLabels(interval)

        timeoutCancellable = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .scan(interval) { interval, _ in
                interval - 1
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateTimerLabels($0)
            }
    }

    private func updateTimerLabels(_ timeInterval: TimeInterval) {
        guard timeInterval >= 0 else {
            timeoutCancellable = nil
            return updateState()
        }

        let formatted = timeoutFormatter.string(from: timeInterval)
        resendCodeTimeoutLabel.text = formatted
        requestVoiceTimeoutLabel.text = formatted
    }

    private func handleVerificationCodeRequestError(_ response: RegistrationErrorResponse) {
        guard let error = response.error as? VerificationCodeRequestError else {
            return
        }

        switch error {
        case .notInvited:
            // needed?
            break
        case .invalidPhoneNumber(reason: let reason):
            presentInvalidPhoneNumberAlert(reason: reason)
        case .invalidClientVersion:
            presentInvalidClientVersionAlert()
        case .retriedTooSoon:
            if let delay = response.retryDelay {
                setupRetryTimer(interval: delay)
            }

            fallthrough
        case .smsFailure, .requestCreationError, .malformedResponse:
            state = .requestError
        }
    }

    @MainActor
    private func confirmVerificationCode(_ code: String) async {
        state = .confirmingCode
        let result = await registrationManager.confirmVerificationCode(code, pushOS: nil)

        switch result {
        case .success:
            DDLogInfo("PhoneNumberVerificationViewController/confirmVerificationCode/valid code [\(code)]")
            registrationManager.didCompleteRegistrationFlow()
            state = .validCode

        case .failure(let error):
            DDLogError("PhoneNumberVerificationViewController/confirmVerificationCode/invalid code [\(code)] error: [\(String(describing: error))]")
            state = .invalidCode
        }
    }

    @objc
    private func keyboardSwipe(_ gesture: UISwipeGestureRecognizer) {
        view.endEditing(true)
    }

    private func presentInvalidPhoneNumberAlert(reason: VerificationCodeRequestError.InvalidPhoneNumberReason?) {
        let alert = UIAlertController(title: Localizations.registrationInvalidPhoneTitle,
                                    message: Localizations.registrationInvalidPhoneText(reason: reason),
                             preferredStyle: .alert)

        alert.addAction(.init(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })

        present(alert, animated: true)
    }

    private func presentInvalidClientVersionAlert() {
        let alert = UIAlertController(title: Localizations.appUpdateNoticeTitle,
                                    message: Localizations.appUpdateNoticeText,
                             preferredStyle: .alert)

        alert.addAction(.init(title: Localizations.buttonUpdate, style: .default) { _ in
            guard
                let appURL = AppContext.appStoreURL,
                UIApplication.shared.canOpenURL(appURL)
            else {
                DDLogError("PhoneNumberVerificationViewController/invalid client/error unable to open [\(AppContext.appStoreURL?.absoluteString ?? "nil")]")
                return
            }

            UIApplication.shared.open(appURL)
        })
    }
}

// MARK: - Button / gesture selectors

extension PhoneNumberVerificationViewController {

    @objc
    private func wrongNumberButtonPushed(_ button: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func resendCodeButtonPushed(_ button: UIButton) {
        requestCodeTask = Task { await requestVerificationCode(byVoice: false) }
    }

    @objc
    private func requestVoiceButtonPushed(_ button: UIButton) {
        requestCodeTask = Task { await requestVerificationCode(byVoice: true) }
    }
}

// MARK: - UITextFieldDelegate methods

extension PhoneNumberVerificationViewController: UITextFieldDelegate {

    @objc
    private func codeTextFieldDidChange(_ textField: UITextField) {
        if let code = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), code.count == 6 {
            Task { await confirmVerificationCode(code) }
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.rangeOfCharacter(from: NSCharacterSet.decimalDigits.inverted) == nil else {
            return false
        }

        let resultingLength = (textField.text?.count ?? 0) - range.length + string.count
        return resultingLength <= 6
    }
}

// MARK: - Localization

extension Localizations {

    static var registrationWrongNumber: String {
        NSLocalizedString("registration.wrong.number",
                   value: "Wrong number?",
                 comment: "Title of the button that allows the user to go back and re-enter their number during registration")
    }

    static var registrationSuccess: String {
        NSLocalizedString("registration.you.are.in",
                   value: "You're in!",
                 comment: "Message shown to the user once they have successfully registered.")
    }
}
