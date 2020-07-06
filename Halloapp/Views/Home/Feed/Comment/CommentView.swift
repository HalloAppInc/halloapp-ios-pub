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

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
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
        button.titleLabel?.font = .systemFont(ofSize: fontDescriptor.pointSize, weight: .medium)
        return button
    }()

    static let deletedCommentViewTag = 1
    private lazy var deletedCommentView: UIView = {
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .secondaryLabel
        textLabel.text = "This comment has been deleted"
        textLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        let view = UIView()
        view.backgroundColor = .clear
        view.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tag = CommentView.deletedCommentViewTag
        view.addSubview(textLabel)
        textLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        textLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        textLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
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

        self.addSubview(self.contactImageView)

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
        
        self.profilePictureWidth = self.contactImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeNormal)
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        self.profilePictureWidth.isActive = true

        self.leadingMargin = self.contactImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: LayoutConstants.profilePictureLeadingMarginNormal)
        self.leadingMargin.isActive = true
        self.contactImageView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.contactImageView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor).isActive = true

        self.profilePictureTrailingSpace = self.vStack.leadingAnchor.constraint(equalTo: self.contactImageView.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceNormal)
        self.profilePictureTrailingSpace.isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }

    func updateWith(comment: FeedPostComment) {
        let contactName = MainAppContext.shared.contactStore.fullName(for: comment.userId)
        let commentText = comment.isCommentRetracted ? "" : comment.text
        let baseFont =  UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        let attributedText = NSMutableAttributedString(string: contactName, attributes: [ NSAttributedString.Key.font: nameFont ])
        attributedText.append(NSAttributedString(string: " \(commentText)", attributes: [ NSAttributedString.Key.font: baseFont ]))
        attributedText.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: attributedText.length))

        self.textLabel.attributedText = attributedText
        self.textLabel.hyperlinkDetectionIgnoreRange = attributedText.string.range(of: contactName)
        self.timestampLabel.text = comment.timestamp.commentTimestamp()
        self.isReplyButtonVisible = !comment.isCommentRetracted

        let isRootComment = comment.parent == nil
        self.profilePictureWidth.constant = isRootComment ? LayoutConstants.profilePictureSizeNormal : LayoutConstants.profilePictureSizeSmall
        self.profilePictureTrailingSpace.constant = isRootComment ? LayoutConstants.profilePictureTrailingSpaceNormal : LayoutConstants.profilePictureTrailingSpaceSmall
        self.leadingMargin.constant = isRootComment ? LayoutConstants.profilePictureLeadingMarginNormal : LayoutConstants.profilePictureLeadingMarginReply

        if comment.isCommentRetracted {
            self.deletedCommentView.isHidden = false
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
        
        contactImageView.configure(with: comment.userId, using: MainAppContext.shared.avatarStore)
    }
}


class CommentsTableHeaderView: UIView {
    private let contactImageView: AvatarView = {
        return AvatarView()
    }()

    private let contactNameLabel: UILabel = {
        let label = UILabel()
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: fontDescriptor.pointSize - 1)
        label.textColor = .label
        return label
    }()

    let textLabel: TextLabel = {
        let label = TextLabel()
        label.numberOfLines = 0
        label.textColor = .label
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 1)
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

        self.addSubview(contactImageView)

        vStack.addArrangedSubview(contactNameLabel)
        vStack.addArrangedSubview(timestampLabel)
        self.addSubview(vStack)

        contactImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.profilePictureSizeSmall).isActive = true
        contactImageView.heightAnchor.constraint(equalTo: contactImageView.widthAnchor).isActive = true
        contactImageView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        contactImageView.topAnchor.constraint(equalTo: self.topAnchor, constant: 8).isActive = true // using layout margins yields incorrect layout
        contactImageView.bottomAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        vStack.leadingAnchor.constraint(equalTo: contactImageView.trailingAnchor, constant: LayoutConstants.profilePictureTrailingSpaceSmall).isActive = true
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
        if !feedPost.orderedMedia.isEmpty, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: feedPost.id) {
            feedDataItem.loadImages()
            
            let mediaView = MediaCarouselView(feedDataItem: feedDataItem, configuration: MediaCarouselViewConfiguration.minimal)
            mediaView.layoutMargins.top = 4
            mediaView.layoutMargins.bottom = 4
            mediaView.addConstraint({
                let constraint = NSLayoutConstraint.init(item: mediaView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 55)
                constraint.priority = .defaultHigh
                return constraint
            }())
            vStack.insertArrangedSubview(mediaView, at: vStack.arrangedSubviews.count - 1)
        }

        // Text
        if let feedPostText = feedPost.text, !feedPostText.isEmpty {
            textLabel.text = feedPostText
            vStack.insertArrangedSubview(textLabel, at: vStack.arrangedSubviews.count - 1)
        } else {
            vStack.removeArrangedSubview(textLabel)
            textLabel.removeFromSuperview()
        }

        // Timestamp
        timestampLabel.text = feedPost.timestamp.commentTimestamp()
        
        // Avatar
        contactImageView.configure(with: feedPost.userId, using: MainAppContext.shared.avatarStore)
    }
}
