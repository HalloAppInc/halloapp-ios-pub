//
//  ChatView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class ChatView: UIView {
    private var leadingMargin: NSLayoutConstraint?

    private lazy var mediaImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "photo"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var mediaLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "(media is not supported yet)"
        label.isHidden = true
        return label
    }()

    private lazy var hStack: UIStackView = {
        let hStack = UIStackView()
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 5)
        hStack.spacing = 0
        return hStack
    }()
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = UIColor.systemGray5
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.tintColor = UIColor.link
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        
        self.backgroundColor = UIColor.systemGray5
        
        self.preservesSuperviewLayoutMargins = true

        self.hStack.addArrangedSubview(self.mediaImageView)
        self.hStack.addArrangedSubview(self.mediaLabel)
        self.hStack.setCustomSpacing(10, after: self.mediaImageView)
        
        let vStack = UIStackView(arrangedSubviews: [ self.hStack, self.textView ])

        vStack.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.setCustomSpacing(0, after: self.hStack)
        self.addSubview(vStack)

        let views = [ "vstack": vStack ]

        self.addConstraint({
            self.leadingMargin = NSLayoutConstraint(item: vStack, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: 0)
            return self.leadingMargin! }())
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "[vstack]|", options: .directionLeadingToTrailing, metrics: nil, views: views))
    
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[vstack]|", options: [], metrics: nil, views: views))
    }

    func clearMedia() {
        self.mediaImageView.isHidden = true
        self.mediaLabel.isHidden = true
    }
    
    func updateWith(chatMessageItem: ChatMessage) {
        let text = chatMessageItem.text ?? ""
        self.textView.text = text
        
        if let media = chatMessageItem.media {
            if media.count > 0 {
                self.mediaImageView.isHidden = false
                self.mediaLabel.isHidden = false
            }
        }
        
    }

}
