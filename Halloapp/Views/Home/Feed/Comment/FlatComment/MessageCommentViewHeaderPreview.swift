//
//  MessageCommentHeaderPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/17/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

fileprivate struct LayoutConstants {
    static let profilePictureSizeNormal: CGFloat = 30
    static let profilePictureTrailingSpaceNormal: CGFloat = 10
}

protocol MessageCommentViewHeaderPreviewDelegate: AnyObject {
    func messageCommentHeaderView(_ view: MessageCommentViewHeaderPreview, didTapGroupWithID groupId: GroupID)
    func messageCommentHeaderView(_ view: MessageCommentViewHeaderPreview, didTapProfilePictureUserId userId: UserID)
    func messageCommentHeaderView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int)
}

class MessageCommentViewHeaderPreview: UICollectionReusableView {

    weak var delegate: MessageCommentViewHeaderPreviewDelegate?

    lazy var profilePictureButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let contactNameLabel: UILabel = {
        let label = UILabel()
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: fontDescriptor.pointSize - 1)
        label.textColor = .label
        label.isUserInteractionEnabled = true
        return label
    }()

    let groupNameLabel: UILabel = {
        let label = UILabel()
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: fontDescriptor.pointSize - 1)
        label.textColor = .label
        label.isHidden = true
        label.isUserInteractionEnabled = true
        return label
    }()

    private lazy var groupIndicatorLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true

        let groupIndicatorImage: UIImage? = UIImage(named: "GroupNameArrow")?.withRenderingMode(.alwaysTemplate).imageFlippedForRightToLeftLayoutDirection()
        let groupIndicatorColor = UIColor(named: "GroupNameArrow") ?? .label

        if let groupIndicator = groupIndicatorImage, let font = label.font {
            let iconAttachment = NSTextAttachment(image: groupIndicator)
            let attrText = NSMutableAttributedString(attachment: iconAttachment)
            attrText.addAttributes([.font: font, .foregroundColor: groupIndicatorColor], range: NSRange(location: 0, length: attrText.length))
            label.attributedText = attrText
        }
        return label
    }()

    private lazy var userAndGroupNameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [contactNameLabel, groupIndicatorLabel, groupNameLabel, UIView()])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.spacing = 5
        return view
    }()

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [userAndGroupNameRow])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        return vStack
    }()

    private var feedPost: FeedPost?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = UIColor.primaryBg
        self.preservesSuperviewLayoutMargins = true
        self.addSubview(profilePictureButton)
        self.addSubview(vStack)

        NSLayoutConstraint.activate([
            profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal),
            profilePictureButton.heightAnchor.constraint(equalTo: profilePictureButton.widthAnchor),
            profilePictureButton.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            profilePictureButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.bottomAnchor),
            vStack.leadingAnchor.constraint(equalTo: profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal),
            vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
            vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
        ])
        groupNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        contactNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))

    }

    func configure(withPost feedPost: FeedPost) {
        self.feedPost = feedPost
        // Contact name
        contactNameLabel.text = MainAppContext.shared.contactStore.fullName(for: feedPost.userId, in: MainAppContext.shared.contactStore.viewContext)
        // Avatar
        profilePictureButton.avatarView.configure(with: feedPost.userId, using: MainAppContext.shared.avatarStore)
        configureGroupName(feedPost: feedPost)
    }

    private func configureGroupName(feedPost: FeedPost) {
        if let groupId = feedPost.groupId, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.chatData.viewContext) {
            groupNameLabel.text = group.name
            groupNameLabel.isHidden = false
            groupIndicatorLabel.isHidden = false
        } else {
            groupNameLabel.isHidden = true
            groupIndicatorLabel.isHidden = true
        }
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = feedPost {
            delegate?.messageCommentHeaderView(self, didTapProfilePictureUserId: feedPost.userId)
        }
    }

    @objc private func showGroupFeed() {
        if let feedPost = feedPost, let groupId = feedPost.groupId {
            delegate?.messageCommentHeaderView(self, didTapGroupWithID: groupId)
        }
    }
}

