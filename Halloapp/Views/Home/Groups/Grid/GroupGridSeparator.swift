//
//  GroupGridSeparator.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class GroupGridSeparator: UICollectionReusableView {

    static let elementKind = "separator"
    static let reuseIdentifier = String(describing: GroupGridSeparator.self)

    override init(frame: CGRect) {
        super.init(frame: frame)

        let separator = UIView()
        separator.backgroundColor = .label.withAlphaComponent(0.24)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
