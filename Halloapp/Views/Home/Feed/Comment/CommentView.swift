//
//  CommentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class CommentView: UIView {
    private var leadingMargin: NSLayoutConstraint?
    var isContentInset: Bool = false {
        didSet {
            if let margin = self.leadingMargin {
                margin.constant = self.isContentInset ? 12 : 0
            }
        }
    }

    var isReplyButtonVisible: Bool = true {
        didSet {
            self.replyButton.isHidden = !self.isReplyButtonVisible
        }
    }

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()

    private lazy var textLabel: TextLabel = {
        let label = TextLabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private(set) lazy var replyButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitleColor(UIColor.systemGray, for: .normal)
        button.setTitle("Reply", for: .normal)
        button.titleLabel?.font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote).withSymbolicTraits(.traitBold)!, size: 0)
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
        view.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
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
        vStack.spacing = 4
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

        let imageSize: CGFloat = 30.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true

        self.leadingMargin = self.contactImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor)
        self.leadingMargin?.isActive = true
        self.contactImageView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.contactImageView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor).isActive = true

        self.vStack.leadingAnchor.constraint(equalTo: self.contactImageView.trailingAnchor, constant: 10).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    }

    private func contentString(author: String, text: String) -> ( NSAttributedString, Range<String.Index>? ) {
        let primaryFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: primaryFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: primaryFont.pointSize)
        let content = NSMutableAttributedString(string: author, attributes: [ NSAttributedString.Key.font: nameFont ])
        content.append(NSAttributedString(string: " \(text)", attributes: [ NSAttributedString.Key.font: primaryFont ]))
        content.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: content.length))
        return (content, content.string.range(of: author))
    }

    func updateWith(feedPost: FeedPost) {
        let contactName = AppContext.shared.contactStore.fullName(for: feedPost.userId)
        let comment = feedPost.text ?? ""
        let content = self.contentString(author: contactName, text: comment)
        self.textLabel.attributedText = content.0
        self.textLabel.hyperlinkDetectionIgnoreRange = content.1
        self.timestampLabel.text = feedPost.timestamp.commentTimestamp()
    }

    func updateWith(comment: FeedPostComment) {
        let contactName = AppContext.shared.contactStore.fullName(for: comment.userId)
        let content = self.contentString(author: contactName, text: comment.isCommentRetracted ? "" : comment.text)
        self.textLabel.attributedText = content.0
        self.textLabel.hyperlinkDetectionIgnoreRange = content.1
        self.timestampLabel.text = comment.timestamp.commentTimestamp()

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
