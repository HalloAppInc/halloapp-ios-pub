//
//  MessageHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 2/9/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

enum MessageHeaderViewConfiguration {
    case small
    case large
}

class MessageHeaderView: UIView {

    var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.timeHeaderText
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    private lazy var timestampView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ timestampLabel])
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = ShadowView(frame: view.bounds)
        subView.backgroundColor = UIColor.timeHeaderBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = false
        subView.translatesAutoresizingMaskIntoConstraints = false
        subView.layer.borderWidth = 0.3
        subView.layer.borderColor = UIColor.primaryBlackWhite.withAlphaComponent(0.4).cgColor
        subView.layer.shadowColor = UIColor.black.cgColor
        subView.layer.shadowOpacity = 0.08
        subView.layer.shadowOffset = CGSize(width: 0, height: 1)
        subView.layer.shadowRadius = 0

        view.insertSubview(subView, at: 0)
        subView.constrain(to: view)
        return view
    }()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(_ messageHeaderViewConfiguration: MessageHeaderViewConfiguration = .small) {
        super.init(frame: .zero)
        commonInit(messageHeaderViewConfiguration: messageHeaderViewConfiguration)
    }

    private func commonInit(messageHeaderViewConfiguration: MessageHeaderViewConfiguration) {
        self.preservesSuperviewLayoutMargins = true
        self.addSubview(timestampView)
        NSLayoutConstraint.activate([
            timestampView.centerXAnchor.constraint(equalTo: centerXAnchor),
            timestampView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            timestampView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        switch messageHeaderViewConfiguration {
        case .small:
            timestampView.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 3, right: 18)
        case .large:
            timestampView.layoutMargins = UIEdgeInsets(top: 5, left: 25, bottom: 5, right: 25)
        }
    }

    func configure(headerText: String) {
        // Timestamp
        timestampLabel.text = headerText
    }
}
