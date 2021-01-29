//
//  ThreadListCell.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import UIKit

fileprivate struct Constants {
    static let LastMsgFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize + 1) // 14
    static let LastMsgColor = UIColor.secondaryLabel
}

class ThreadListCell: UITableViewCell {

    public var chatThread: ChatThread? = nil
    public var isShowingTypingIndicator: Bool = false
    
    public var avatarSize: CGFloat = 50
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        chatThread = nil
        isShowingTypingIndicator = false

        nameLabel.attributedText = nil

        timeLabel.text = nil
        lastMsgLabel.text = nil
        unreadCountView.isHidden = true

        avatarView.avatarView.prepareForReuse()
    }

    // 14 points for font
    private func lastMessageText(for chatThread: ChatThread) -> NSAttributedString {

        var contactNamePart = ""
        if chatThread.type == .group {
            if let userId = chatThread.lastMsgUserId, userId != MainAppContext.shared.userData.userId {
                contactNamePart = MainAppContext.shared.contactStore.fullName(for: userId) + ": "
            }
        }

        var defaultText = ""
        if chatThread.type == .oneToOne && chatThread.lastMsgMediaType == .none {
            defaultText = Localizations.chatListMessageDefault(name: chatThread.title)
        }

        var messageText = chatThread.lastMsgText ?? defaultText

        if [.retracting, .retracted].contains(chatThread.lastMsgStatus) {
            messageText = Localizations.chatMessageDeleted
        }

        var mediaIcon: UIImage?
        switch chatThread.lastMsgMediaType {
        case .image:
            mediaIcon = UIImage(systemName: "photo")
            if messageText.isEmpty {
                messageText = Localizations.chatMessagePhoto
            }

        case .video:
            mediaIcon = UIImage(systemName: "video.fill")
            if messageText.isEmpty {
                messageText = Localizations.chatMessageVideo
            }

        default:
            break
        }

        let messageStatusIcon: UIImage? = {
            switch chatThread.lastMsgStatus {
            case .seen:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(.chatOwnMsg)

            case .delivered:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))

            case .sentOut:
                return UIImage(named: "CheckmarkSingle")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))

            default:
                return nil
            }
        }()

        let result = NSMutableAttributedString(string: contactNamePart)

        if let mediaIcon = mediaIcon {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: mediaIcon)))
            result.append(NSAttributedString(string: " "))
        }

        if let messageStatusIcon = messageStatusIcon {
            let imageSize = messageStatusIcon.size
            let scale = Constants.LastMsgFont.capHeight / imageSize.height

            let iconAttachment = NSTextAttachment(image: messageStatusIcon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))

            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(string: messageText))

        result.addAttributes([ .font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor ],
                             range: NSRange(location: 0, length: result.length))
//        if !contactNamePart.isEmpty {
//            // Note that the assumption is that we are using system font for the rest of the text.
//            let participantNameFont = UIFont.systemFont(ofSize: Constants.LastMsgFont.pointSize, weight: .medium)
//            result.addAttribute(.font, value: participantNameFont, range: NSRange(location: 0, length: contactNamePart.count))
//        }

        return result
    }

    // 14 points for font
    private func lastFeedText(for chatThread: ChatThread) -> NSAttributedString {

        var contactNamePart = ""
        if chatThread.type == .group {
            if let userID = chatThread.lastFeedUserID, userID != MainAppContext.shared.userData.userId {
                contactNamePart = MainAppContext.shared.contactStore.fullName(for: userID) + ": "
            }
        }

        var messageText = chatThread.lastFeedText ?? ""

        if [.retracted].contains(chatThread.lastFeedStatus) {
            messageText = Localizations.postHasBeenDeleted
        }

        switch chatThread.lastFeedMediaType {
        case .image:
            if messageText.isEmpty {
                messageText = Localizations.chatMessagePhoto
            }

        case .video:
            if messageText.isEmpty {
                messageText = Localizations.chatMessageVideo
            }

        default:
            break
        }

        let result = NSMutableAttributedString(string: contactNamePart)

        result.append(NSAttributedString(string: messageText))

        result.addAttributes([ .font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor ],
                             range: NSRange(location: 0, length: result.length))
//        if !contactNamePart.isEmpty {
//            // Note that the assumption is that we are using system font for the rest of the text.
//            let participantNameFont = UIFont.systemFont(ofSize: Constants.LastMsgFont.pointSize, weight: .medium)
//            result.addAttribute(.font, value: participantNameFont, range: NSRange(location: 0, length: contactNamePart.count))
//        }

        return result
    }
    
    func configureAvatarSize(_ size: CGFloat) {
        avatarSize = size
        let avatarSizeWithIndicator: CGFloat = avatarSize + (avatarView.hasNewPostsIndicator ? 2*(avatarView.newPostsIndicatorRingSpacing + avatarView.newPostsIndicatorRingWidth) : 0)
        contentView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: avatarSizeWithIndicator),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 0.5*avatarSizeWithIndicator),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),

            vStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            vStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }
    
    func configure(with chatThread: ChatThread) {

        self.chatThread = chatThread

        if chatThread.type == .oneToOne {
            nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatThread.chatWithUserId ?? "")
        } else {
            nameLabel.text = chatThread.title
        }

        lastMsgLabel.attributedText = lastMessageText(for: chatThread)

        if chatThread.unreadCount > 0 {
            unreadCountView.isHidden = false
            unreadCountView.label.text = String(chatThread.unreadCount)
            timeLabel.textColor = .systemBlue
        } else if chatThread.isNew {
            unreadCountView.isHidden = false
            unreadCountView.label.text = " "
            timeLabel.textColor = .systemBlue
        } else {
            unreadCountView.isHidden = true
            timeLabel.textColor = .secondaryLabel
        }

        if let timestamp = chatThread.lastMsgTimestamp {
            timeLabel.text = timestamp.chatListTimestamp()
        }

        if chatThread.type == .oneToOne {
            avatarView.configure(userId: chatThread.chatWithUserId ?? "", using: MainAppContext.shared.avatarStore)
        } else if chatThread.type == .group {
            avatarView.configure(groupId: chatThread.groupId ?? "", using: MainAppContext.shared.avatarStore)
        }
    }
    
    func configureForGroupsList(with chatThread: ChatThread, squareSize: CGFloat = 0) {
        guard chatThread.groupId != nil else { return }
        self.chatThread = chatThread
        nameLabel.text = chatThread.title
        
        lastMsgLabel.attributedText = lastFeedText(for: chatThread)

        if chatThread.unreadFeedCount > 0 {
            unreadCountView.isHidden = false
            unreadCountView.label.text = String(chatThread.unreadFeedCount)
            timeLabel.textColor = .systemBlue
        } else if chatThread.isNew {
            unreadCountView.isHidden = false
            unreadCountView.label.text = " "
            timeLabel.textColor = .systemBlue
        } else {
            unreadCountView.isHidden = true
            timeLabel.textColor = .secondaryLabel
        }

        if let timestamp = chatThread.lastFeedTimestamp {
            timeLabel.text = timestamp.chatListTimestamp()
        }

        avatarView.configure(groupId: chatThread.groupId ?? "", squareSize: squareSize, using: MainAppContext.shared.avatarStore)
        
    }

    func highlightTitle(_ searchItems: [String]) {
        guard let title = nameLabel.text else { return }
        let titleLowercased = title.lowercased() as NSString
        let attributedString = NSMutableAttributedString(string: title)
        for item in searchItems {
            let range = titleLowercased.range(of: item.lowercased())
            attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
        }
        nameLabel.attributedText = attributedString
    }

    func configureTypingIndicator(_ typingIndicatorStr: String?) {
        guard let chatThread = chatThread else { return }

        guard let typingIndicatorStr = typingIndicatorStr else {
            isShowingTypingIndicator = false
            configure(with: chatThread)
            return
        }

        let attributedString = NSMutableAttributedString(string: typingIndicatorStr, attributes: [.font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor])
        lastMsgLabel.attributedText = attributedString

        isShowingTypingIndicator = true
    }
    
    private func setup() {
        backgroundColor = .clear

        avatarView = AvatarViewButton(type: .custom)
//        avatarView.hasNewPostsIndicator = ServerProperties.isGroupFeedEnabled
//        avatarView.newPostsIndicatorRingWidth = 5
//        avatarView.newPostsIndicatorRingSpacing = 1.5
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(avatarView)
        contentView.addSubview(vStack)
        
//        if ServerProperties.isGroupFeedEnabled {
//            avatarView.addTarget(self, action: #selector(avatarButtonTapped), for: .touchUpInside)
//        } else {
//            avatarView.isUserInteractionEnabled = false
//        }
        
        avatarView.isUserInteractionEnabled = false
    }

    private var avatarView: AvatarViewButton!

    var avatarTappedAction: (() -> ())?

    @objc private func avatarButtonTapped() {
        avatarTappedAction?()
    }
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ topRow, bottomRow ])
        view.axis = .vertical
        view.spacing = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var topRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, timeLabel ])
        view.axis = .horizontal
        view.alignment = .firstBaseline
        view.spacing = 8
        return view
    }()
    
    private lazy var bottomRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ lastMsgLabel, unreadCountView ])
        view.axis = .horizontal
        view.alignment = .center // This works as long as unread label and last message text have the same font.
        view.spacing = 8
        return view
    }()
    
    // 15 points for font
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .systemFont(forTextStyle: .subheadline, weight: .semibold)
        label.textColor = UIColor.label.withAlphaComponent(0.8)
        return label
    }()

    // 13 points for font
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = UIFont.preferredFont(forTextStyle: .footnote)

        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        return label
    }()

    private lazy var lastMsgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    // 12 points for font
    private lazy var unreadCountView: UnreadBadgeView = {
        let view = UnreadBadgeView(frame: .zero)
        
        view.label.font = .systemFont(forTextStyle: .caption1, weight: .medium)
        
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        return view
    }()

}

private class UnreadBadgeView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    var label: UILabel!

    private func commonInit() {
        backgroundColor = .clear
        layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        let backgroundView = PillView()
        backgroundView.fillColor = .systemBlue
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        backgroundView.constrain(to: self)

        label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.widthAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, multiplier: 1).isActive = true
        label.constrainMargins(to: self)
    }
}

private extension Localizations {

    static var postHasBeenDeleted: String {
        NSLocalizedString("post.has.been.deleted", value: "This post has been deleted", comment: "Displayed in place of a deleted group feed post at group list screen")
    }

}
