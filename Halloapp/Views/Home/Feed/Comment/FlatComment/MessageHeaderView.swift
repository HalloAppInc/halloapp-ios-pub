//
//  MessageHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 2/9/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class MessageHeaderView: UIView {

    var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.alpha = 0.75
        label.textColor = UIColor.timeHeaderText
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    private lazy var timestampView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ timestampLabel])
        view.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 3, right: 18)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.backgroundColor = UIColor.timeHeaderBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(subView, at: 0)
        subView.constrain(to: view)
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
            timestampView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            timestampView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func configure(headerText: String) {
        // Timestamp
        timestampLabel.text = headerText
    }
}
