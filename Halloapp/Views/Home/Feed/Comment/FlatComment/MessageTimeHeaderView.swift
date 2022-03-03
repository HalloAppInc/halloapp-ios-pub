//
//  MessageTimeHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 1/10/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class MessageTimeHeaderView: UICollectionReusableView {

    static var elementKind: String {
        return String(describing: MessageTimeHeaderView.self)
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
        self.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(headerText: String) {
        headerView.configure(headerText: headerText)
    }
}
