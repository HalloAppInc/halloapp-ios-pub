//
//  MessageTimeHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 1/10/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core

class MessageTimeHeaderView: UICollectionReusableView {

    static var elementKind: String {
        return String(describing: MessageTimeHeaderView.self)
    }

    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.alpha = 0.75
        label.textColor = .secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        self.addSubview(timestampLabel)
        NSLayoutConstraint.activate([
            timestampLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timestampLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(headerText: String) {
        // Timestamp
        timestampLabel.text = headerText
    }

}
