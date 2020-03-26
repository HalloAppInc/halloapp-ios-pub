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

    private lazy var textLabel: UITextView = {
        let textView = UITextView()
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.dataDetectorTypes = [.phoneNumber, .link]
        textView.textContainerInset = .zero
        textView.layoutMargins = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
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
        hStack.preservesSuperviewLayoutMargins = true
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 8

        let vStack = UIStackView(arrangedSubviews: [ self.textLabel, hStack ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.preservesSuperviewLayoutMargins = true
        vStack.axis = .vertical
        vStack.spacing = 4
        self.addSubview(vStack)

        let imageSize: CGFloat = 30.0
        let views = [ "image": self.contactImageView, "vstack": vStack ]
        NSLayoutConstraint(item: self.contactImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
        NSLayoutConstraint(item: self.contactImageView, attribute: .height, relatedBy: .equal, toItem: self.contactImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        self.addConstraint({
            self.leadingMargin = NSLayoutConstraint(item: self.contactImageView, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leadingMargin, multiplier: 1, constant: 0)
            return self.leadingMargin! }())
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "[image]-10-[vstack]-|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-8-[image]->=8-|", options: [], metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-[vstack]-|", options: [], metrics: nil, views: views))
    }

    private func contentString(author: String, text: String) -> NSAttributedString {
        let primaryFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let nameFont = UIFont(descriptor: primaryFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: primaryFont.pointSize)
        let content = NSMutableAttributedString(string: author, attributes: [ NSAttributedString.Key.font: nameFont ])
        content.append(NSAttributedString(string: " \(text)", attributes: [ NSAttributedString.Key.font: primaryFont ]))
        content.addAttributes([ NSAttributedString.Key.foregroundColor: UIColor.label ], range: NSRange(location: 0, length: content.length))
        return content
    }

    func updateWith(feedItem: FeedDataItem) {
        let contactName = AppContext.shared.contactStore.fullName(for: feedItem.username)
        let comment = feedItem.text
        self.textLabel.attributedText = self.contentString(author: contactName, text: comment)
        self.timestampLabel.text = Utils().timeForm(dateStr: String(feedItem.timestamp))
    }

    func updateWith(commentItem: FeedComments) {
        if let comment = commentItem.text, let username = commentItem.username {
            let contactName = AppContext.shared.contactStore.fullName(for: username)
            self.textLabel.attributedText = self.contentString(author: contactName, text: comment)
        }
        self.timestampLabel.text = Utils().timeForm(dateStr: String(commentItem.timestamp))
    }
}
