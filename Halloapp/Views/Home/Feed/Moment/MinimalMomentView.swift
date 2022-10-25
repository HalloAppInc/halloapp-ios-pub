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
    private var imageLoadingCancellables: Set<AnyCancellable> = []

    private var imageContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        view.layer.cornerRadius = 4
        return view
    }()

    private lazy var leadingImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        return view
    }()

    private lazy var trailingImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        return view
    }()

    private lazy var showTrailingImageViewConstraint: NSLayoutConstraint = {
        let constraint = trailingImageView.widthAnchor.constraint(equalTo: imageContainer.widthAnchor, multiplier: 0.5)
        return constraint
    }()

    private lazy var overlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black.withAlphaComponent(0.5)
        //view.layer.masksToBounds = true
        view.layer.cornerRadius = 4
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

        addSubview(imageContainer)
        imageContainer.addSubview(leadingImageView)
        imageContainer.addSubview(trailingImageView)
        addSubview(overlay)
        addSubview(progressControl)

        let padding: CGFloat = 3
        let hideTrailingImageViewConstraint = trailingImageView.widthAnchor.constraint(equalToConstant: 0)
        hideTrailingImageViewConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            imageContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            imageContainer.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),

            leadingImageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            leadingImageView.trailingAnchor.constraint(equalTo: trailingImageView.leadingAnchor),
            leadingImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            leadingImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            trailingImageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            trailingImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            trailingImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            hideTrailingImageViewConstraint,

            overlay.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            progressControl.widthAnchor.constraint(equalTo: imageContainer.widthAnchor, multiplier: 0.4),
            progressControl.heightAnchor.constraint(equalTo: progressControl.widthAnchor),
            progressControl.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            progressControl.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("MinimalMomentView coder init not implemented...")
    }

    func configure(with post: FeedPost) {
        imageLoadingCancellables = []
        feedPost = post

        guard let (leading, trailing) = arrangedMedia else {
            DDLogError("MinimalMomentView/configure/post with no media")
            return
        }

        leading.imagePublisher
            .sink { [weak self] image in
                self?.leadingImageView.image = image
            }
            .store(in: &imageLoadingCancellables)

        trailing?.imagePublisher
            .sink { [weak self] image in
                self?.trailingImageView.image = image
            }
            .store(in: &imageLoadingCancellables)

        [leading, trailing].forEach {
            $0?.loadImage()
        }

        showTrailingImageViewConstraint.isActive = trailing != nil
        progressControl.configure(with: post)
    }

    private var arrangedMedia: (leading: FeedMedia, trailing: FeedMedia?)? {
        guard let feedPost else {
            return nil
        }

        let media = feedPost.feedMedia

        if let selfieMedia = media.count == 2 ? media[1] : nil, let first = media.first {
            return feedPost.isMomentSelfieLeading ? (selfieMedia, first) : (first, selfieMedia)
        }

        if let first = media.first {
            return (first, nil)
        }

        return nil
    }

    /// A publisher that fires only once when the appropriate image views have been assigned images.
    var imageViewsAreReadyPublisher: AnyPublisher<Void, Never> {
        let leadingPublisher = leadingImageView.publisher(for: \.image)
            .compactMap {
                $0 != nil ? () : nil
            }
            .first()

        let trailingPublisher = !showTrailingImageViewConstraint.isActive ? nil : trailingImageView.publisher(for: \.image)
            .compactMap {
                $0 != nil ? () : nil
            }
            .first()

        let publishers = [leadingPublisher, trailingPublisher].compactMap { $0 }
        return Publishers.MergeMany(publishers)
            .collect()
            .map { _ in }
            .eraseToAnyPublisher()
    }
}
