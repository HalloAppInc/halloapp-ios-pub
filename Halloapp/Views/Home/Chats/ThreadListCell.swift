//
//  ThreadListCell.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

fileprivate struct Constants {
    static let TitleFont = UIFont.systemFont(forTextStyle: .body, weight: .semibold) // 17 points
    static let LastMsgFont = UIFont.systemFont(forTextStyle: .callout) // 16 points
    static let LastMsgColor = UIColor.secondaryLabel
}

class ThreadListCell: UITableViewCell {

    public var chatThread: ChatThread? = nil
    public var isShowingTypingIndicator: Bool = false
    
    private var avatarSize: CGFloat = 56 // default

    private var cancellableSet: Set<AnyCancellable> = []

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

        titleLabel.attributedText = nil

        timeLabel.text = nil
        lastMsgLabel.text = nil
        lastMsgLabel.textColor = Constants.LastMsgColor
        lastMsgLabel.attributedText = nil
        unreadCountView.isHidden = true

        avatarView.avatarView.prepareForReuse()

        cancellableSet.forEach { $0.cancel() }
        cancellableSet.removeAll()
    }

    private func lastMessageText(for chatThread: ChatThread) -> NSMutableAttributedString {
        var defaultText = ""
        if chatThread.type == .oneToOne, let chatWithUserID = chatThread.userID, chatThread.lastMsgMediaType == .none, chatThread.userID != MainAppContext.shared.userData.userId {
            let fullName = UserProfile.find(with: chatWithUserID, in: AppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
            if chatThread.isNew {
                defaultText = Localizations.threadListPreviewInvitedUserDefault(name: fullName)
            } else {
                defaultText = Localizations.threadListPreviewAlreadyUserDefault(name: fullName)
            }
        }

        var messageText = chatThread.lastMsgText ?? defaultText

        if [.retracting, .retracted].contains(chatThread.lastMsgStatus) && chatThread.lastMsgText == nil {
            messageText = Localizations.chatMessageDeleted
        }

        let messageStatusIcon: UIImage? = {
            switch chatThread.lastMsgStatus {
            case .sentOut:
                return UIImage(named: "CheckmarkSingle")?.withTintColor(.systemGray)
            case .delivered:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(.systemGray)
            case .seen, .played:
                return UIImage(named: "CheckmarkDouble")?.withTintColor(traitCollection.userInterfaceStyle == .light ? UIColor.chatOwnMsg : UIColor.primaryBlue)
            default:
                return nil
            }
        }()
        
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

        case .audio:
            mediaIcon = UIImage(systemName: "mic.fill")?.withTintColor(chatThread.lastMsgStatus == .played ? .primaryBlue : .systemGray)

            if messageText.isEmpty {
                messageText = Localizations.chatMessageAudio
            }

        case .missedAudioCall:
            mediaIcon = UIImage(systemName: "phone.fill.arrow.down.left")?.withTintColor(.red)
            messageText = Localizations.voiceCallMissed + " " + messageText

        case .incomingAudioCall:
            mediaIcon = UIImage(systemName: "phone.fill.arrow.down.left")
            messageText = Localizations.voiceCall + " " + messageText

        case .outgoingAudioCall:
            mediaIcon = UIImage(systemName: "phone.fill.arrow.up.right")
            messageText = Localizations.voiceCall + " " + messageText

        case .missedVideoCall:
            mediaIcon = UIImage(systemName: "arrow.down.left.video.fill")?.withTintColor(.red)
            messageText = Localizations.videoCallMissed + " " + messageText

        case .incomingVideoCall:
            mediaIcon = UIImage(systemName: "arrow.down.left.video.fill")
            messageText = Localizations.videoCall + " " + messageText

        case .outgoingVideoCall:
            mediaIcon = UIImage(systemName: "arrow.up.right.video.fill")
            messageText = Localizations.videoCall + " " + messageText

        case .location:
            mediaIcon = UIImage(systemName: "mappin.and.ellipse")
            messageText = Localizations.locationSharingNavTitle + " " + messageText

        case .document:
            mediaIcon = UIImage(systemName: "doc.fill")
            if messageText.isEmpty {
                messageText = Localizations.chatMessageDocument
            }

        case .none:
            break
        }

        let result = NSMutableAttributedString(string: "")

        if let messageStatusIcon = messageStatusIcon {
            let imageSize = messageStatusIcon.size
            let font = UIFont.systemFont(ofSize: Constants.LastMsgFont.pointSize - 1)
            
            let scale = font.capHeight / imageSize.height
            let iconAttachment = NSTextAttachment(image: messageStatusIcon)
            iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))

            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }

        if let mediaIcon = mediaIcon, chatThread.type == .oneToOne {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: mediaIcon)))
            result.append(NSAttributedString(string: " "))
        }

        let ham = HAMarkdown(font: Constants.LastMsgFont, color: Constants.LastMsgColor)

        result.append(ham.parse(messageText))
        // For group chat messages, we prefix the preview with the message author name.
        if chatThread.type == .groupChat {
            let namePrefixedResult = NSMutableAttributedString(string: "")
            var firstName: String?
            if let lastMsgUserId = chatThread.lastMsgUserId {
                if lastMsgUserId == MainAppContext.shared.userData.userId {
                    firstName = Localizations.userYouCapitalized
                } else {
                    firstName = UserProfile.find(with: lastMsgUserId, in: MainAppContext.shared.mainDataStore.viewContext)?.name ?? ""
                }
            }
            if let firstName = firstName {
                namePrefixedResult.append(NSMutableAttributedString(string: firstName + ": ", attributes: [ .font: Constants.LastMsgFont ]))
            }
            namePrefixedResult.append(result)
            return namePrefixedResult
        }
        return result
    }

    private func lastFeedText(for chatThread: ChatThread) -> NSMutableAttributedString {

        var contactNamePart = ""
        if chatThread.type == .groupFeed {
            if let userID = chatThread.lastFeedUserID, userID != MainAppContext.shared.userData.userId {
                contactNamePart = UserProfile.find(with: userID, in: AppContext.shared.mainDataStore.viewContext).flatMap {
                    $0.displayName + ": "
                } ?? ""
            }
        }

        var messageText = chatThread.lastFeedText ?? ""

        if [.retracted].contains(chatThread.lastFeedStatus) {
            messageText = Localizations.deletedPostGeneric
        }

        var mediaIcon: UIImage?
        if messageText.isEmpty {
            switch chatThread.lastFeedMediaType {
            case .image:
                mediaIcon = UIImage(systemName: "photo")
                messageText = Localizations.chatMessagePhoto
            case .video:
                mediaIcon = UIImage(systemName: "video.fill")
                messageText = Localizations.chatMessageVideo
            case .audio:
                mediaIcon = UIImage(systemName: "mic.fill")
                messageText = Localizations.chatMessageAudio
            default:
                break
            }
            mediaIcon = mediaIcon?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
        }

        let result = NSMutableAttributedString(string: contactNamePart)

        if let mediaIcon = mediaIcon {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: mediaIcon)))
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
    
    func configureAvatarSize(_ size: CGFloat) {
        avatarSize = size
        let avatarSizeWithIndicator: CGFloat = avatarSize
        contentView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: avatarSizeWithIndicator),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
        ])
    }

    func configureForChatsList(with chatThread: ChatThread, squareSize: CGFloat = 0) {
        self.chatThread = chatThread
        
        switch chatThread.type {
        case .oneToOne:
            if let userID = chatThread.userID {
                titleLabel.text = UserProfile.find(with: userID, in: AppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
                DDLogDebug("ThreadListCell/configureForChatsList/id: \(userID)/groupID: \(String(describing: chatThread.groupId))/unreadCount: \(chatThread.unreadCount)")

                avatarView.configure(userId: chatThread.userID ?? "", using: MainAppContext.shared.avatarStore)

                if !MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: MainAppContext.shared.contactStore.viewContext) {
                    cancellableSet.forEach { $0.cancel() }
                    cancellableSet.removeAll()
                    cancellableSet.insert(
                        MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] (newUserIDs) in
                            if let self, newUserIDs.contains(userID) {
                                self.titleLabel.text = UserProfile.find(with: userID, in: AppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
                            }
                        }
                    )
                }
            }
        case .groupChat:
            if let groupId = chatThread.groupId {
               titleLabel.text = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext)?.name
               DDLogDebug("ThreadListCell/configureForChatsList/ groupID: \(String(describing: groupId))/unreadCount: \(chatThread.unreadCount)")
               avatarView.configure(groupId: groupId, using: MainAppContext.shared.avatarStore)
           }
        case .groupFeed :
            DDLogInfo("ThreadListCell/configureForChatsList/ unexpected type found groupFeed")
        }
        lastMsgLabel.attributedText = lastMessageText(for: chatThread).firstLineWithEllipsisIfNecessary()
        if chatThread.unreadCount > 0 {
            unreadCountView.isHidden = false
            unreadCountView.count = chatThread.unreadCount
            timeLabel.textColor = .systemBlue
        } else {
            unreadCountView.isHidden = true
            timeLabel.textColor = .secondaryLabel
        }

        if let timestamp = chatThread.lastMsgTimestamp, (chatThread.lastMsgId != nil || chatThread.type == .groupChat) {
            timeLabel.text = timestamp.chatListTimestamp()
        }
    }

    func configureForGroupsList(with chatThread: ChatThread, squareSize: CGFloat = 0) {
        guard let groupID = chatThread.groupId else { return }
        if chatThread.type == .groupChat {
            configureForChatsList(with: chatThread, squareSize: squareSize)
            return
        }
        self.chatThread = chatThread
        titleLabel.text = chatThread.title

        lastMsgLabel.attributedText = lastFeedText(for: chatThread).firstLineWithEllipsisIfNecessary()

        var unreadFeedCount = chatThread.unreadFeedCount

        // account for NUX zero zone
        let sharedNUX = MainAppContext.shared.nux
        if groupID == sharedNUX.sampleGroupID(), let seen = sharedNUX.sampleGroupWelcomePostSeen(), !seen {
            unreadFeedCount += 1
        }

        if unreadFeedCount > 0 {
            unreadCountView.isHidden = false
            unreadCountView.count = unreadFeedCount
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
        guard let title = titleLabel.text else { return }
        let titleLowercased = title.lowercased() as NSString
        let attributedString = NSMutableAttributedString(string: title)
        for item in searchItems {
            let range = titleLowercased.range(of: item.lowercased())
            attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
        }
        titleLabel.attributedText = attributedString
    }

    func configureTypingIndicator(_ typingIndicatorStr: String?) {
        guard let chatThread = chatThread else { return }

        guard let typingIndicatorStr = typingIndicatorStr else {
            isShowingTypingIndicator = false
            configureForChatsList(with: chatThread)
            return
        }

        let attributedString = NSMutableAttributedString(string: typingIndicatorStr, attributes: [.font: Constants.LastMsgFont, .foregroundColor: Constants.LastMsgColor])
        lastMsgLabel.attributedText = attributedString

        isShowingTypingIndicator = true
    }
    
    private func setup() {
        backgroundColor = .clear

        avatarView = AvatarViewButton(type: .custom)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = false
        
        contentView.addSubview(mainRow)
        
        contentView.addConstraints([
            mainRow.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            mainRow.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            mainRow.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mainRow.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private var avatarView: AvatarViewButton!

    var avatarTappedAction: (() -> ())?

    @objc private func avatarButtonTapped() {
        avatarTappedAction?()
    }
    
    private lazy var mainRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ avatarView, vStack ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 12
                
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ topRow, bottomRow ])
        view.axis = .vertical
        view.spacing = 6
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var topRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ titleLabel, timeLabel ])
        view.axis = .horizontal
        view.alignment = .firstBaseline
        view.spacing = 7
        return view
    }()
    
    private lazy var bottomRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ lastMsgLabel, unreadCountView ])
        view.axis = .horizontal
        view.alignment = .center // This works as long as unread label and last message text have the same font.
        view.spacing = 8
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = Constants.TitleFont
        label.textColor = UIColor.label
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    // 15 points for font
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 50, for: .horizontal)
        return label
    }()

    private lazy var lastMsgLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textColor = Constants.LastMsgColor
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var unreadCountView = UnreadBadgeView()

}

private class UnreadBadgeView: UIView {

    var count: Int32 = 0 {
        didSet {
            label.text = String(count)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private let label: UILabel = {
        let label = UILabel()
        // 13 points for font
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.textColor = .primaryWhiteBlack
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .vertical)
        return label
    }()

    private func commonInit() {
        backgroundColor = .systemBlue
        layoutMargins = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.constrainMargins(to: self)
        widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor).isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.height, bounds.width) * 0.5
    }
}

private extension NSMutableAttributedString {
    func firstLineWithEllipsisIfNecessary() -> NSAttributedString {
        guard let firstNewLineIndex = string.firstIndex(of: "\n") else { return self }
        let endFirstNewLineIndex = string.index(firstNewLineIndex, offsetBy: 1)
        let firstNewLineRange = firstNewLineIndex..<endFirstNewLineIndex
        let firstNewLineNSRange = NSRange(firstNewLineRange, in: string)
        replaceCharacters(in: firstNewLineNSRange, with: "...\n")

        guard let replacedNewLineIndex = string.firstIndex(of: "\n") else { return self }
        let subStrRange = string.startIndex..<replacedNewLineIndex
        let subStrNSRange = NSRange(subStrRange, in: string)
        return attributedSubstring(from: subStrNSRange)
    }
}
