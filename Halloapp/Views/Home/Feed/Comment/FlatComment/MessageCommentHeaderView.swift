//
//  MessageCommentViewHeader.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/21/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

fileprivate struct LayoutConstants {
    static let profilePictureSizeNormal: CGFloat = 30
    static let profilePictureTrailingSpaceNormal: CGFloat = 10
}

protocol MessageCommentHeaderViewDelegate: AnyObject {
    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapGroupWithID groupId: GroupID)
    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapProfilePictureUserId userId: UserID)
    func messageCommentHeaderView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int)
}

class MessageCommentHeaderView: UICollectionReusableView {

    public override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        // Always ensure post header is on top of the section header
        // Setting the ZIndex on the supplementary item did not work
        // and hence we need to override the zPosition here
        self.layer.zPosition = 1000
    }

    static var elementKind: String {
        return String(describing: MessageCommentHeaderView.self)
    }

    weak var delegate: MessageCommentHeaderViewDelegate?

    lazy var profilePictureButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
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

    private(set) var audioView: PostAudioView = {
        let audioView = PostAudioView(configuration: .comments)
        audioView.isHidden = true
        return audioView
    }()

    let textView: ExpandableTextView = {
        let textView = ExpandableTextView()
        textView.numberOfLines = 3
        textView.isHidden = true
        return textView
    }()

    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .natural
        return label
    }()
    
    lazy var mediaCarouselView: MediaCarouselView = {
        var configuration = MediaCarouselViewConfiguration.minimal
        configuration.downloadProgressViewSize = 24
        let mediaView = MediaCarouselView(media: [], configuration: configuration)
        mediaView.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        mediaView.isHidden = true
        mediaView.delegate = self
        let constraint = mediaView.heightAnchor.constraint(equalToConstant: 55)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        return mediaView
    }()

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [userAndGroupNameRow, mediaCarouselView, audioView, textView, timestampLabel])
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

        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator
        self.addSubview(separatorView)

        NSLayoutConstraint.activate([
            profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal),
            profilePictureButton.heightAnchor.constraint(equalTo: profilePictureButton.widthAnchor),
            profilePictureButton.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            profilePictureButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.bottomAnchor),
            vStack.leadingAnchor.constraint(equalTo: profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal),
            vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
            vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
            separatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

        groupNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        contactNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUserFeedForPostAuthor)))
    }

    func configure(withPost feedPost: FeedPost) {
        self.feedPost = feedPost
        // Contact name
        contactNameLabel.text = MainAppContext.shared.contactStore.fullName(for: feedPost.userId)
        // Timestamp
        timestampLabel.text = feedPost.timestamp.feedTimestamp()
        // Avatar
        profilePictureButton.avatarView.configure(with: feedPost.userId, using: MainAppContext.shared.avatarStore)
        configureGroupName(feedPost: feedPost)
        configureMedia(feedPost: feedPost)
        configureText(feedPost: feedPost)
    }

    private func configureGroupName(feedPost: FeedPost) {
        if let groupId = feedPost.groupId, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            groupNameLabel.text = group.name
            groupNameLabel.isHidden = false
            groupIndicatorLabel.isHidden = false
        } else {
            groupNameLabel.isHidden = true
            groupIndicatorLabel.isHidden = true
        }
    }

    private func configureMedia(feedPost: FeedPost) {
        if !feedPost.orderedMedia.isEmpty {
            let media = MainAppContext.shared.feedData.media(for: feedPost)
            MainAppContext.shared.feedData.loadImages(postID: feedPost.id)

            let imageAndVideoMedia = media.filter { [.image, .video].contains($0.type) }
            if !imageAndVideoMedia.isEmpty {
                mediaCarouselView.configureMediaCarousel(media: imageAndVideoMedia)
                mediaCarouselView.isHidden = false
            }

            // Audio
            if let audioMedia = media.first(where: { $0.type == .audio }) {
                audioView.feedMedia = audioMedia
                let isOwnPost = feedPost.userId == MainAppContext.shared.userData.userId
                audioView.isSeen = feedPost.status == .seen || isOwnPost
                audioView.isHidden = false
            }
        }
    }

    private func configureText(feedPost: FeedPost) {
        // TODO: Need to handle groupFeedItems that failed to decrypt.
        // talk to nandini.
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: feedPost.id)
        let postTextWithCryptoResult = (feedPost.text ?? "") + cryptoResultString
        if !postTextWithCryptoResult.isEmpty {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                postTextWithCryptoResult,
                mentions: feedPost.orderedMentions)

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)

            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: .label)
                textView.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
                // @TODO: since we've already calculated the alignment on the feed, bring it over?
                textView.textAlignment = attrText.string.naturalAlignment
                textView.isHidden = false
            }
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

// MARK: PostAudioViewDelegate
extension MessageCommentHeaderView: PostAudioViewDelegate {

    func postAudioView(_ postAudioView: PostAudioView, didUpdateIsPlayingTo isPlaying: Bool) {
        guard isPlaying, let feedPost = feedPost else {
            return
        }
        MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
        postAudioView.isSeen = true
    }
}

extension MessageCommentHeaderView: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        delegate?.messageCommentHeaderView(view, didTapMediaAtIndex: index)
    }

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {

    }
}

