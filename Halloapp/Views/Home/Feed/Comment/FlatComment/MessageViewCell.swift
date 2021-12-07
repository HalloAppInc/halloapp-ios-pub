//
//  MessageViewCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 12/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit

class MessageViewCell: UICollectionViewCell {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.feedBackground
        
        contentView.preservesSuperviewLayoutMargins = false
        
        contentView.addSubview(mainView)
        
        mainView.constrainMargins([.top, .leading, .trailing], to: contentView)
        mainView.constrainMargin(anchor: .bottom, to: contentView, priority: UILayoutPriority(rawValue: 999))
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ textView ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    

    private lazy var textView: UnselectableUITextView = {
        let textView = UnselectableUITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = .clear
        textView.textColor = UIColor.primaryBlackWhite
        textView.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]

        return textView
    }()
    
    func configureWithComment(comment: FeedPostComment) {
        textView.text = comment.text
    }

}
