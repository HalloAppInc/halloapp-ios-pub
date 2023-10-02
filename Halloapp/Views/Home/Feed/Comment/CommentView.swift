//
//  CommentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
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

extension Localizations {

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
    private(set) var commentLinkPreviewView: CommentLinkPreviewView?
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


        if let commentLinkPreviewView = commentLinkPreviewView {
            vStack.removeArrangedSubview(commentLinkPreviewView)
            commentLinkPreviewView.removeFromSuperview()
            vStack.removeArrangedSubview(textCommentLabel)
            textCommentLabel.removeFromSuperview()
            self.commentLinkPreviewView = nil
        }

        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
 
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: feedPostComment.id)
        let feedPostCommentText = feedPostComment.rawText + cryptoResultString

        if let feedCommentMedia = feedPostComment.media,
           let media = MainAppContext.shared.feedData.media(commentID: feedPostComment.id, in: MainAppContext.shared.feedData.viewContext),
           feedCommentMedia.count > 0 {

            // Set Name
            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
            let contactName = feedPostComment.user.displayName
            let attributedText = NSMutableAttributedString(string: contactName,
                                                           attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                        NSAttributedString.Key.font: nameFont])
            attributedText.append(NSAttributedString(string: " "))
            attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))
            nameTextLabel.attributedText = attributedText

            if media.count == 1 && media[0].type == .audio {
                voiceCommentRow.isHidden = false

                if voiceCommentView.url != media[0].fileURL {
                    voiceCommentTimeLabel.text = "0:00"
                    voiceCommentView.url = media[0].fileURL
                }

                if !voiceCommentView.isPlaying {
                    let isOwn = feedPostComment.userId == MainAppContext.shared.userData.userId
                    voiceCommentView.state = feedPostComment.status == .played || isOwn ? .played : .normal
                }

                if media[0].fileURL == nil {
                    voiceCommentView.state = .loading

                    mediaStatusCancellable = media[0].mediaStatusDidChange.sink { [weak self] mediaItem in
                        guard let self = self else { return }
                        guard let url = mediaItem.fileURL else { return }
                        self.voiceCommentView.url = url

                        let isOwn = feedPostComment.userId == MainAppContext.shared.userData.userId
                        self.voiceCommentView.state = feedPostComment.status == .played || isOwn ? .played : .normal
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
                vStack.insertArrangedSubview(mediaView, at: vStack.arrangedSubviews.firstIndex(of: nameTextLabel)! + 1)
                mediaView.topAnchor.constraint(equalTo: nameTextLabel.bottomAnchor, constant: 20).isActive = true
                vStack.setCustomSpacing(4, after: nameTextLabel)
                self.mediaCarouselView = mediaCarouselView
            }

            // Text below media
            if !feedPostCommentText.isEmpty {
                let textWithMentions = UserProfile.text(with: feedPostComment.mentions,
                                                        collapsedText: feedPostCommentText,
                                                        in: MainAppContext.shared.mainDataStore.viewContext)
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
                let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
                let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
                if let attrText = textWithMentions?.with(font: font, color: .label) {
                    let ham = HAMarkdown(font: font, color: .label)
                    textCommentLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
                }

                textCommentLabel.delegate = self
                vStack.insertArrangedSubview(textCommentLabel, at: vStack.arrangedSubviews.count - 1)
                vStack.setCustomSpacing(4, after: mediaView)
            }
        } else if let feedLinkPreviews = feedPostComment.linkPreviews, let feedLinkPreview = feedLinkPreviews.first  {
            // Add name
            configureNameLabel(feedPostComment: feedPostComment)
            // Comment contains link previews
            configureLinkPreviewView(feedLinkPreview: feedLinkPreview)
            // Add text below link preview
            configureTextCommentLabel(feedPostComment: feedPostComment)

        } else if feedPostComment.isWaiting  {
            let contactName = feedPostComment.user.displayName
            let attributedText = NSMutableAttributedString(string: contactName,
                                                           attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                        NSAttributedString.Key.font: nameFont])
            attributedText.append(NSAttributedString(string: " "))
            nameTextLabel.attributedText = attributedText

        } else {
            // No media, set name and append text to name label
            let contactName = feedPostComment.user.displayName
            let attributedText = NSMutableAttributedString(string: contactName,
                                                           attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                        NSAttributedString.Key.font: nameFont])

            attributedText.append(NSAttributedString(string: " "))
            let commentText = UserProfile.text(with: feedPostComment.mentions,
                                               collapsedText: feedPostCommentText,
                                               in: MainAppContext.shared.mainDataStore.viewContext)

            if !feedPostComment.isRetracted, let commentText {
                let ham = HAMarkdown(font: baseFont, color: .label)
                let attrStr = ham.parse(commentText.with(font: baseFont))
                attributedText.append(attrStr.applyingFontForMentions(nameFont))
            }
    
            attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))
            nameTextLabel.attributedText = attributedText
        }
    }

    func configureLinkPreviewView(feedLinkPreview: CommonLinkPreview) {
        // Set Name
        MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
        let commentLinkPreviewView = CommentLinkPreviewView()
        commentLinkPreviewView.configure(linkPreview: feedLinkPreview)
        vStack.insertArrangedSubview(commentLinkPreviewView, at: vStack.arrangedSubviews.count - 1)
        commentLinkPreviewView.topAnchor.constraint(equalTo: vStack.topAnchor, constant: 20).isActive = true
        vStack.setCustomSpacing(4, after: commentLinkPreviewView)
        self.commentLinkPreviewView = commentLinkPreviewView
    }

    func configureNameLabel(feedPostComment: FeedPostComment) {
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let contactName = feedPostComment.user.displayName
        let attributedText = NSMutableAttributedString(string: contactName,
                                                       attributes: [NSAttributedString.Key.userMention: feedPostComment.userId,
                                                                    NSAttributedString.Key.font: nameFont])
        attributedText.append(NSAttributedString(string: " "))
        attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))
        nameTextLabel.attributedText = attributedText
    }

    func configureTextCommentLabel(feedPostComment: FeedPostComment) {
        if !feedPostComment.rawText.isEmpty {
            let textWithMentions = UserProfile.text(with: feedPostComment.mentions, 
                                                    collapsedText: feedPostComment.rawText,
                                                    in: MainAppContext.shared.mainDataStore.viewContext)
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: .label)
                textCommentLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }

            textCommentLabel.delegate = self
            vStack.insertArrangedSubview(textCommentLabel, at: vStack.arrangedSubviews.count - 1)
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
            let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: comment.id)
            let attributedText = NSMutableAttributedString(string: "⚠️ " + Localizations.commentIsNotSupported + cryptoResultString)
            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                attributedText.append(NSAttributedString(string: " "))
                attributedText.append(link)
            }
            deletedCommentTextLabel.attributedText = attributedText.with(
                font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable,
                color: .secondaryLabel)
        case .incoming, .sendError, .sending, .sent, .none, .played:
            hideDeletedView()
        case .rerequesting:
            if comment.isWaiting {
                showDeletedView()
                let waitingString = "🕓 " + Localizations.feedCommentWaiting
                let attributedString = Localizations.appendLearnMoreLabel(to: waitingString)
                deletedCommentTextLabel.attributedText = attributedString.with(
                    font: UIFont.preferredFont(forTextStyle: .subheadline).withItalicsIfAvailable,
                    color: .secondaryLabel)
            } else {
                hideDeletedView()
            }
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
                    URLRouter.shared.handleOrOpen(url: url)
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

    private let groupNameLabel: UILabel = {
        let label = UILabel()
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: fontDescriptor.pointSize - 1)
        label.textColor = .label
        label.isHidden = true
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
        let groupIndicatorColor = UIColor.groupNameArrowTint

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

    private(set) var mediaView: MediaCarouselView?

    private(set) var audioView: PostAudioView?

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
        self.preservesSuperviewLayoutMargins = true

        self.addSubview(profilePictureButton)

        vStack.addArrangedSubview(userAndGroupNameRow)
        vStack.addArrangedSubview(timestampLabel)
        self.addSubview(vStack)

        profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal).isActive = true
        profilePictureButton.heightAnchor.constraint(equalTo: profilePictureButton.widthAnchor).isActive = true
        profilePictureButton.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        profilePictureButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8).isActive = true // using layout margins yields incorrect layout
        profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        vStack.leadingAnchor.constraint(equalTo: profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 8).isActive = true // using layout margins yields incorrect layout
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separatorGray
        self.addSubview(separatorView)
        separatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        separatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
    }

    func configure(withPost feedPost: FeedPost) {
        self.feedPost = feedPost

        // Contact name
        contactNameLabel.text = feedPost.user.displayName

        let viewContext = MainAppContext.shared.chatData.viewContext

        if let groupId = feedPost.groupId, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: viewContext) {
            groupNameLabel.text = group.name
            groupNameLabel.isHidden = false
            groupIndicatorLabel.isHidden = false
        } else {
            groupNameLabel.isHidden = true
            groupIndicatorLabel.isHidden = true
        }
        // Media
        if let mediaView = mediaView {
            vStack.removeArrangedSubview(mediaView)
            mediaView.removeFromSuperview()
            self.mediaView = nil
        }
        if !feedPost.orderedMedia.isEmpty {
            let media = MainAppContext.shared.feedData.media(for: feedPost)
            MainAppContext.shared.feedData.loadImages(postID: feedPost.id)

            let imageAndVideoMedia = media.filter { [.image, .video].contains($0.type) }
            if !imageAndVideoMedia.isEmpty {
                var configuration = MediaCarouselViewConfiguration.minimal
                configuration.downloadProgressViewSize = 24
                let mediaView = MediaCarouselView(media: imageAndVideoMedia, configuration: configuration)
                mediaView.layoutMargins.top = 4
                mediaView.layoutMargins.bottom = 4
                let constraint = mediaView.heightAnchor.constraint(equalToConstant: 55)
                constraint.priority = .defaultHigh
                constraint.isActive = true
                vStack.insertArrangedSubview(mediaView, at: vStack.arrangedSubviews.count - 1)
                self.mediaView = mediaView
            }

            // Audio
            if let audioMedia = media.first(where: { $0.type == .audio }) {
                let audioView = audioView ?? PostAudioView(configuration: .comments)
                audioView.delegate = self
                audioView.feedMedia = audioMedia
                let isOwnPost = feedPost.userId == MainAppContext.shared.userData.userId
                audioView.isSeen = feedPost.status == .seen || isOwnPost
                vStack.insertArrangedSubview(audioView, at: max(vStack.arrangedSubviews.count - 1, 0))
                self.audioView = audioView
            } else if let audioView = audioView {
                vStack.removeArrangedSubview(audioView)
                audioView.removeFromSuperview()
                self.audioView = nil
            }
        }

        // Text
        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: feedPost.id)
        let postTextWithCryptoResult = (feedPost.rawText ?? "") + cryptoResultString

        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)

        if feedPost.isWaiting {
            let waitingString = "🕓 " + Localizations.feedPostWaiting
            let attributedString = Localizations.appendLearnMoreLabel(to: waitingString)
            let textFont = font.withItalicsIfAvailable
            textLabel.attributedText = attributedString.with(font: textFont, color: .label)
            textLabel.numberOfLines = 0
            vStack.insertArrangedSubview(textLabel, at: vStack.arrangedSubviews.count - 1)

        } else if !postTextWithCryptoResult.isEmpty {
            let textWithMentions = UserProfile.text(with: feedPost.orderedMentions,
                                                    collapsedText: postTextWithCryptoResult,
                                                    in: MainAppContext.shared.mainDataStore.viewContext)
            let boldFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
            if let attrText = textWithMentions?.with(font: font, color: .label) {
                let ham = HAMarkdown(font: font, color: .label)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(boldFont)
            }

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

// MARK: PostAudioViewDelegate
extension CommentsTableHeaderView: PostAudioViewDelegate {

    func postAudioView(_ postAudioView: PostAudioView, didUpdateIsPlayingTo isPlaying: Bool) {
        guard isPlaying, let feedPost = feedPost else {
            return
        }
        AppContext.shared.coreFeedData.sendSeenReceiptIfNecessary(for: feedPost)
        postAudioView.isSeen = true
    }
}

// MARK: AudioViewDelegate
extension CommentView: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        voiceCommentTimeLabel.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
        guard let commentId = feedPostCommentID else { return }
        voiceCommentView.state = .played
        MainAppContext.shared.feedData.markCommentAsPlayed(commentId: commentId)
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    }
}
