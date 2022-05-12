//
//  ChatEventViewCell.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/3/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class ChatEventViewCell: UITableViewCell {

    public func configure(userID: UserID) {
        let fullname = MainAppContext.shared.contactStore.fullName(for: userID)
        keysChangedLabel.text = Localizations.chatEventSecurityKeysChanged(name: fullname)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        selectionStyle = .none
        backgroundColor = UIColor.primaryBg

        contentView.preservesSuperviewLayoutMargins = false

        contentView.addSubview(mainView)

        mainView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true

        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ keysChangedLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.distribution = .equalCentering
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var keysChangedLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.textAlignment = .center

        label.font = UIFont.italicSystemFont(ofSize: 16)
        label.textColor = .label.withAlphaComponent(0.7)

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

}
