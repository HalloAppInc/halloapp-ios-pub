//
//  UserProfileTableHeaderView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

final class UserProfileTableHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var vStack: UIStackView!

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.label.withAlphaComponent(0.8)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = MainAppContext.shared.userData.name
        return label
    }()

    var displayName: Bool = true {
        didSet {
            vStack.spacing = displayName ? 16 : 0
            nameLabel.isHidden = !displayName
        }
    }

    private func reloadNameLabelFont() {
        nameLabel.font = UIFont.gothamFont(ofSize: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).pointSize + 1, weight: .medium)
    }

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        layoutMargins.top = 16

        reloadNameLabelFont()
        NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { (notification) in
            self.reloadNameLabelFont()
        }

        vStack = UIStackView(arrangedSubviews: [ contactImageView, nameLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 16
        vStack.axis = .vertical
        vStack.alignment = .center
        addSubview(vStack)
        vStack.constrainMargins(to: self)

        contactImageView.heightAnchor.constraint(equalToConstant: 70).isActive = true
        contactImageView.widthAnchor.constraint(equalTo: contactImageView.heightAnchor).isActive = true
    }

    func updateMyProfile(name: String) {
        contactImageView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        nameLabel.text = name
    }

    func updateProfile(userID: UserID) {
        contactImageView.configure(with: userID, using: MainAppContext.shared.avatarStore)
    }
}
