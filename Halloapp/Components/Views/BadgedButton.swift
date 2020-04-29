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
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private func setupView() {
        self.badgeView.translatesAutoresizingMaskIntoConstraints = false
        self.badgeView.isUserInteractionEnabled = false
        self.addSubview(self.badgeView)
        self.badgeView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        self.badgeView.widthAnchor.constraint(equalTo: self.badgeView.heightAnchor).isActive = true
        self.setupBadgeViewPositionConstraints()
    }
    // MARK: Badge

    private lazy var badgeView =  BadgeView()

    private var badgeViewPositionConstraints: [NSLayoutConstraint] = []

    private func setupBadgeViewPositionConstraints() {
        if !self.badgeViewPositionConstraints.isEmpty {
            self.removeConstraints(self.badgeViewPositionConstraints)
            self.badgeViewPositionConstraints.removeAll()
        }
        if let viewToAttachTo = self.badgeAnchor == .image ? self.imageView : self.titleLabel {
            self.badgeViewPositionConstraints.append(self.badgeView.centerXAnchor.constraint(equalTo: viewToAttachTo.trailingAnchor))
            self.badgeViewPositionConstraints.append(self.badgeView.centerYAnchor.constraint(equalTo: viewToAttachTo.topAnchor))
            self.addConstraints(self.badgeViewPositionConstraints)
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
                self.setupBadgeViewPositionConstraints()
            }
        }
    }

    public var isBadgeHidden: Bool {
        get { self.badgeView.isHidden }
        set { self.badgeView.isHidden = newValue }
    }
}
