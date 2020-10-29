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
    private(set) var avatarViewButton: AvatarViewButton!

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.label.withAlphaComponent(0.8)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = MainAppContext.shared.userData.name
        return label
    }()

    var isDisplayingName: Bool = true {
        didSet {
            vStack.spacing = isDisplayingName ? 16 : 0
            nameLabel.isHidden = !isDisplayingName
        }
    }

    var canEditProfile: Bool = false {
        didSet {
            if canEditProfile {
                addCameraOverlayToAvatarViewButton()
                avatarViewButton.isUserInteractionEnabled = true
            } else {
                avatarViewButton.avatarView.placeholderOverlayView = nil
                avatarViewButton.isUserInteractionEnabled = false
            }
        }
    }

    private func addCameraOverlayToAvatarViewButton() {
        let overlayViewDiameter: CGFloat = 27
        let cameraOverlayView = UIButton(type: .custom)
        cameraOverlayView.bounds.size = CGSize(width: overlayViewDiameter, height: overlayViewDiameter)
        cameraOverlayView.translatesAutoresizingMaskIntoConstraints = false
        cameraOverlayView.setBackgroundColor(.systemBlue, for: .normal)
        cameraOverlayView.setImage(UIImage(named: "ProfileHeaderCamera")?.withRenderingMode(.alwaysTemplate), for: .normal)
        cameraOverlayView.tintColor = .white
        cameraOverlayView.layer.cornerRadius = 0.5 * overlayViewDiameter
        cameraOverlayView.layer.masksToBounds = true
        avatarViewButton.avatarView.placeholderOverlayView = cameraOverlayView
        avatarViewButton.addConstraints([
            cameraOverlayView.widthAnchor.constraint(equalToConstant: overlayViewDiameter),
            cameraOverlayView.heightAnchor.constraint(equalTo: cameraOverlayView.widthAnchor),
            cameraOverlayView.bottomAnchor.constraint(equalTo: avatarViewButton.avatarView.bottomAnchor),
            cameraOverlayView.trailingAnchor.constraint(equalTo: avatarViewButton.avatarView.trailingAnchor, constant: 8)
        ])
    }

    private func reloadNameLabelFont() {
        nameLabel.font = UIFont.gothamFont(ofSize: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).pointSize + 1, weight: .medium)
    }

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        layoutMargins.top = 32

        avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.isUserInteractionEnabled = canEditProfile

        reloadNameLabelFont()
        NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            self.reloadNameLabelFont()
        }

        vStack = UIStackView(arrangedSubviews: [ avatarViewButton, nameLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 16
        vStack.axis = .vertical
        vStack.alignment = .center
        addSubview(vStack)
        vStack.constrainMargins(to: self, priority: .required - 10) // because UIKit temporarily might set header view's width to zero.

        addConstraints([ avatarViewButton.heightAnchor.constraint(equalToConstant: 70),
                         avatarViewButton.widthAnchor.constraint(equalTo: avatarViewButton.heightAnchor) ])
    }

    func updateMyProfile(name: String) {
        avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        nameLabel.text = name
    }

    func updateProfile(userID: UserID) {
        avatarViewButton.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
    }
}
