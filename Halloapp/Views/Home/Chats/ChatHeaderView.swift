//
//  ChatHeaderView.swift
//  HalloApp
//
//  Created by Tony Jiang on 12/16/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

protocol ChatHeaderViewDelegate: AnyObject {
    func chatHeaderViewOpenEncryptionBlog(_ chatHeaderView: ChatHeaderView)
    func chatHeaderViewUnblockContact(_ chatHeaderView: ChatHeaderView)
}

class ChatHeaderView: UIView {
    weak var delegate: ChatHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configureOrRefresh(with userID: UserID) {
        let isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userID)
        blockedContactBubbleColumn.isHidden = !isUserBlocked
    }

    private func setup() {
        addSubview(mainColumn)
        mainColumn.constrain(to: self)
    }

    private lazy var mainColumn: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ encryptionBubbleColumn, blockedContactBubbleColumn, spacer] )

        view.axis = .vertical
        view.alignment = .fill
        view.spacing = 20
        view.setCustomSpacing(20, after: encryptionBubble)

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 0, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var encryptionBubbleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ encryptionBubble ])
        view.axis = .vertical
        view.alignment = .fill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var encryptionBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ lockImageView, encryptionLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 5

        view.layoutMargins = UIEdgeInsets(top: 8, left: 15, bottom: 8, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatInfoBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openEncryptionBlog)))

        return view
    }()

    private lazy var lockImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "settingsPrivacy")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = UIColor.chatInfoBubble

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        return imageView
    }()

    private lazy var encryptionLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 4
        label.textAlignment = .center
        label.textColor = .chatInfoBubble
        label.font = UIFont.systemFont(ofSize: 12)
        label.adjustsFontForContentSizeCategory = true
        label.text = Localizations.chatEncryptionLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var blockedContactBubbleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ blockedContactBubble ])
        view.axis = .vertical
        view.alignment = .center
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    lazy var blockedContactBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ blockedContactLabel ])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatInfoBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(unblockContact)))
        return view
    }()

    private lazy var blockedContactLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 4
        label.textAlignment = .center
        label.textColor = .chatInfoBubble
        label.font = UIFont.systemFont(ofSize: 12)
        label.adjustsFontForContentSizeCategory = true
        label.text = Localizations.chatBlockedContactLabel

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    @objc private func openEncryptionBlog() {
        guard let delegate = delegate else { return }
        delegate.chatHeaderViewOpenEncryptionBlog(self)
    }

    @objc private func unblockContact() {
        guard let delegate = delegate else { return }
        delegate.chatHeaderViewUnblockContact(self)
    }

}

private extension Localizations {

    static var chatEncryptionLabel: String {
        NSLocalizedString("chat.encryption.label", value: "Chats are end-to-end encrypted and HalloApp does not have access to them. Tap to learn more.", comment: "Text shown at the top of the chat screen informing the user that the chat is end-to-end encrypted")
    }

    static var chatBlockedContactLabel: String {
        NSLocalizedString("chat.blocked.contact.label", value: "Contact is blocked, tap to unblock", comment: "Text shown at the top of the chat screen informing the user that the contact is blocked")
    }

}
