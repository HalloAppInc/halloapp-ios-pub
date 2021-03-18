//
//  BadgedButton.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class BadgedButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.isUserInteractionEnabled = false
        addSubview(badgeView)
        badgeView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeView.heightAnchor).isActive = true
        setupBadgeViewPositionConstraints()
    }
    // MARK: Badge

    private lazy var badgeView =  BadgeView()

    private var badgeViewPositionConstraints: [NSLayoutConstraint] = []

    private func setupBadgeViewPositionConstraints() {
        if !badgeViewPositionConstraints.isEmpty {
            removeConstraints(badgeViewPositionConstraints)
            badgeViewPositionConstraints.removeAll()
        }
        if let viewToAttachTo = badgeAnchor == .image ? imageView : titleLabel {
            badgeViewPositionConstraints.append(badgeView.centerXAnchor.constraint(equalTo: viewToAttachTo.trailingAnchor, constant: centerXConstant))
            badgeViewPositionConstraints.append(badgeView.centerYAnchor.constraint(equalTo: viewToAttachTo.topAnchor, constant: centerYConstant))
            addConstraints(badgeViewPositionConstraints)
        }
    }

    // MARK: Public

    enum BadgeAnchor {
        case text
        case image
    }

    public var badgeAnchor: BadgeAnchor = .image {
        didSet {
            if oldValue != badgeAnchor {
                setupBadgeViewPositionConstraints()
            }
        }
    }

    public var centerXConstant:CGFloat = 0 {
        didSet {
            if oldValue != centerXConstant {
                setupBadgeViewPositionConstraints()
            }
        }
    }
    public var centerYConstant:CGFloat = 0 {
        didSet {
            if oldValue != centerYConstant {
                setupBadgeViewPositionConstraints()
            }
        }
    }
    
    public var isBadgeHidden: Bool {
        get { badgeView.isHidden }
        set { badgeView.isHidden = newValue }
    }
}
