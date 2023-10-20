//
//  ChatTitleView.swift
//  HalloApp
//
//  Created by Tony Jiang on 12/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol ChatTitleViewDelegate: AnyObject {
    func chatTitleView(_ chatTitleView: ChatTitleView)
}

class ChatTitleView: UIView {

    weak var delegate: ChatTitleViewDelegate?

    public var isShowingTypingIndicator: Bool = false

    public var currentlyTypingUserId: UserID?

    private var isUnknownContactWithPushNumber: Bool = false

    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: .greatestFiniteMagnitude, height: UIView.noIntrinsicMetric)
    }

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    func update(with fromUserId: String, status: UserPresenceType, lastSeen: Date?) {
        contactImageView.configure(with: fromUserId, using: MainAppContext.shared.avatarStore)
        setNameLabel(for: fromUserId)

        guard !isUnknownContactWithPushNumber else { return }

        switch status {
        case .away:
            // prefer to show last seen over typing
            if let lastSeen = lastSeen {
                lastSeenLabel.text = lastSeen.lastSeenTimestamp()
                typingLabel.isHidden = true
                lastSeenLabel.isHidden = false
            }
        case .available:
            // prefer to show typing over online
            lastSeenLabel.isHidden = !isShowingTypingIndicator ? false : true
            lastSeenLabel.text = Localizations.chatOnlineLabel
        default:
            lastSeenLabel.isHidden = true
            lastSeenLabel.text = ""
        }
    }

    func updateGroupTitleView(groupId: GroupID, fromUserId: UserID, status: UserPresenceType) {
        contactImageView.configure(groupId: groupId, using: MainAppContext.shared.avatarStore)
        setNameLabel(groupId: groupId)
        guard currentlyTypingUserId == fromUserId else { return }
        switch status {
        case .away:
            currentlyTypingUserId = nil
            typingLabel.isHidden = true
        default:
            lastSeenLabel.isHidden = true
        }
    }

    func clearGroupTitleViewTyping(groupId: GroupID) {
        contactImageView.configure(groupId: groupId, using: MainAppContext.shared.avatarStore)
        setNameLabel(groupId: groupId)
        typingLabel.text = ""
        typingLabel.isHidden = true
    }

    func refreshName(for userID: String) {
        setNameLabel(for: userID)
    }

    func refreshName(groupId: GroupID) {
        setNameLabel(groupId: groupId)
    }

    public func configureGroupTitleViewWithTypingIndicator(chatStateInfo: ChatStateInfo) {
        let typingIndicatorStr = MainAppContext.shared.chatData.getTypingIndicatorString(type: .groupChat, id: chatStateInfo.threadID, fromUserID: chatStateInfo.from)

        if typingIndicatorStr == nil && !isShowingTypingIndicator {
            return
        }
        currentlyTypingUserId = chatStateInfo.from
        showChatState(with: typingIndicatorStr)
    }

    func showTypingChatStateForGroupChat(for typingUserId: UserID, with typingIndicatorStr: String?) {

        let showTyping: Bool = typingIndicatorStr != nil

        lastSeenLabel.isHidden = showTyping
        typingLabel.isHidden = !showTyping
        isShowingTypingIndicator = showTyping

        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
    }

    func showChatState(with typingIndicatorStr: String?) {
        guard !isUnknownContactWithPushNumber else { return }

        let showTyping: Bool = typingIndicatorStr != nil
        
        lastSeenLabel.isHidden = showTyping
        typingLabel.isHidden = !showTyping
        isShowingTypingIndicator = showTyping
        
        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
    }
    
    private func setNameLabel(for userID: UserID) {
        nameLabel.text = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
    }

    private func setNameLabel(groupId: GroupID) {
        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
            nameLabel.text = group.name
        }
    }
    
    private func setup() {
        let imageSize: CGFloat = 32
        contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        contactImageView.heightAnchor.constraint(equalTo: contactImageView.widthAnchor).isActive = true

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let hStack = UIStackView(arrangedSubviews: [ contactImageView, nameColumn ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10

        addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoProfile))
        isUserInteractionEnabled = true
        addGestureRecognizer(tapGesture)
    }

    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [nameLabel, lastSeenLabel, typingLabel])
        view.axis = .vertical
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(ofFixedSize: 17, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var lastSeenLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()

    private lazy var typingLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()

    // MARK: actions

    @objc func gotoProfile(_ sender: UIView) {
        delegate?.chatTitleView(self)
    }
}

private extension Localizations {

    static var chatOnlineLabel: String {
        NSLocalizedString("chat.online.label", value: "online", comment: "Text below the contact's name when the contact is online in the Chat Screen")
    }

}
