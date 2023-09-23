//
//  FriendMigrationInfoViewController.swift
//  HalloApp
//
//  Created by Tanveer on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class FriendMigrationInfoViewController: UIViewController {

    private let onboarder: any Onboarder

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 30, weight: .bold, scalingTextStyle: .footnote)
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .center
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 17)
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .center
        return label
    }()

    private let continueButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentEdgeInsets = .init(top: 14, left: 0, bottom: 14, right: 0)
        button.titleLabel?.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        return button
    }()

    init(onboarder: any Onboarder) {
        self.onboarder = onboarder
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("FriendMigrationInfoViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = .primaryWhiteBlack
        view.layoutMargins = .init(top: 10, left: 25, bottom: 10, right: 25)

        let image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")
        let imageView = UIImageView(image: image)
        imageView.preferredSymbolConfiguration = .init(pointSize: 37)
        imageView.tintColor = .primaryBlue

        let circleView = CircleView()
        circleView.layoutMargins = .init(top: 12, left: 12, bottom: 12, right: 12)
        circleView.fillColor = .secondarySystemFill

        let container = UIView()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        circleView.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(circleView)
        container.addSubview(titleLabel)
        container.addSubview(messageLabel)

        circleView.addSubview(imageView)
        view.addSubview(container)
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.topAnchor),
            container.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor),

            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: circleView.layoutMarginsGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: circleView.layoutMarginsGuide.trailingAnchor),
            imageView.topAnchor.constraint(greaterThanOrEqualTo: circleView.layoutMarginsGuide.topAnchor),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: circleView.layoutMarginsGuide.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            circleView.topAnchor.constraint(equalTo: container.topAnchor),
            circleView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            circleView.widthAnchor.constraint(equalTo: circleView.heightAnchor, multiplier: 1),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 17),

            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
        ])

        titleLabel.text = Localizations.friendMigrationTitle
        messageLabel.text = Localizations.friendMigrationMessage

        continueButton.setTitle(Localizations.buttonContinue, for: .normal)
        continueButton.setBackgroundColor(.primaryBlue, for: .normal)
        continueButton.setTitleColor(.white, for: .normal)

        continueButton.layer.cornerRadius = 10
        continueButton.layer.masksToBounds = true

        continueButton.addTarget(self, action: #selector(continuePushed), for: .touchUpInside)
    }

    @objc
    private func continuePushed(_ button: UIButton) {
        if let viewController = onboarder.nextViewController() {
            navigationController?.setViewControllers([viewController], animated: true)
        }
    }
}

// MARK: - Localization

extension Localizations {

    fileprivate static var friendMigrationTitle: String {
        NSLocalizedString("friend.migration.title",
                          value: "New Friendship Model on HalloApp",
                          comment: "Title when explaining the new friend network.")
    }

    fileprivate static var friendMigrationMessage: String {
        NSLocalizedString("friend.migration.message",
                          value: "Now you can search for people on HalloApp using their name or @username. Your existing HalloApp contacts now become your friends. You can remove existing contacts from friends at any time.",
                          comment: "Message explaining the new friend network.")
    }
}
