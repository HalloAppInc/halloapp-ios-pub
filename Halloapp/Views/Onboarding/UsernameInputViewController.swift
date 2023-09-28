//
//  UsernameInputViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/15/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core
import CocoaLumberjackSwift

extension UsernameInputViewController {

    private enum State {
        case typing
        case validating
        case valid
        case invalid(error: ChangeUsernameError)
    }
}

class UsernameInputViewController: UIViewController {

    let onboarder: any Onboarder

    private var cancellables: Set<AnyCancellable> = []
    private var setUsernameTask: Task<Void, Never>?

    private var state: State = .typing {
        didSet { updateState() }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let avatarPicker: OnboardingAvatarPicker = {
        let picker = OnboardingAvatarPicker()
        return picker
    }()

    private let promptLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledGothamFont(ofSize: 16, weight: .medium, scalingTextStyle: .footnote)
        label.textColor = .lavaOrange
        label.adjustsFontSizeToFitWidth = true
        label.numberOfLines = 2
        return label
    }()

    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.tintColor =  .systemBlue
        textField.textContentType = .name
        textField.returnKeyType = .next
        textField.spellCheckingType = .no
        return textField
    }()

    private let usernameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.tintColor =  .systemBlue
        textField.returnKeyType = .done
        textField.spellCheckingType = .no
        textField.autocapitalizationType = .none
        return textField
    }()

    private let nextButton: UIButton = {
        let button = OnboardingConstants.AdvanceButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var nextButtonBottomConstraint: NSLayoutConstraint = {
        nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                           constant: -OnboardingConstants.bottomButtonBottomDistance)
    }()

    init(onboarder: any Onboarder) {
        self.onboarder = onboarder
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("UsernameInputViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        avatarPicker.willMove(toParent: self)

        let nameTextFieldContainer = OnboardingConstants.TextFieldContainerView()
        let usernameTextFieldContainer = OnboardingConstants.TextFieldContainerView()
        nameTextFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        usernameTextFieldContainer.translatesAutoresizingMaskIntoConstraints = false

        let vStack = UIStackView(arrangedSubviews: [avatarPicker.view, promptLabel, nameTextFieldContainer, usernameTextFieldContainer])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 10
        vStack.setCustomSpacing(35, after: avatarPicker.view)
        vStack.setCustomSpacing(20, after: promptLabel)

        scrollView.layoutMargins = .init(top: 0, left: 20, bottom: 0, right: 20)

        nameTextFieldContainer.addSubview(nameTextField)
        usernameTextFieldContainer.addSubview(usernameTextField)
        scrollView.addSubview(vStack)
        view.addSubview(scrollView)
        view.addSubview(nextButton)

        let vStackCenterConstraint = vStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        vStackCenterConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            nameTextField.leadingAnchor.constraint(equalTo: nameTextFieldContainer.layoutMarginsGuide.leadingAnchor),
            nameTextField.trailingAnchor.constraint(equalTo: nameTextFieldContainer.layoutMarginsGuide.trailingAnchor),
            nameTextField.topAnchor.constraint(equalTo: nameTextFieldContainer.layoutMarginsGuide.topAnchor),
            nameTextField.bottomAnchor.constraint(equalTo: nameTextFieldContainer.layoutMarginsGuide.bottomAnchor),

            usernameTextField.leadingAnchor.constraint(equalTo: usernameTextFieldContainer.layoutMarginsGuide.leadingAnchor),
            usernameTextField.trailingAnchor.constraint(equalTo: usernameTextFieldContainer.layoutMarginsGuide.trailingAnchor),
            usernameTextField.topAnchor.constraint(equalTo: usernameTextFieldContainer.layoutMarginsGuide.topAnchor),
            usernameTextField.bottomAnchor.constraint(equalTo: usernameTextFieldContainer.layoutMarginsGuide.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -10),

            vStackCenterConstraint,
            vStack.leadingAnchor.constraint(equalTo: scrollView.layoutMarginsGuide.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.layoutMarginsGuide.trailingAnchor),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: scrollView.topAnchor),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.layoutMarginsGuide.widthAnchor),

            nextButtonBottomConstraint,
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        nameTextField.placeholder = Localizations.nameTitle.lowercased()
        usernameTextField.placeholder = Localizations.usernameTitle.lowercased()
        nextButton.setTitle(Localizations.buttonNext, for: .normal)
        nextButton.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)

        for textField in [nameTextField, usernameTextField] {
            textField.delegate = self
            textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        }

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] keyboardInfo in
                self?.updateLayout(using: keyboardInfo, showing: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] keyboardInfo in
                self?.updateLayout(using: keyboardInfo, showing: false)
            }
            .store(in: &cancellables)

        avatarPicker.avatarButton.configure(userId: MainAppContext.shared.userData.userId,
                                            using: MainAppContext.shared.avatarStore)
        addChild(avatarPicker)

        nameTextField.text = onboarder.name
        usernameTextField.text = onboarder.username

        updateState()
    }

    private func updateLayout(using keyboardInfo: KeyboardNotificationInfo, showing: Bool) {
        let constant: CGFloat
        if showing {
            constant = -keyboardInfo.endFrame.height + view.safeAreaInsets.bottom - OnboardingConstants.advanceButtonKeyboardBottomPadding
        } else {
            constant = -OnboardingConstants.bottomButtonBottomDistance
        }

        nextButtonBottomConstraint.constant = constant
        UIView.animate(withKeyboardNotificationInfo: keyboardInfo) {
            self.view.layoutIfNeeded()
        }
    }

    private func updateState() {
        var promptTextColor = UIColor.lavaOrange
        var promptText = Localizations.selectUsernamePrompt
        var enableNextButton = false
        var shouldAdvance = false

        switch state {
        case .typing:
            let nameLength = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            let usernameLength = usernameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            enableNextButton = nameLength > 1 && usernameLength > 2

        case .validating:
            break
        case .valid:
            shouldAdvance = true

        case .invalid(let error):
            let errorDescription = error.errorDescription ?? ""
            if case .alreadyTaken = error {
                promptText = String(format: errorDescription, usernameTextField.text ?? "")
            } else {
                promptText = errorDescription
            }

            promptTextColor = .systemRed
        }

        promptLabel.textColor = promptTextColor
        promptLabel.text = promptText
        nextButton.isEnabled = enableNextButton

        if shouldAdvance, let viewController = onboarder.nextViewController() {
            navigationController?.setViewControllers([viewController], animated: true)
        }
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        let nameText = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let usernameText = usernameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        onboarder.set(name: nameText)

        setUsernameTask = Task {
            do {
                try await onboarder.set(username: usernameText)
                if Task.isCancelled {
                    return
                }
                DDLogInfo("UsernameInputViewController/setUsernameTask/successfully set username")
                state = .valid
            } catch {
                DDLogInfo("UsernameInputViewController/validate/failed to set [\(usernameText)] \(String(describing: error))")
                state = .invalid(error: error as? ChangeUsernameError ?? .other)
            }
        }
    }
}

// MARK: - UITextFieldDelegate methods

extension UsernameInputViewController: UITextFieldDelegate {

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        setUsernameTask?.cancel()
        state = .typing
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text, let range = Range(range, in: text) else {
            return true
        }

        let updated = text.replacingCharacters(in: range, with: string)
        let updatedLength = updated.count

        if updatedLength > 0, updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        return updatedLength <= 25
    }
}

// MARK: - Localization

extension Localizations {

    static var nameTitle: String {
        NSLocalizedString("name.title",
                          value: "Name",
                          comment: "Indicates the user's name.")
    }

    static var usernameTitle: String {
        NSLocalizedString("username.title",
                          value: "Username",
                          comment: "Indicates the user's username.")
    }

    static var selectUsernamePrompt: String {
        NSLocalizedString("select.username.prompt",
                          value: "Enter your name and choose a username",
                          comment: "Prompts the user to choose their username.")
    }
}
