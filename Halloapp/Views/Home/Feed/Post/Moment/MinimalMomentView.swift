//
//  MinimalMomentView.swift
//  HalloApp
//
//  Created by Tanveer on 6/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon
import CocoaLumberjackSwift

/// Used for displaying the unlocking moment in `MomentViewController`.
class MinimalMomentView: UIView {

    private(set) var feedPost: FeedPost?
    private var mediaLoader: AnyCancellable?

    private var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.masksToBounds = true
        view.layer.cornerRadius = 4
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .momentPolaroid
        layer.masksToBounds = true
        layer.cornerRadius = 5

        addSubview(imageView)
        let padding: CGFloat = 3
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("MinimalMomentView coder init not implemented...")
    }

    func configure(with post: FeedPost) {
        guard let media = post.feedMedia.first else {
            DDLogError("MinimalMomentView/configure/post with no media")
            return
        }

        feedPost = post
        if media.isMediaAvailable {
            imageView.image = media.image
        } else {
            mediaLoader = media.$isMediaAvailable.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.imageView.image = media.image
            }
        }
    }
}
