//
//  MessageCellViewEvent.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class MessageCellViewEvent: UICollectionViewCell {
    static var elementKind: String {
        return String(describing: MessageCellViewEvent.self)
    }

    var messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        label.alpha = 0.80
        label.textColor = UIColor.black
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    private lazy var messageView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ messageLabel])
        view.layoutMargins = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 18)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.messageEventHeaderBackground
        view.layer.cornerRadius = 7
        view.layer.masksToBounds = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.messageEventHeaderBorder.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0
        return view
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
        contentView.addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            messageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }

    func configure(headerText: String) {
        messageLabel.text = headerText
    }
}
