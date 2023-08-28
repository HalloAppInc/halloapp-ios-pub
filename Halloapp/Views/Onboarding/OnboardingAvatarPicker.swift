//
//  OnboardingAvatarPicker.swift
//  HalloApp
//
//  Created by Tanveer on 8/15/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core

class OnboardingAvatarPicker: UIViewController {

    private static let avatarDiameter: CGFloat = 115
    private static let cameraViewDiameter: CGFloat = 40

    private var avatarMediaCancellable: AnyCancellable?

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

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)

        let stack = UIStackView(arrangedSubviews: [avatarButton, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center

        view.addSubview(stack)
        stack.addSubview(cameraView)

        let constant = (sqrt(2) * Self.avatarDiameter / 2) / 2

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            avatarButton.widthAnchor.constraint(equalToConstant: Self.avatarDiameter),
            avatarButton.heightAnchor.constraint(equalToConstant: Self.avatarDiameter),

            cameraView.widthAnchor.constraint(equalToConstant: Self.cameraViewDiameter),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor),
            cameraView.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor, constant: constant),
            cameraView.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor, constant: constant),
        ])

        avatarButton.configureWithMenu { [weak self, weak avatarButton] in
            HAMenu.lazy {
                HAMenu {
                    HAMenuButton(title: Localizations.choosePhoto) {
                        self?.presentPhotoPicker()
                    }
                }
                .displayInline()

                if let avatarButton, avatarButton.avatarView.hasImage {
                    HAMenu {
                        HAMenuButton(title: Localizations.deletePhoto) {
                            let context = MainAppContext.shared
                            context.avatarStore.removeAvatar(for: context.userData.userId,
                                                             using: context.service)
                        }
                        .destructive()
                    }
                    .displayInline()
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("OnboardingAvatarPicker coder init not implemented...")
    }

    private func presentPhotoPicker() {
        let picker = MediaPickerViewController(config: .avatar) { [weak self] viewController, _, media, cancelled in
            guard !cancelled, let media = media.first else {
                return viewController.dismiss(animated: true)
            }

            viewController.reset(destination: nil, selected: [])

            let cropper = MediaEditViewController(config: .profile, mediaToEdit: [media], selected: 0) { viewController, media, _, cancelled in
                guard !cancelled, let media = media.first else {
                    return viewController.dismiss(animated: true)
                }

                Analytics.log(event: .onboardingAddedProfilePhoto)

                self?.avatarMediaCancellable = media.ready
                    .first { $0 }
                    .compactMap { _ in media.image }
                    .sink { image in
                        let context = MainAppContext.shared
                        context.avatarStore.uploadAvatar(image: image,
                                                         for: context.userData.userId,
                                                         using: context.service)
                    }

                self?.dismiss(animated: true)
            }

            let cropperNavigationController = UINavigationController(rootViewController: cropper)
            viewController.present(cropperNavigationController, animated: true)
        }

        let pickerNavigationController = UINavigationController(rootViewController: picker)
        pickerNavigationController.modalPresentationStyle = .fullScreen

        present(pickerNavigationController, animated: true)
    }
}

// MARK: - Localization

extension Localizations {

    static var optionalTitle: String {
        NSLocalizedString("optional.title",
                          value: "Optional",
                          comment: "Title denoting something that is optional.")
    }

    static var choosePhoto: String {
        NSLocalizedString("choose.photo",
                          value: "Choose Photo",
                          comment: "Prompts the user to choose a photo.")
    }
}
