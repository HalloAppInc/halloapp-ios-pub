//
//  MessageCellViewEvent.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import Core

public enum ChatLogEventType: Int16 {
    case whisperKeysChange = 0
    case addToAddressBook = 1
    case blocked = 2
    case unblocked = 3
}

protocol MessageChatEventViewDelegate: AnyObject {
    func messageChatHeaderViewAddToContacts(_ messageCellViewEvent: MessageCellViewEvent)
}

class MessageCellViewEvent: UICollectionViewCell {
    static var elementKind: String {
        return String(describing: MessageCellViewEvent.self)
    }

    weak var delegate: MessageChatEventViewDelegate?
    var eventType: ChatLogEventType?

    var messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.scaledSystemFont(ofSize: 12, weight: .regular)
        label.alpha = 0.80
        label.textColor = UIColor.black
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    private lazy var messageView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ messageLabel])
        view.layoutMargins = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 18)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = ShadowView(frame: view.bounds)
        subView.backgroundColor = UIColor.messageEventHeaderBackground
        subView.layer.cornerRadius = 7
        subView.layer.masksToBounds = false
        subView.translatesAutoresizingMaskIntoConstraints = false
        subView.layer.borderWidth = 0.5
        subView.layer.borderColor = UIColor.messageEventHeaderBorder.cgColor
        subView.layer.shadowColor = UIColor.black.cgColor
        subView.layer.shadowOpacity = 0.1
        subView.layer.shadowOffset = CGSize(width: 0, height: 1)
        subView.layer.shadowRadius = 0

        view.insertSubview(subView, at: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTapEvent)))
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.preservesSuperviewLayoutMargins = true
        contentView.addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            messageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    func configure(chatLogEventType: ChatLogEventType, userID: UserID) {
        eventType = chatLogEventType
        switch chatLogEventType {
        case .whisperKeysChange:
            let name = UserProfile.findOrCreate(with: userID, in: MainAppContext.shared.mainDataStore.viewContext).displayName
            messageLabel.text = Localizations.chatEventSecurityKeysChanged(name: name)
        case .blocked:
            messageLabel.text = Localizations.chatBlockedContactLabel
        case .unblocked:
            messageLabel.text = Localizations.chatUnblockedContactLabel
        case .addToAddressBook:
            let name = UserProfile.findOrCreate(with: userID, in: MainAppContext.shared.mainDataStore.viewContext).displayName
            messageLabel.text = Localizations.chatEventAddContactToAddressBook(name: name)
        }
    }

    func configure(groupEvent: GroupEvent) {
        if let text = groupEvent.text {
            messageLabel.text = text
        }
    }

    @objc private func onTapEvent() {
        guard let delegate = delegate else { return }
        switch eventType {
        case .addToAddressBook:
            delegate.messageChatHeaderViewAddToContacts(self)
        default:
            break
        }
    }
}
