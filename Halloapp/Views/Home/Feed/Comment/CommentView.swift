//
//  CommentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

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

class CommentView: UIView {

    // MARK: Variable Constraints
    private var leadingMargin: NSLayoutConstraint!
    private var profilePictureWidth: NSLayoutConstraint!
    private var profilePictureTrailingSpace: NSLayoutConstraint!
  
    var isReplyButtonVisible: Bool = true {
        didSet {
            self.replyButton.alpha = self.isReplyButtonVisible ? 1 : 0
        }
    }

    private(set) lazy var profilePictureButton: AvatarViewButton = {
        let button = AvatarViewButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private(set) lazy var textLabel: TextLabel = {
        let label = TextLabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        button.setTitle("Reply", for: .normal)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
        button.titleLabel?.font = .systemFont(ofSize: fontDescriptor.pointSize, weight: .bold)
        return button
    }()

    static let deletedCommentViewTag = 1
    private var deletedCommentTextLabel: UILabel!
    private lazy var deletedCommentView: UIView = {
        deletedCommentTextLabel = UILabel()
        deletedCommentTextLabel.translatesAutoresizingMaskIntoConstraints = false
        deletedCommentTextLabel.textColor = .secondaryLabel
        deletedCommentTextLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
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

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
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

        self.addSubview(self.profilePictureButton)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let hStack = UIStackView(arrangedSubviews: [ self.timestampLabel, self.replyButton, spacer ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 8

        vStack.addArrangedSubview(self.textLabel)
        vStack.addArrangedSubview(hStack)
        self.addSubview(self.vStack)
        
        self.profilePictureWidth = self.profilePictureButton.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal)
        self.profilePictureButton.heightAnchor.constraint(equalTo: self.profilePictureButton.widthAnchor).isActive = true
        self.profilePictureWidth.isActive = true

        self.leadingMargin = self.profilePictureButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: LayoutConstants.profilePictureLeadingMarginNormal)
        self.leadingMargin.isActive = true
        self.profilePictureButton.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.profilePictureButton.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor).isActive = true

        self.profilePictureTrailingSpace = self.vStack.leadingAnchor.constraint(equalTo: self.profilePictureButton.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal)
        self.profilePictureTrailingSpace.isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }

    func updateWith(comment: FeedPostComment) {
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

        let contactName = MainAppContext.shared.contactStore.fullName(for: comment.userId)
        let attributedText = NSMutableAttributedString(
            string: contactName,
            attributes: [NSAttributedString.Key.userMention: comment.userId,
                         NSAttributedString.Key.font: nameFont])

        attributedText.append(NSAttributedString(string: " "))

        if let commentText = MainAppContext.shared.contactStore.textWithMentions(comment.text, orderedMentions: comment.orderedMentions),
            !comment.isRetracted
        {
            attributedText.append(commentText.with(font: baseFont))
        }

        attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))

        self.textLabel.attributedText = attributedText
        self.timestampLabel.text = comment.timestamp.feedTimestamp()
        self.isReplyButtonVisible = comment.isPosted

        let isRootComment = comment.parent == nil
        self.profilePictureWidth.constant = isRootComment ? LayoutConstants.profilePictureSizeNormal : LayoutConstants.profilePictureSizeSmall
        self.profilePictureTrailingSpace.constant = isRootComment ? LayoutConstants.profilePictureTrailingSpaceNormal : LayoutConstants.profilePictureTrailingSpaceSmall
        self.leadingMargin.constant = isRootComment ? LayoutConstants.profilePictureLeadingMarginNormal : LayoutConstants.profilePictureLeadingMarginReply

        if comment.isRetracted {
            self.deletedCommentView.isHidden = false
            deletedCommentTextLabel.text = comment.status == .retracted ? "This comment has been deleted" : "Deleting comment"
            if self.deletedCommentView.superview == nil {
                self.vStack.insertArrangedSubview(self.deletedCommentView, at: self.vStack.arrangedSubviews.firstIndex(of: self.textLabel)! + 1)
            }
        } else {
            // Hide "This comment has been deleted" view.
            // Use tags so as to not trigger lazy initialization of the view.
            if let deletedCommentView = self.vStack.arrangedSubviews.first(where: { $0.tag == CommentView.deletedCommentViewTag }) {
                deletedCommentView.isHidden = true
            }
        }
        
        profilePictureButton.avatarView.configure(with: comment.userId, using: MainAppContext.shared.avatarStore)
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
        label.numberOfLines = 0
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
        if !feedPost.orderedMedia.isEmpty, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: feedPost.id) {
            feedDataItem.loadImages()

            var configuration = MediaCarouselViewConfiguration.minimal
            configuration.downloadProgressViewSize = 24
            let mediaView = MediaCarouselView(feedDataItem: feedDataItem, configuration: configuration)
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
                orderedMentions: feedPost.orderedMentions)

            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            let font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
            textLabel.attributedText = textWithMentions?.with(font: font, color: .label)

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
