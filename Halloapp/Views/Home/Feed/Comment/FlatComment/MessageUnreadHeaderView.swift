//
//  MessageUnreadHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 2/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class MessageUnreadHeaderView: UICollectionViewCell {

    static var elementKind: String {
        return String(describing: MessageUnreadHeaderView.self)
    }

    private var headerView: MessageHeaderView

    override init(frame: CGRect) {
        headerView = MessageHeaderView()
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        headerView = MessageHeaderView()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.preservesSuperviewLayoutMargins = true
        contentView.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func configure(headerText: String) {
        headerView.configure(headerText: headerText)
        headerView.timestampLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
    }
}
