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
        DispatchQueue.main.async { [weak self] in
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

class MessageDocumentView: UIControl {
    static let previewSize = CGSize(width: 238, height: 124)
    static let cornerRadius = CGFloat(10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.backgroundColor = .messageFileBackground

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        label.font = .scaledSystemFont(ofSize: 15)

        labelBackground.translatesAutoresizingMaskIntoConstraints = false
        labelBackground.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        labelBackground.contentView.addSubview(label)
        addSubview(preview)
        addSubview(labelBackground)

        preview.constrain(to: self)
        preview.heightAnchor.constraint(equalToConstant: Self.previewSize.height).isActive = true
        preview.widthAnchor.constraint(equalToConstant: Self.previewSize.width).isActive = true
        labelBackground.constrain([.leading, .trailing, .bottom], to: self)
        label.constrainMargins(to: labelBackground.contentView)

        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = true

    }

    func setDocument(url: URL?, name: String?) {
        documentURL = url
        guard let url = url else {
            label.text = nil
            preview.image = nil
            return
        }

        let attrString: NSMutableAttributedString = {
            guard let icon = UIImage(systemName: "doc") else {
                return NSMutableAttributedString(string: "📄")
            }
            return NSMutableAttributedString(attachment: NSTextAttachment(image: icon))
        }()
        if let name = name {
            attrString.append(NSAttributedString(string: " \(name)"))
        }
        label.attributedText = attrString

        FileUtils.generateThumbnail(for: url, size: FileUtils.thumbnailSizeDefault) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let image):
                    guard url == self.documentURL else {
                        // Ignore thumbnail if it arrives after view has been reused
                        return
                    }
                    self.preview.image = image
                case .failure(let error):
                    DDLogError("MessageCellViewDocument/generateThumbnail/error [\(url.absoluteString)] [\(error)]")
                }
            }
        }
    }

    private let preview = UIImageView()
    private let label = UILabel()
    private let labelBackground = BlurView(effect: UIBlurEffect(style: .prominent), intensity: 0.5)

    private var documentURL: URL?
}
