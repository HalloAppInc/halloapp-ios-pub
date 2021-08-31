//
//  CommentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Combine
import UIKit

// MARK: Constraint Constants
fileprivate struct LayoutConstants {
    static let profilePictureSizeSmall: CGFloat = 20
    static let profilePictureSizeNormal: CGFloat = 30
    static let profilePictureLeadingMarginNormal: CGFloat = 0
    static let profilePictureLeadingMarginReply: CGFloat = 50
    static let profilePictureTrailingSpaceSmall: CGFloat = 8
    static let profilePictureTrailingSpaceNormal: CGFloat = 10
}

protocol CommentViewDelegate: AnyObject {
    func commentView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int)
}

private extension Localizations {

    static var commentReply: String {
        NSLocalizedString("comment.reply", value: "Reply", comment: "Title for the button displayed under feed post comment. Verb.")
    }

    static var commentDeleted: String {
        NSLocalizedString("comment.deleted", value: "This comment has been deleted", comment: "Text displayed in place of deleted comment.")
    }

    static var commentIsBeingDeleted: String {
        NSLocalizedString("comment.deleting", value: "Deleting comment", comment: "Text displayed in place of a comment that is currently being deleted.")
    }

    static var commentIsNotSupported: String {
        NSLocalizedString("comment.unsupported", value: "Your version of HalloApp does not support this type of comment.", comment: "Text displayed in place of a comment that is not supported in the current app version.")
    }

    static var posting: String {
        NSLocalizedString("comment.posting", value: "Posting...", comment: "Text displayed in place of comment timestamp while comment is being posted.")
    }
}

class CommentView: UIView {

    var feedPostCommentID: FeedPostCommentID?

    // MARK: Variable Constraints
    private var leadingMargin: NSLayoutConstraint!
    private var profilePictureWidth: NSLayoutConstraint!
    private var profilePictureTrailingSpace: NSLayoutConstraint!
    weak var delegate: CommentViewDelegate?
    private(set) var mediaCarouselView: MediaCarouselView?
    private var mediaStatusCancellable: AnyCancellable?
  
    var isReplyButtonVisible: Bool = true {
        didSet {
            replyButton.alpha = isReplyButtonVisible ? 1 : 0
        }
    }

    private(set) lazy var profilePictureButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private(set) lazy var nameTextLabel: TextLabel = {
        let label = TextLabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let textCommentLabel: TextLabel = {
        let label = TextLabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let mediaView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let mediaStack = UIStackView(arrangedSubviews: [ spacer ])
        mediaStack.translatesAutoresizingMaskIntoConstraints = false
        mediaStack.spacing = 4
        return mediaStack
    }()

    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private(set) lazy var replyButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.setTitle(Localizations.commentReply, for: .normal)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
        button.titleLabel?.font = .systemFont(ofSize: fontDescriptor.pointSize, weight: .bold)
        return button
    }()

    static let deletedCommentViewTag = 1
    private var deletedCommentTextLabel: TextLabel!
    private lazy var deletedCommentView: UIView = {
        deletedCommentTextLabel = TextLabel()
        deletedCommentTextLabel.translatesAutoresizingMaskIntoConstraints = false
        deletedCommentTextLabel.textColor = .secondaryLabel
        deletedCommentTextLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        deletedCommentTextLabel.numberOfLines = 0
        deletedCommentTextLabel.delegate = self
        let view = UIView()
        view.backgroundColor = .clear
        view.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tag = CommentView.deletedCommentViewTag
        view.addSubview(deletedCommentTextLabel)
        deletedCommentTextLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        deletedCommentTextLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor).isActive = true
        deletedCommentTextLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        deletedCommentTextLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
        return view

    }()

    private lazy var voiceCommentRow: UIView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 8).isActive = true

        let stack = UIStackView(arrangedSubviews: [voiceCommentView, voiceCommentTimeLabel, spacer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.backgroundColor = .commentVoiceNoteBackground
        stack.layer.borderWidth = 0.5
        stack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        stack.layer.cornerRadius = 15
        stack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        stack.layer.shadowOffset = CGSize(width: 0, height: 2)
        stack.layer.shadowRadius = 4
        stack.layer.shadowOpacity = 0.5
        stack.isLayoutMarginsRelativeArrangement = true

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        stack.heightAnchor.constraint(equalToConstant: 46).isActive = true
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6).isActive = true
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30).isActive = true

        return container
    }()

    private lazy var voiceCommentView: AudioView = {
        let view = AudioView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)

        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.delegate = self

        return view
    } ()

    private lazy var voiceCommentTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime

        return label
    }()

    private var vStack: UIStackView!
    private var bottomRow: UIStackView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        preservesSuperviewLayoutMargins = true

        addSubview(profilePictureButton)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        bottomRow = UIStackView(arrangedSubviews: [ timestampLabel, replyButton, spacer ])
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.alignment = .center
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8

        vStack = UIStackView(arrangedSubviews: [ nameTextLabel, voiceCommentRow, bottomRow ])
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        addSubview(vStack)
        
        profilePictureWidth = profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal)
        profilePictureButton.heightAnchor.constraint(equalTo: profilePictureButton.widthAnchor).isActive = true
        profilePictureWidth.isActive = true

        leadingMargin = profilePictureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.profilePictureLeadingMarginNormal)
        leadingMargin.isActive = true
        profilePictureButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true

        profilePictureTrailingSpace = vStack.leadingAnchor.constraint(equalTo: profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal)
        profilePictureTrailingSpace.isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func configure(withComment feedPostComment: FeedPostComment) {
        mediaStatusCancellable?.cancel()
        voiceCommentRow.isHidden = true

        if let mediaCarouselView = mediaCarouselView {
            mediaView.removeArrangedSubview(mediaCarouselView)
            mediaCarouselView.removeFromSuperview()
            vStack.removeArrangedSubview(mediaView)
            mediaView.removeFromSuperview()
            vStack.removeArrangedSubview(textCommentLabel)
            textCommentLabel.removeFromSuperview()
            self.mediaCarouselView = nil
        }

        if let feedCommentMedia = feedPostComment.media,
           let media = MainAppContext.shared.feedData.media(commentID: feedPostComment.id),
           feedCommentMedia.count > 0 {

            // Set Name
            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
            let contactName = MainAppContext.shared.contactStore.fullName(for: feedPostComment.userId)
            let attributedText = NSMutableAttributedString(string: contactName,
                                                           attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                        NSAttributedString.Key.font: nameFont])
            attributedText.append(NSAttributedString(string: " "))
            attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))
            nameTextLabel.attributedText = attributedText

            if media.count == 1 && media[0].type == .audio {
                voiceCommentRow.isHidden = false

                voiceCommentTimeLabel.text = "0:00"
                voiceCommentView.url = media[0].fileURL

                if media[0].fileURL == nil {
                    mediaStatusCancellable = media[0].mediaStatusDidChange.sink { [weak self] mediaItem in
                        guard let self = self else { return }
                        guard let url = mediaItem.fileURL else { return }
                        self.voiceCommentView.url = url
                    }
                }
            } else {
                // Set Media
                MainAppContext.shared.feedData.loadImages(commentID: feedPostComment.id)
                var configuration = MediaCarouselViewConfiguration.default
                configuration.downloadProgressViewSize = 24
                configuration.alwaysScaleToFitContent = false
                let mediaCarouselView = MediaCarouselView(media: media, configuration: configuration)
                mediaCarouselView.widthAnchor.constraint(equalToConstant: 170).isActive = true
                mediaCarouselView.heightAnchor.constraint(equalToConstant: 170).isActive = true
                mediaCarouselView.delegate = self
                mediaView.insertArrangedSubview(mediaCarouselView, at: mediaView.arrangedSubviews.count - 1)
                vStack.insertArrangedSubview(mediaView, at: vStack.arrangedSubviews.count - 1)
                self.mediaCarouselView = mediaCarouselView
            }

            // Text below media
            if !feedPostComment.text.isEmpty {
                let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                    feedPostComment.text,
                    mentions: Array(feedPostComment.mentions ?? Set()))

                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
                let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
                let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
                textCommentLabel.attributedText = textWithMentions?.with(font: font, color: .label).applyingFontForMentions(boldFont)

                vStack.insertArrangedSubview(textCommentLabel, at: vStack.arrangedSubviews.count - 1)
            }
        } else {
            // No media, set name and append text to name label
            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

            let contactName = MainAppContext.shared.contactStore.fullName(for: feedPostComment.userId)
            let attributedText = NSMutableAttributedString(string: contactName,
                                                           attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                        NSAttributedString.Key.font: nameFont])

            attributedText.append(NSAttributedString(string: " "))

            if let commentText = MainAppContext.shared.contactStore.textWithMentions(feedPostComment.text, mentions: Array(feedPostComment.mentions ?? Set())),
                !feedPostComment.isRetracted
            {
                attributedText.append(commentText.with(font: baseFont).applyingFontForMentions(nameFont))
            }

            attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))
            nameTextLabel.attributedText = attributedText
        }
    }

    func updateWith(comment: FeedPostComment) {
        feedPostCommentID = comment.id
        configure(withComment: comment)
        isReplyButtonVisible = comment.isPosted
        switch comment.status {
        case .sending:
            timestampLabel.text = Localizations.posting

        default:
            timestampLabel.text = comment.timestamp.feedTimestamp()
        }

        let isRootComment = comment.parent == nil
        profilePictureWidth.constant = isRootComment ? LayoutConstants.profilePictureSizeNormal : LayoutConstants.profilePictureSizeSmall
        profilePictureTrailingSpace.constant = isRootComment ? LayoutConstants.profilePictureTrailingSpaceNormal : LayoutConstants.profilePictureTrailingSpaceSmall
        leadingMargin.constant = isRootComment ? LayoutConstants.profilePictureLeadingMarginNormal : LayoutConstants.profilePictureLeadingMarginReply

        switch comment.status {
        case .retracted:
            showDeletedView()
            deletedCommentTextLabel.text = Localizations.commentDeleted
        case .retracting:
            showDeletedView()
            deletedCommentTextLabel.text = Localizations.commentIsBeingDeleted
        case .unsupported:
            showDeletedView()
            let attributedText = NSMutableAttributedString(string: "⚠️ " + Localizations.commentIsNotSupported)
            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                attributedText.append(NSAttributedString(string: " "))
                attributedText.append(link)
            }
            deletedCommentTextLabel.attributedText = attributedText.with(
                font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable,
                color: .secondaryLabel)
        case .incoming, .sendError, .sending, .sent, .none:
            hideDeletedView()
        }
        
        profilePictureButton.avatarView.configure(with: comment.userId, using: MainAppContext.shared.avatarStore)
    }

    private func showDeletedView() {
        deletedCommentView.isHidden = false
        if deletedCommentView.superview == nil {
            vStack.insertArrangedSubview(deletedCommentView, at: vStack.arrangedSubviews.firstIndex(of: nameTextLabel)! + 1)
        }
    }

    private func hideDeletedView() {
        // Use tags so as to not trigger lazy initialization of the view.
        if let deletedCommentView = vStack.arrangedSubviews.first(where: { $0.tag == CommentView.deletedCommentViewTag }) {
            deletedCommentView.isHidden = true
        }
    }

}

extension CommentView: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        if let commentID = feedPostCommentID {
            delegate?.commentView(view, forComment: commentID, didTapMediaAtIndex: index)
        }
    }
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {

    }
}

extension CommentView: TextLabelDelegate {
    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link:
            if let url = link.result?.url {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        default:
            DDLogError("CommentView/textLabelDidRequestHandleLink/error [unsupported link type]")
            break
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        DDLogError("CommentView/textLabelDidRequestToExpand/error [should not be collapsed]")
    }
}


class CommentsTableHeaderView: UIView {

    let profilePictureButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let contactNameLabel: UILabel = {
        let label = UILabel()
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: fontDescriptor.pointSize - 1)
        label.textColor = .label
        return label
    }()

    private(set) var mediaView: MediaCarouselView?

    let textLabel: TextLabel = {
        let label = TextLabel()
        return label
    }()

    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .natural
        return label
    }()

    private let vStack: UIStackView = {
        let vStack = UIStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        return vStack
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

        self.addSubview(profilePictureButton)

        vStack.addArrangedSubview(contactNameLabel)
        vStack.addArrangedSubview(timestampLabel)
        self.addSubview(vStack)

        profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeSmall).isActive = true
        profilePictureButton.heightAnchor.constraint(equalTo: profilePictureButton.widthAnchor).isActive = true
        profilePictureButton.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        profilePictureButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8).isActive = true // using layout margins yields incorrect layout
        profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        vStack.leadingAnchor.constraint(equalTo: profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceSmall).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 8).isActive = true // using layout margins yields incorrect layout
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator
        self.addSubview(separatorView)
        separatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        separatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
    }

    func configure(withPost feedPost: FeedPost) {
        // Contact name
        contactNameLabel.text = MainAppContext.shared.contactStore.fullName(for: feedPost.userId)

        // Media
        if let mediaView = mediaView {
            vStack.removeArrangedSubview(mediaView)
            mediaView.removeFromSuperview()
            self.mediaView = nil
        }
        if !feedPost.orderedMedia.isEmpty {
            let media = MainAppContext.shared.feedData.media(for: feedPost)
            MainAppContext.shared.feedData.loadImages(postID: feedPost.id)

            var configuration = MediaCarouselViewConfiguration.minimal
            configuration.downloadProgressViewSize = 24
            let mediaView = MediaCarouselView(media: media, configuration: configuration)
            mediaView.layoutMargins.top = 4
            mediaView.layoutMargins.bottom = 4
            mediaView.addConstraint({
                let constraint = NSLayoutConstraint.init(item: mediaView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 55)
                constraint.priority = .defaultHigh
                return constraint
            }())
            vStack.insertArrangedSubview(mediaView, at: vStack.arrangedSubviews.count - 1)
            self.mediaView = mediaView
        }

        // Text
        if let feedPostText = feedPost.text, !feedPostText.isEmpty {
            let textWithMentions = MainAppContext.shared.contactStore.textWithMentions(
                feedPostText,
                mentions: feedPost.orderedMentions)

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
            textLabel.attributedText = textWithMentions?.with(font: font, color: .label).applyingFontForMentions(boldFont)

            vStack.insertArrangedSubview(textLabel, at: vStack.arrangedSubviews.count - 1)
        } else {
            vStack.removeArrangedSubview(textLabel)
            textLabel.removeFromSuperview()
        }

        // Timestamp
        timestampLabel.text = feedPost.timestamp.feedTimestamp()
        
        // Avatar
        profilePictureButton.avatarView.configure(with: feedPost.userId, using: MainAppContext.shared.avatarStore)
    }
}

// MARK: AudioViewDelegate
extension CommentView: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        voiceCommentTimeLabel.text = time
    }
}
