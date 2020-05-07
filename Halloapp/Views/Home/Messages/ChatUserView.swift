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
    
    private lazy var sentTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkSingle")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray3
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var deliveredTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkDouble")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray3
        imageView.isHidden = true
        return imageView
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
        self.addSubview(self.deliveredTickImageView)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let vStack = UIStackView(arrangedSubviews: [ textView ])
        
        vStack.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 5)
        vStack.isLayoutMarginsRelativeArrangement = true

        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 4
        self.addSubview(vStack)
        
        let imageSize: CGFloat = 10.0
        
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .height, relatedBy: .equal, toItem: self.sentTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        
        NSLayoutConstraint(item: self.deliveredTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
        NSLayoutConstraint(item: self.deliveredTickImageView, attribute: .height, relatedBy: .equal, toItem: self.deliveredTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        
        let views = [ "vstack": vStack, "sentTick": self.sentTickImageView, "deliveredTick": self.deliveredTickImageView ]
        
        self.addConstraint({
            self.leadingMargin = NSLayoutConstraint(item: vStack, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: 0)
            return self.leadingMargin! }())
        
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "[vstack]-0-[sentTick]-(-8)-[deliveredTick]-10-|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[sentTick]-14-|", options: [], metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[deliveredTick]-14-|", options: [], metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[vstack]|", options: [], metrics: nil, views: views))
    }


    func clearTicks() {
        self.sentTickImageView.isHidden = true
        self.sentTickImageView.tintColor = UIColor.systemGray3
        self.deliveredTickImageView.isHidden = true
        self.deliveredTickImageView.tintColor = UIColor.systemGray3
    }
    
    func updateWith(chatMessageItem: ChatMessage) {

        switch chatMessageItem.senderStatus {
        case .seen:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemBlue
            self.deliveredTickImageView.isHidden = false
            self.deliveredTickImageView.tintColor = UIColor.systemBlue
        case .delivered:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = false
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        case .sentOut:
            self.sentTickImageView.isHidden = false
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = true
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        default:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = true
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        }
        
        let text = chatMessageItem.text ?? ""
        self.textView.text = text
    }

}


