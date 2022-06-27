//
//  MessageChatHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/23/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol MessageChatHeaderViewDelegate: AnyObject {
    func messageChatHeaderViewOpenEncryptionBlog(_ messageChatHeaderView: MessageChatHeaderView)
}

class MessageChatHeaderView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: MessageChatHeaderView.self)
    }

    weak var delegate: MessageChatHeaderViewDelegate?
    var MaxWidthConstraint: CGFloat { return self.bounds.width * 0.8 }

    var encryptionLabel: UILabel = {
        let encryptionLabel = UILabel()
        encryptionLabel.font = .scaledSystemFont(ofSize: 12, weight: .regular)
        encryptionLabel.alpha = 0.80
        encryptionLabel.textColor = UIColor.black
        encryptionLabel.textAlignment = .center
        encryptionLabel.translatesAutoresizingMaskIntoConstraints = false
        encryptionLabel.numberOfLines = 4
        encryptionLabel.text = Localizations.chatEncryptionLabel
        encryptionLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return encryptionLabel
    }()

    private lazy var encryptionBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ encryptionLabel])
        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 18)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.messageEventHeaderBackground
        view.layer.cornerRadius = 7
        view.layer.masksToBounds = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.messageEventHeaderBorder.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openEncryptionBlog)))
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
        self.addSubview(encryptionBubble)
        NSLayoutConstraint.activate([
            encryptionBubble.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthConstraint).rounded()),
            encryptionBubble.centerXAnchor.constraint(equalTo: centerXAnchor),
            encryptionBubble.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            encryptionBubble.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 14),
        ])
    }

    @objc private func openEncryptionBlog() {
        guard let delegate = delegate else { return }
        delegate.messageChatHeaderViewOpenEncryptionBlog(self)
    }
}
