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

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.masksToBounds = true
        view.layer.cornerRadius = 4
        return view
    }()

    private lazy var overlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black.withAlphaComponent(0.5)
        return view
    }()

    private lazy var progressControl: UploadProgressControl = {
        let control = UploadProgressControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.tintColor = .white.withAlphaComponent(0.9)
        control.showSuccessIndicator = true

        control.onRetry = { [weak self] in
            if let id = self?.feedPost?.id {
                MainAppContext.shared.feedData.retryPosting(postId: id)
            }
        }

        return control
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .momentPolaroid
        layer.masksToBounds = true
        layer.cornerRadius = 5

        addSubview(imageView)
        addSubview(overlay)
        addSubview(progressControl)

        let padding: CGFloat = 3
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            overlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            progressControl.widthAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.4),
            progressControl.heightAnchor.constraint(equalTo: progressControl.widthAnchor),
            progressControl.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            progressControl.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
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

        progressControl.configure(with: post)
    }
}
