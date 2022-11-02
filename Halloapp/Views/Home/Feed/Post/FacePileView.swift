//
//  FacePileView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class FacePileView: UIControl {
    var avatarViews: [AvatarView] = []
    var reactionViews: [UILabel] = []
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
            avatarView.borderWidth = 3
            avatarView.isHidden = true
            avatarView.translatesAutoresizingMaskIntoConstraints = false

            let reactionView = UILabel()
            reactionView.isHidden = true
            reactionView.font = .systemFont(ofSize: 14)
            reactionView.translatesAutoresizingMaskIntoConstraints = false

            self.addSubview(avatarView)
            self.addSubview(reactionView)
            avatarViews.append(avatarView)
            reactionViews.append(reactionView)

            if index == 0 {
                // The rightmost avatar
                avatarView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            } else {
                let previousView = self.avatarViews[index - 1]
                avatarView.trailingAnchor.constraint(equalTo: previousView.centerXAnchor, constant: -3).isActive = true
            }

            let diameter: CGFloat = 27

            avatarView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
            avatarView.heightAnchor.constraint(equalToConstant: diameter).isActive = true
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor).isActive = true

            let offset = diameter / 2 * (M_SQRT2 - 1) / M_SQRT2
            reactionView.centerXAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: -offset).isActive = true
            reactionView.centerYAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: -offset).isActive = true
        }

        if let lastView = avatarViews.last {
            self.leadingAnchor.constraint(equalTo: lastView.leadingAnchor).isActive = true
            self.topAnchor.constraint(equalTo: lastView.topAnchor).isActive = true
            self.bottomAnchor.constraint(equalTo: lastView.bottomAnchor).isActive = true
        }
    }

    func configure(with post: FeedPostDisplayable) {
        let receiptsToShow = post.seenReceipts.prefix(numberOfFaces).reversed()

        if !receiptsToShow.isEmpty {
            for (userIndex, receipt) in receiptsToShow.enumerated() {
                let avatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: receipt.userId)
                let avatarView = avatarViews[userIndex]
                avatarView.isHidden = false
                avatarView.configure(with: avatar, using: MainAppContext.shared.avatarStore)

                let reactionView = reactionViews[userIndex]
                reactionView.text = receipt.reaction
                reactionView.isHidden = (receipt.reaction ?? "").isEmpty
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

        for reactionView in reactionViews {
            reactionView.isHidden = true
        }
    }
}

class ReactionPileView: UIControl {
    var reactionViews: [UILabel] = []
    let numberOfReactions = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        for index in 0 ..< numberOfReactions {
            // The reactions are added from right to left

            let reactionView = UILabel()
            reactionView.isHidden = true
            reactionView.translatesAutoresizingMaskIntoConstraints = false

            self.addSubview(reactionView)
            reactionViews.append(reactionView)

            if index == 0 {
                // The rightmost reaction
                reactionView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            } else {
                let previousView = self.reactionViews[index - 1]
                reactionView.trailingAnchor.constraint(equalTo: previousView.centerXAnchor, constant: -3).isActive = true
            }

            let diameter: CGFloat = 27

            reactionView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
            reactionView.heightAnchor.constraint(equalToConstant: diameter).isActive = true
            reactionView.widthAnchor.constraint(equalTo: reactionView.heightAnchor).isActive = true
        }

        if let lastView = reactionViews.last {
            self.leadingAnchor.constraint(equalTo: lastView.leadingAnchor).isActive = true
            self.topAnchor.constraint(equalTo: lastView.topAnchor).isActive = true
            self.bottomAnchor.constraint(equalTo: lastView.bottomAnchor).isActive = true
        }
    }

    func configure(with post: FeedPostDisplayable) {
        let reactionsToShow = post.postReactions.suffix(numberOfReactions)

        for (i, reactionView) in reactionViews.enumerated() {
            if i < reactionsToShow.count {
                let (_, reaction) = reactionsToShow[i]
                reactionView.text = reaction
                reactionView.isHidden = reaction.isEmpty
            } else {
                reactionView.isHidden = true
            }
        }
    }

    func prepareForReuse() {
        for reactionView in reactionViews {
            reactionView.isHidden = true
        }
    }
}
