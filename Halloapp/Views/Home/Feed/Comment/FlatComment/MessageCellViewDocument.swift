//
//  MessageCellViewDocument.swift
//  HalloApp
//
//  Created by Garrett on 9/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

class MessageCellViewDocument: MessageCellViewBase {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        contentView.preservesSuperviewLayoutMargins = false
        nameContentTimeRow.addArrangedSubview(nameRow)
        nameContentTimeRow.addArrangedSubview(forwardCountLabel)
        nameContentTimeRow.addArrangedSubview(documentView)
        nameContentTimeRow.addArrangedSubview(textRow)
        nameContentTimeRow.addArrangedSubview(sizeAndTimeRow)
        nameContentTimeRow.setCustomSpacing(0, after: textRow)
        contentView.addSubview(messageRow)
        messageRow.constrain([.top], to: contentView)
        messageRow.constrain(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))

        NSLayoutConstraint.activate([
            rightAlignedConstraint,
            leftAlignedConstraint
        ])

        // Tapping on user name should take you to the user's feed
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))
        // Reply gesture
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureCellAction))
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
    }

    public lazy var sizeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 12)
        label.textColor = .chatTime
        return label
    }()

    public lazy var sizeAndTimeRow: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [sizeLabel, timeRow])
        stackView.axis = .horizontal
        return stackView
    }()

    private(set) lazy var documentView: MessageDocumentView = {
        let view = MessageDocumentView()
        view.addTarget(self, action: #selector(didTapDocument), for: .touchUpInside)
        view.backgroundColor = .messageFileBackground
        return view
    }()

    private var documentURL: URL?

    override func prepareForReuse() {
        super.prepareForReuse()
        documentView.setDocument(url: nil, name: nil)
    }

    override func configureWith(comment: FeedPostComment, userColorAssignment: UIColor, parentUserColorAssignment: UIColor, isPreviousMessageFromSameSender: Bool) {
        super.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        DDLogError("MessageCellViewDocument/configureWithComment/error [documents-not-supported-in-comments]")
    }

    override func configureWith(message: ChatMessage, userColorAssignment: UIColor, parentUserColorAssignment: UIColor,isPreviousMessageFromSameSender: Bool) {
        super.configureWith(message: message, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        configureText(chatMessage: message)

        if AppContext.shared.userDefaults.bool(forKey: "enableChatForwarding") {
            forwardButton.isHidden = false
        }
        DispatchQueue.main.async {
            MainAppContext.shared.chatData.downloadMedia(in: message)
        }

        documentURL = message.media?.first?.mediaURL
        if let documentURL = documentURL {
            documentView.setDocument(url: documentURL, name: message.media?.first?.name)
        }

        let fileSize = message.media?.first?.fileSize ?? 0
        sizeLabel.text = fileSize > 0 ? ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) : nil

        // TODO-DOC download spinner

        if isOwnMessage {
            NSLayoutConstraint.activate([
                forwardButton.trailingAnchor.constraint(equalTo: messageRow.leadingAnchor, constant: 4),
                forwardButton.centerYAnchor.constraint(equalTo: messageRow.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                forwardButton.leadingAnchor.constraint(equalTo: messageRow.trailingAnchor, constant: -4),
                forwardButton.centerYAnchor.constraint(equalTo: messageRow.centerYAnchor),
            ])
        }
        configureCell()

        // hide empty space above media on incomming messages
        nameRow.isHidden = true
    }

    @objc
    private func didTapDocument() {
        guard let documentURL = documentURL else {
            return
        }
        chatDelegate?.messageView(self, openDocument: documentURL)
    }
}
