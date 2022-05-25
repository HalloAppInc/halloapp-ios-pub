//
//  QuotedMediaPanel.swift
//  HalloApp
//
//  Created by Tanveer on 5/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import AVFoundation

class QuotedMediaPanel: UIStackView, InputContextPanel {
    var media: PendingMedia? {
        didSet { configure() }
    }

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        return view
    }()

    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .footnote, weight: .regular, maximumPointSize: 22)
        label.textColor = .secondaryLabel
        return label
    }()

    private(set) lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "xmark.circle.fill")?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = .systemGray
        return button
    }()

    private lazy var imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 0)
    private lazy var imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)

    var didSelect: ((PendingMedia) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .center
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 5, left: 0, bottom: 0, right: 0)

        addArrangedSubview(imageView)
        addArrangedSubview(durationLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            imageWidthConstraint,
            imageHeightConstraint,
            closeButton.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2),
            closeButton.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: -2),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(imageWasTapped))
        self.addGestureRecognizer(tap)
    }

    private func updateImageConstraints() {
        guard let image = imageView.image else {
            return
        }

        let ratio = image.size.width / image.size.height
        let maxHeight: CGFloat = 85
        let width = ratio * maxHeight

        imageHeightConstraint.constant = maxHeight
        imageWidthConstraint.constant = width
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    private func configure() {
        guard let media = media else {
            return reset()
        }

        switch media.type {
        case .image:
            imageView.image = media.image
            durationLabel.isHidden = true
            updateImageConstraints()
        case .video:
            guard let url = media.fileURL, let image = VideoUtils.videoPreviewImage(url: url) else {
                return
            }

            imageView.image = image
            durationLabel.isHidden = false
            durationLabel.text = duration(from: url)
            updateImageConstraints()
        case .audio:
            return
        }
    }

    private func duration(from video: URL) -> String? {
        let asset = AVURLAsset(url: video)
        let interval = TimeInterval(CMTimeGetSeconds(asset.duration))
        if var formatted = ContentInputView.durationFormatter.string(from: interval) {
            if formatted.hasPrefix("0"), formatted.count > 4 {
                formatted = String(formatted.dropFirst())
            }

            return formatted
        }

        return nil
    }

    private func reset() {
        imageView.image = nil
        durationLabel.text = nil

        imageHeightConstraint.constant = 0
        imageWidthConstraint.constant = 0
    }

    @objc
    private func imageWasTapped(_ sender: UITapGestureRecognizer) {
        if let media = media {
            didSelect?(media)
        }
    }
}
