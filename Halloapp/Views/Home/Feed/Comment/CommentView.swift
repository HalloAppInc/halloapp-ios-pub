//
//  CommentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class CommentView: UIView {

    // MARK: Variable Constraints
    private var leadingMargin: NSLayoutConstraint!
    private var profilePictureWidth: NSLayoutConstraint!
    private var profilePictureTrailingSpace: NSLayoutConstraint!

    // MARK: Constraint Constants
    static private let profilePictureSizeSmall: CGFloat = 20
    static private let profilePictureSizeNormal: CGFloat = 30
    static private let profilePictureTrailingSpaceSmall: CGFloat = 8
    static private let profilePictureTrailingSpaceNormal: CGFloat = 10

    var isContentInset: Bool = false {
        didSet {
            if let margin = self.leadingMargin {
                margin.constant = self.isContentInset ? 50 : 0
            }
        }
    }

    var isReplyButtonVisible: Bool = true {
        didSet {
            self.replyButton.alpha = self.isReplyButtonVisible ? 1 : 0
        }
    }

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray
        return imageView
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
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
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

        self.profilePictureWidth = self.contactImageView.widthAnchor.constraint(equalToConstant: Self.profilePictureSizeNormal)
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        self.profilePictureWidth.isActive = true

        self.leadingMargin = self.contactImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor)
        self.leadingMargin.isActive = true
        self.contactImageView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.contactImageView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor).isActive = true

        self.profilePictureTrailingSpace = self.vStack.leadingAnchor.constraint(equalTo: self.contactImageView.trailingAnchor, constant: Self.profilePictureTrailingSpaceNormal)
        self.profilePictureTrailingSpace.isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }

    private func contentString(author: String, text: String, font: UIFont) -> ( NSAttributedString, Range<String.Index>? ) {
        let nameFont = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
        let content = NSMutableAttributedString(string: author, attributes: [ NSAttributedString.Key.font: nameFont ])
        content.append(NSAttributedString(string: " \(text)", attributes: [ NSAttributedString.Key.font: font ]))
        content.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: content.length))
        return (content, content.string.range(of: author))
    }

    func updateWith(feedPost: FeedPost) {
        let contactName = MainAppContext.shared.contactStore.fullName(for: feedPost.userId)
        let comment = feedPost.text ?? ""
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let content = self.contentString(author: contactName, text: comment, font: UIFont(descriptor: font.fontDescriptor, size: font.pointSize - 1))
        self.textLabel.attributedText = content.0
        self.textLabel.hyperlinkDetectionIgnoreRange = content.1
        self.timestampLabel.text = feedPost.timestamp.commentTimestamp()
        self.profilePictureWidth.constant = Self.profilePictureSizeSmall
        self.profilePictureTrailingSpace.constant = Self.profilePictureTrailingSpaceSmall
    }

    func updateWith(comment: FeedPostComment) {
        let contactName = MainAppContext.shared.contactStore.fullName(for: comment.userId)
        let content = self.contentString(author: contactName, text: comment.isCommentRetracted ? "" : comment.text, font: UIFont.preferredFont(forTextStyle: .subheadline))
        self.textLabel.attributedText = content.0
        self.textLabel.hyperlinkDetectionIgnoreRange = content.1
        self.timestampLabel.text = comment.timestamp.commentTimestamp()
        self.isReplyButtonVisible = !comment.isCommentRetracted
        self.profilePictureWidth.constant = comment.parent == nil ? Self.profilePictureSizeNormal : Self.profilePictureSizeSmall
        self.profilePictureTrailingSpace.constant = comment.parent == nil ? Self.profilePictureTrailingSpaceNormal : Self.profilePictureTrailingSpaceSmall

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
    }
}
