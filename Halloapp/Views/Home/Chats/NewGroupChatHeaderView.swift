//
//  NewGroupChatHeaderView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 6/22/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

private extension Localizations {
    static var chatNewGroupLabel: String {
        NSLocalizedString("chat.new.group.label", value: "New Group Chat", comment: "cta label for creating a new group chat")
    }
}

fileprivate struct Constants {
    static let PhotoIconSize: CGFloat = 36
}

protocol NewGroupChatHeaderViewDelegate: AnyObject {
    func newGroupChatHeaderView(_ newGroupChatHeaderView: NewGroupChatHeaderView)
}

class NewGroupChatHeaderView: UIView {
    weak var delegate: NewGroupChatHeaderViewDelegate?
    private lazy var newGroupChatIconView: UIView = {
        let newGroupChatIconView = UIView()
        newGroupChatIconView.backgroundColor = .systemBlue
        newGroupChatIconView.layer.cornerRadius = 0.5 * Constants.PhotoIconSize
        newGroupChatIconView.translatesAutoresizingMaskIntoConstraints = false

        let newGroupImageView = UIImageView()
        newGroupImageView.contentMode = .scaleAspectFill
        newGroupImageView.image = UIImage(named: "ProfileHeaderCamera")?.withRenderingMode(.alwaysTemplate)
        newGroupImageView.tintColor = .secondarySystemGroupedBackground
        newGroupImageView.translatesAutoresizingMaskIntoConstraints = false
        newGroupChatIconView.addSubview(newGroupImageView)

        NSLayoutConstraint.activate([
            newGroupImageView.widthAnchor.constraint(equalToConstant: 0.5 * Constants.PhotoIconSize),
            newGroupImageView.heightAnchor.constraint(equalToConstant: 0.5 * Constants.PhotoIconSize),
            newGroupImageView.centerXAnchor.constraint(equalTo: newGroupChatIconView.centerXAnchor),
            newGroupImageView.centerYAnchor.constraint(equalTo: newGroupChatIconView.centerYAnchor),

            newGroupChatIconView.widthAnchor.constraint(equalToConstant: Constants.PhotoIconSize),
            newGroupChatIconView.heightAnchor.constraint(equalToConstant: Constants.PhotoIconSize),
        ])

        return newGroupChatIconView
    }()

    private lazy var newGroupChatLabel: UILabel = {
        newGroupChatLabel = UILabel()
        newGroupChatLabel.translatesAutoresizingMaskIntoConstraints = false
        newGroupChatLabel.text = Localizations.chatNewGroupLabel
        newGroupChatLabel.textColor = .systemBlue
        return newGroupChatLabel
    }()

    private lazy var newGroupChatHeaderView: UIStackView = {
        let newGroupChatHeaderView = UIStackView(arrangedSubviews: [ newGroupChatIconView, newGroupChatLabel])
        newGroupChatHeaderView.translatesAutoresizingMaskIntoConstraints = false
        newGroupChatHeaderView.axis = .horizontal
        newGroupChatHeaderView.spacing = 10
        newGroupChatHeaderView.backgroundColor = .feedPostBackground
        newGroupChatHeaderView.layer.cornerRadius = 13
        newGroupChatHeaderView.isLayoutMarginsRelativeArrangement = true
        newGroupChatHeaderView.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return newGroupChatHeaderView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    private func setup() {
        addSubview(newGroupChatHeaderView)
        NSLayoutConstraint.activate([
            newGroupChatHeaderView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            newGroupChatHeaderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            newGroupChatHeaderView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            newGroupChatHeaderView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.createNewChatGroup(_:)))
        newGroupChatHeaderView.isUserInteractionEnabled = true
        newGroupChatHeaderView.addGestureRecognizer(tapGesture)
    }

    @objc func createNewChatGroup (_ sender: UITapGestureRecognizer) {
        self.delegate?.newGroupChatHeaderView(self)
    }
}
