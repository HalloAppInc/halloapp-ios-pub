//
//  UpdateContactsPermissionView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

class UpdateContactsPermissionView: UIView {

    private let settingsURL = URL(string: UIApplication.openSettingsURLString)
    private let learnMoreURL = URL(string: "https://halloapp.com/blog/why-address-book/")

    public override init(frame: CGRect) {
        super.init(frame: frame)
        let image = UIImage(named: "AvatarUser")
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.contactsAccessDenied
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        
        let settingsButton = UIButton()
        settingsButton.layer.masksToBounds = true
        settingsButton.setTitle(Localizations.buttonGoToSettings, for: .normal)
        settingsButton.setBackgroundColor(.systemBlue, for: .normal)
        settingsButton.setBackgroundColor(UIColor.systemBlue.withAlphaComponent(0.5), for: .highlighted)
        settingsButton.setBackgroundColor(.systemGray4, for: .disabled)
        settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        settingsButton.layer.cornerRadius = 19
        settingsButton.addTarget(self, action: #selector(didTapOpenSettings), for: .touchUpInside)

        let learnMoreButton = UIButton()
        learnMoreButton.setTitle(Localizations.buttonLearnMore, for: .normal)
        learnMoreButton.setTitleColor(.systemBlue, for: .normal)
        learnMoreButton.titleLabel?.font = .systemFont(forTextStyle: .footnote, weight: .medium)
        learnMoreButton.addTarget(self, action: #selector(didTapLearnMore), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [imageView, label, settingsButton, learnMoreButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        addSubview(stackView)
        stackView.constrainMargins(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func didTapOpenSettings() {
        guard let settingsURL = settingsURL else {
            DDLogError("UpdateContactsPermissionView/didTapOpenSettings/error settings-url-unavailable")
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    @objc
    private func didTapLearnMore() {
        guard let learnMoreURL = learnMoreURL else {
            DDLogError("UpdateContactsPermissionView/didTapLearnMore/error learn-more-url-unavailable")
            return
        }
        UIApplication.shared.open(learnMoreURL)
    }
}

private extension Localizations {
    static var contactsAccessDenied: String {
        NSLocalizedString(
            "contacts.access.denied",
            value: "Allow HalloApp access to your contacts so you can send and receive updates",
            comment: "Shown when user denies contacts permission"
        )
    }
}
