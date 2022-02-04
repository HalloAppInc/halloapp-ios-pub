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

    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.alpha = 0.75
        label.textColor = .secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var timestampView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ timestampLabel])
        view.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 3, right: 18)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = UIColor.timeHeaderBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        view.insertSubview(subView, at: 0)
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
        self.addSubview(timestampView)
        NSLayoutConstraint.activate([
            timestampView.centerXAnchor.constraint(equalTo: centerXAnchor),
            timestampView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(headerText: String) {
        // Timestamp
        timestampLabel.text = headerText
    }

}
