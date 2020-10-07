//
//  FacePileView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class FacePileView: UIControl {
    var avatarViews: [AvatarView] = []
    let numberOfFaces = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        for index in 0 ..< numberOfFaces {
            // The avatars are added from right to left
            let avatarView = AvatarView()
            avatarView.borderColor = .secondarySystemGroupedBackground
            avatarView.borderWidth = 2
            avatarView.isHidden = true
            avatarView.translatesAutoresizingMaskIntoConstraints = false

            self.addSubview(avatarView)
            avatarViews.append(avatarView)

            if index == 0 {
                // The rightmost avatar
                avatarView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            } else {
                let previousView = self.avatarViews[index - 1]
                avatarView.trailingAnchor.constraint(equalTo: previousView.centerXAnchor, constant: -3).isActive = true
            }

            avatarView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
            avatarView.heightAnchor.constraint(equalToConstant: 25).isActive = true
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor).isActive = true
        }

        let lastView = avatarViews.last!
        self.leadingAnchor.constraint(equalTo: lastView.leadingAnchor).isActive = true
        self.topAnchor.constraint(equalTo: lastView.topAnchor).isActive = true
        self.bottomAnchor.constraint(equalTo: lastView.bottomAnchor).isActive = true
    }

    func configure(with post: FeedPost) {
        let seenReceipts = MainAppContext.shared.feedData.seenReceipts(for: post)

        var usersWithAvatars: [UserAvatar] = []
        var usersWithoutAvatar: [UserAvatar] = []

        for receipt in seenReceipts {
            let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: receipt.userId)
            if !userAvatar.isEmpty {
                usersWithAvatars.append(userAvatar)
            } else {
                usersWithoutAvatar.append(userAvatar)
            }
            if usersWithAvatars.count >= numberOfFaces {
                break
            }
        }

        if usersWithAvatars.count < numberOfFaces {
            usersWithAvatars.append(contentsOf: usersWithoutAvatar.prefix(numberOfFaces - usersWithAvatars.count))
        }

        if !usersWithAvatars.isEmpty {
            // The avatars are applied from right to left
            usersWithAvatars.reverse()
            for userIndex in 0 ..< usersWithAvatars.count {
                let avatarView = avatarViews[userIndex]
                avatarView.isHidden = false
                avatarView.configure(with: usersWithAvatars[userIndex], using: MainAppContext.shared.avatarStore)

                switch usersWithAvatars.count - userIndex {
                case 3:
                    avatarView.imageAlpha = 0.7 // The rightmost avatar
                case 2:
                    avatarView.imageAlpha = 0.9 // The middle avatar
                default:
                    avatarView.imageAlpha = 1 // The leftmost avatar
                }

            }
        } else { // No one has seen this post. Just show a dummy avatar.
            guard let avatarView = avatarViews.first else { return }
            avatarView.resetImage()
            avatarView.imageAlpha = 1
            avatarView.isHidden = false
        }
    }

    func prepareForReuse() {
        for avatarView in avatarViews {
            avatarView.prepareForReuse()
            avatarView.isHidden = true
        }
    }
}
