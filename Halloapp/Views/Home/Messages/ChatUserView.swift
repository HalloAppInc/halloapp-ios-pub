//
//  ChatUserView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class ChatUserView: UIView {
    private var leadingMargin: NSLayoutConstraint?

    private lazy var sentTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "checkmark"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        
        return imageView
    }()
    
    private lazy var seenTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "checkmark"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        
        return imageView
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
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.tintColor = UIColor.link
        return textView
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
        
        self.backgroundColor = UIColor.systemBackground

        self.preservesSuperviewLayoutMargins = true

        self.addSubview(self.sentTickImageView)
        self.addSubview(self.seenTickImageView)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let vStack = UIStackView(arrangedSubviews: [ textView ])
        
        vStack.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 5)
        vStack.isLayoutMarginsRelativeArrangement = true

        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        self.addSubview(vStack)

        
        let imageSize: CGFloat = 12.0
        let views = [ "vstack": vStack, "sentTick": self.sentTickImageView, "seenTick": self.seenTickImageView ]
        
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .height, relatedBy: .equal, toItem: self.sentTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        
        NSLayoutConstraint(item: self.seenTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
        NSLayoutConstraint(item: self.seenTickImageView, attribute: .height, relatedBy: .equal, toItem: self.seenTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        
        self.addConstraint({
            self.leadingMargin = NSLayoutConstraint(item: vStack, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: 0)
            return self.leadingMargin! }())
        
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "[vstack]-(-3)-[sentTick]-(-4)-[seenTick]-5-|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[sentTick]-13-|", options: [], metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[seenTick]-13-|", options: [], metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[vstack]|", options: [], metrics: nil, views: views))
        
        self.sentTickImageView.isHidden = true
        self.seenTickImageView.isHidden = true
        
    }


    func updateWith(chatMessageItem: ChatMessage) {
        let text = chatMessageItem.text ?? ""
        self.textView.text = text
    }

}

