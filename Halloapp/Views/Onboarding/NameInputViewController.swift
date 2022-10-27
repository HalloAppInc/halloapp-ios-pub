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
    private var avatarUploadCancellable: AnyCancellable?

    @Published private var userName = ""

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarPicker, promptLabel, textFieldContainer, UIView()])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 40, left: 15, bottom: 0, right: 15)
        stack.spacing = 15
        stack.setCustomSpacing(25, after: avatarPicker)
        stack.setCustomSpacing(10, after: promptLabel)

        return stack
    }()

    private lazy var avatarPicker: OnboardingAvatarPicker = {
        let picker = OnboardingAvatarPicker()
        picker.avatarButton.configureWithMenu { [weak self] in
            HAMenu.lazy {
                self?.avatarMenu()
            }
        }

        return picker
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

        textField.textContentType = .name
        textField.returnKeyType = .done
        textField.spellCheckingType = .no
        textField.enablesReturnKeyAutomatically = true

        textField.setContentHuggingPriority(.required, for: .vertical)
        return textField
    }()

    private lazy var nextButtonBottomConstraint: NSLayoutConstraint = {
        let constraint = nextButtonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                constant: -OnboardingConstants.bottomButtonBottomDistance)
        return constraint
    }()

    private lazy var nextButtonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nextButton])
        let padding = OnboardingConstants.bottomButtonPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)
        stack.axis = .vertical
        stack.alignment = .center
        return stack
    }()

    private lazy var nextButton: RoundedRectChevronButton = {
        let button = RoundedRectChevronButton()
        button.backgroundTintColor = .lavaOrange
        button.setTitle(Localizations.buttonNext, for: .normal)
        button.tintColor = .white
        button.contentEdgeInsets = OnboardingConstants.bottomButtonInsets
        button.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)

        return button
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

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

        avatarPicker.avatarButton.configure(userId: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(keyboardSwipe))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)

        formSubscriptions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
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

        $userName
            .map { $0.isEmpty ? false : true }
            .assign(to: \.isEnabled, onWeak: nextButton)
            .store(in: &cancellables)
    }

    private func updateLayoutForKeyboard(info: KeyboardNotificationInfo, showing: Bool) {
        nextButtonBottomConstraint.constant = showing ? -info.endFrame.height + view.safeAreaInsets.bottom : -OnboardingConstants.bottomButtonBottomDistance
        UIView.animate(withKeyboardNotificationInfo: info) {
            self.view.layoutIfNeeded()
        }
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        guard textField.text != nil else {
            return
        }

        registrationManager.set(userName: userName)

        let onboardingManager: OnboardingManager
        if let demo = registrationManager as? DemoRegistrationManager {
            onboardingManager = DemoOnboardingManager(networkSize: demo.onboardingNetworkSize, completion: demo.completion)
        } else {
            onboardingManager = DefaultOnboardingManager()
        }

        hideKeyboard()
        let vc = PermissionsViewController(onboardingManager: onboardingManager)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc
    private func keyboardSwipe(_ gesture: UISwipeGestureRecognizer) {
        hideKeyboard()
    }

    private func hideKeyboard() {
        view.endEditing(true)
    }

    @HAMenuContentBuilder
    private func avatarMenu() -> HAMenu.Content {
        HAMenu {
            HAMenuButton(title: Localizations.takeOrChoosePhoto) { [weak self] in
                self?.presentPhotoPicker()
            }
        }
        .displayInline()

        if avatarPicker.avatarButton.avatarView.hasImage {
            HAMenu {
                HAMenuButton(title: Localizations.deletePhoto) { [weak self] in
                    self?.deleteAvatar()
                }
                .destructive()
            }
            .displayInline()
        }
    }

    private func presentPhotoPicker() {
        let picker = MediaPickerViewController(config: .avatar) { viewController, _, media, cancelled in
            guard !cancelled, let media = media.first else {
                return viewController.dismiss(animated: true)
            }

            let cropper = self.makePhotoCropper(with: media)
            cropper.modalPresentationStyle = .fullScreen

            viewController.reset(destination: nil, selected: [])
            viewController.present(cropper, animated: true)
        }

        let nc = UINavigationController(rootViewController: picker)
        nc.modalPresentationStyle = .fullScreen

        present(nc, animated: true)
    }

    private func makePhotoCropper(with media: PendingMedia) -> UIViewController {
        let cropper = MediaEditViewController(config: .profile,
                                         mediaToEdit: [media],
                                            selected: 0) { viewController, media, _, cancelled in

            guard !cancelled, let media = media.first else {
                return viewController.dismiss(animated: true)
            }

            self.avatarUploadCancellable = media.ready
                .first { $0 }
                .compactMap { _ in media.image }
                .sink { image in
                    let context = MainAppContext.shared
                    context.avatarStore.uploadAvatar(image: image, for: context.userData.userId, using: context.service)
                }

            // dismiss both the picker and the cropper
            self.dismiss(animated: true)
        }

        return UINavigationController(rootViewController: cropper)
    }

    private func deleteAvatar() {
        let context = MainAppContext.shared
        context.avatarStore.removeAvatar(for: context.userData.userId, using: context.service)
    }
}

// MARK: - UITextField delegate methods

extension NameInputViewController: UITextFieldDelegate {

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        let trimmed = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        userName = trimmed ?? ""
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

// MARK: - OnboardingAvatarPicker implementation

fileprivate class OnboardingAvatarPicker: UIView {

    private static let avatarDiameter: CGFloat = 115
    private static let cameraViewDiameter: CGFloat = 40

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarButton, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        return stack
    }()

    private(set) lazy var avatarButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .footnote, maximumPointSize: 22)
        label.textColor = .secondaryLabel
        label.text = Localizations.optionalTitle
        return label
    }()

    private lazy var cameraView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(systemName: "camera.fill")
        view.contentMode = .center
        view.backgroundColor = .primaryBlue
        view.tintColor = .white

        view.layer.cornerRadius = Self.cameraViewDiameter / 2

        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(vStack)
        vStack.addSubview(cameraView)

        let constant = (sqrt(2) * Self.avatarDiameter / 2) / 2

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarButton.widthAnchor.constraint(equalToConstant: Self.avatarDiameter),
            avatarButton.heightAnchor.constraint(equalToConstant: Self.avatarDiameter),

            cameraView.widthAnchor.constraint(equalToConstant: Self.cameraViewDiameter),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor),
            cameraView.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor, constant: constant),
            cameraView.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor, constant: constant),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("OnboardingAvatarPicker coder init not implemented...")
    }
}

// MARK: - Localizations

extension Localizations {

    static var registrationNamePrompt: String {
        NSLocalizedString("registration.name.prompt",
                   value: "How should we call you?",
                 comment: "Text prompting the user for their push name.")
    }

    static var optionalTitle: String {
        NSLocalizedString("optional.title",
                   value: "Optional",
                 comment: "Title that suggests something is optional.")
    }
}
