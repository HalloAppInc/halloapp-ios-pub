//
//  FeedPermissionAlert.swift
//  HalloApp
//
//  Created by Garrett on 5/24/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import UIKit

final class FeedPermissionAlert: UIView {

    struct Action {
        var title: String
        var handler: (FeedPermissionAlert) -> Void
    }

    var overlayID: String = UUID().uuidString

    let messageLabel = UILabel()
    let dismissButton = UIButton()
    let acceptButton = UIButton()
    var backgroundPanel = BlurView(effect: UIBlurEffect(style: .systemMaterial), intensity: 0.5)

    let dismissAction: Action
    let acceptAction: Action

    let messageSpacing: CGFloat = 8
    let buttonSpacing: CGFloat = 32

    init(message: String, acceptAction: Action, dismissAction: Action) {
        self.acceptAction = acceptAction
        self.dismissAction = dismissAction

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        backgroundPanel.backgroundColor = UIColor.label.withAlphaComponent(0.25)
        backgroundPanel.translatesAutoresizingMaskIntoConstraints = false
        backgroundPanel.layer.cornerRadius = 15
        backgroundPanel.clipsToBounds = true

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .callout)

        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        acceptButton.setTitle(acceptAction.title, for: .normal)
        acceptButton.setTitleColor(.systemBlue, for: .normal)
        acceptButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .semibold)
        acceptButton.addTarget(self, action: #selector(didTapAccept), for: .touchUpInside)
        acceptButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setTitle(dismissAction.title, for: .normal)
        dismissButton.setTitleColor(.label, for: .normal)
        dismissButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .semibold)
        dismissButton.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        dismissButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(backgroundPanel)
        addSubview(messageLabel)
        addSubview(dismissButton)
        addSubview(acceptButton)

        backgroundPanel.constrain(to: self)
        messageLabel.constrainMargins([.leading, .trailing, .top], to: self)

        dismissButton.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor).isActive = true

        acceptButton.leadingAnchor.constraint(equalTo: dismissButton.trailingAnchor, constant: buttonSpacing).isActive = true
        acceptButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: messageSpacing).isActive = true
        acceptButton.constrain([.top, .bottom], to: dismissButton)
        acceptButton.constrainMargins([.trailing, .bottom], to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTapAccept() {
        acceptAction.handler(self)
    }

    @objc
    private func didTapDismiss() {
        dismissAction.handler(self)
    }
}

extension FeedPermissionAlert: Overlay {

    var dismissBehavior: DismissBehavior {
        .dismissOnExplicitRequest
    }

    func display(in container: OverlayContainer) {
        UIView.animate(withDuration: 0.2) {
            container.addSubview(self)
            self.constrainMargins([.top, .leading, .trailing], to: container)
        }
    }

    func _dismiss() -> Future<Void, Never> {
        Future { promise in
            UIView.animate(
                withDuration: 0.2,
                animations: { self.alpha = 0 },
                completion: { _ in promise(.success(())) })
        }
    }


}
