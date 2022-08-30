//
//  NameInputViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/16/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core

class NameInputViewController: UIViewController {

    let registrationManager: RegistrationManager

    private var cancellables: Set<AnyCancellable> = []

    @Published private var username = ""

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [profileHeader.view, promptLabel, textFieldContainer, UIView()])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 40, left: 15, bottom: 0, right: 15)
        stack.spacing = 15
        stack.setCustomSpacing(10, after: promptLabel)

        return stack
    }()

    private lazy var profileHeader: ProfileHeaderViewController = {
        let header = ProfileHeaderViewController()
        header.configureForCurrentUser(withName: "")
        header.view.setContentHuggingPriority(.required, for: .vertical)
        return header
    }()

    private lazy var promptLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.textColor = .lavaOrange
        label.adjustsFontSizeToFitWidth = true
        label.text = Localizations.registrationNamePrompt
        return label
    }()

    private lazy var textFieldContainer: ShadowView = {
        let view = ShadowView()
        view.backgroundColor = .feedPostBackground
        view.layer.cornerRadius = 10
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0.75
        view.layer.shadowOpacity = 1
        return view
    }()

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = Localizations.registrationNamePlaceholder
        textField.tintColor = .systemBlue
        textField.font = .systemFont(forTextStyle: .body)
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.textContentType = .name
        textField.returnKeyType = .done
        textField.spellCheckingType = .no
        textField.enablesReturnKeyAutomatically = true

        textField.setContentHuggingPriority(.required, for: .vertical)
        return textField
    }()

    private lazy var nextButtonBottomConstraint: NSLayoutConstraint = {
        let constraint = nextButtonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        return constraint
    }()

    private lazy var nextButtonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nextButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        stack.axis = .vertical
        stack.alignment = .center
        return stack
    }()

    private lazy var nextButton: RoundedRectChevronButton = {
        let button = RoundedRectChevronButton()
        button.backgroundTintColor = .lavaOrange
        button.setTitle(Localizations.buttonNext, for: .normal)
        button.tintColor = .white
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 80, bottom: 12, right: 80)
        button.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)

        return button
    }()

    init(registrationManager: RegistrationManager) {
        self.registrationManager = registrationManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("NameInputViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        view.backgroundColor = .feedBackground

        addChild(profileHeader)
        textFieldContainer.addSubview(textField)
        view.addSubview(nextButtonStack)
        view.addSubview(scrollView)
        scrollView.addSubview(vStack)

        let vStackCenterYConstraint = vStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        vStackCenterYConstraint.priority = .defaultHigh

        let textFieldInset: CGFloat = 12
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: textFieldContainer.leadingAnchor, constant: textFieldInset),
            textField.trailingAnchor.constraint(equalTo: textFieldContainer.trailingAnchor, constant: -textFieldInset),
            textField.topAnchor.constraint(equalTo: textFieldContainer.topAnchor, constant: textFieldInset),
            textField.bottomAnchor.constraint(equalTo: textFieldContainer.bottomAnchor, constant: -textFieldInset),

            nextButtonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nextButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nextButtonBottomConstraint,

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: nextButtonStack.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            vStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            vStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(keyboardSwipe))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)

        formSubscriptions()
    }

    private func formSubscriptions() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in
                self?.updateLayoutForKeyboard(info: $0, showing: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .compactMap { KeyboardNotificationInfo(userInfo: $0.userInfo) }
            .sink { [weak self] in
                self?.updateLayoutForKeyboard(info: $0, showing: false)
            }
            .store(in: &cancellables)

        $username
            .map { $0.isEmpty ? false : true }
            .assign(to: \.isEnabled, onWeak: nextButton)
            .store(in: &cancellables)
    }

    private func updateLayoutForKeyboard(info: KeyboardNotificationInfo, showing: Bool) {
        nextButtonBottomConstraint.constant = showing ? -info.endFrame.height + view.safeAreaInsets.bottom : 0
        UIView.animate(withKeyboardNotificationInfo: info) {
            self.view.layoutIfNeeded()
        }
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        guard let name = textField.text else {
            return
        }

        // TODO
        //registrationManager.set(userName: name)

        let onboardingManager: OnboardingManager
        if let _ = registrationManager as? DemoRegistrationManager {
            onboardingManager = DemoOnboardingManager(networkSize: 0, completion: { })
        } else {
            onboardingManager = DefaultOnboardingManager()
        }

        let vc = PermissionsViewController(onboardingManager: onboardingManager)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc
    private func keyboardSwipe(_ gesture: UISwipeGestureRecognizer) {
        view.endEditing(true)
    }
}

// MARK: - UITextField delegate methods

extension NameInputViewController: UITextFieldDelegate {

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        let trimmed = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        username = trimmed ?? ""
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text, let textRange = Range(range, in: text) else {
            return true
        }

        let updatedText = text.replacingCharacters(in: textRange, with: string)
        if updatedText.count > 1, updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        return updatedText.count <= 25
    }
}

// MARK: - Localizations

extension Localizations {

    static var registrationNamePrompt: String {
        NSLocalizedString("registration.name.prompt",
                   value: "How should we call you?",
                 comment: "Text prompting the user for their push name.")
    }
}
