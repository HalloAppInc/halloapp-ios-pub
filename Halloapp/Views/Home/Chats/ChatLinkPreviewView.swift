//
//  ChatLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 11/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import Combine
import LinkPresentation
import UIKit
import SwiftUI

class ChatLinkPreviewView: UIView {

    private var imageLoadingCancellable: AnyCancellable?
    private var media: ChatMedia?
    private var chatLinkPreview: ChatLinkPreview?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(chatLinkPreview: ChatLinkPreview) {
        if let media = chatLinkPreview.media {
            self.media = media.first
        }
        self.chatLinkPreview  = chatLinkPreview
        commonInit()
    }
    
    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        progressView.heightAnchor.constraint(equalTo: progressView.widthAnchor, multiplier: 1).isActive = true
        return progressView
    }()

    private lazy var mediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return mediaView
    }()

    private lazy var urlLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .secondaryLabel
        urlLabel.textAlignment = .natural
        return urlLabel
    }()

    private lazy var linkIconView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var linkPreviewLinkStack: UIStackView {
        let linkStack = UIStackView(arrangedSubviews: [ linkIconView, urlLabel, UIView() ])
        linkStack.translatesAutoresizingMaskIntoConstraints = false
        linkStack.spacing = 2
        linkStack.alignment = .center
        linkStack.axis = .horizontal
        return linkStack
    }

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var textStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ titleLabel, linkPreviewLinkStack ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()

    private lazy var hStack: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [mediaView, textStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false

        mediaView.addSubview(progressView)
        progressView.centerXAnchor.constraint(equalTo: mediaView.centerXAnchor).isActive = true
        progressView.centerYAnchor.constraint(equalTo: mediaView.centerYAnchor).isActive = true
        progressView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        progressView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.clipsToBounds = true
        return hStack
    }()

    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        guard let chatLinkPreview = chatLinkPreview else { return }

        titleLabel.text = chatLinkPreview.title
        urlLabel.text = chatLinkPreview.url?.host
        configureMedia()
        self.addSubview(hStack)

        hStack.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.isUserInteractionEnabled = true
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
        if let url = chatLinkPreview?.url {
            URLRouter.shared.handleOrOpen(url: url)
        }
    }

    private func configureMedia() {
        guard let media = media else {
            progressView.isHidden = true
            mediaView.isHidden = true
            return
        }
        // Reset the media view to show a placeholder view and progress indicator
        progressView.isHidden = false
        mediaView.image = UIImage(systemName: "photo")
        mediaView.tintColor = .systemGray3
        mediaView.isHidden = false

        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath ?? "", isDirectory: false)

        if media.type == .image {
            if let image = UIImage(contentsOfFile: fileURL.path) {
                self.show(image: image)
            } else if imageLoadingCancellable == nil {
                showPlaceholderImage()
                imageLoadingCancellable = MainAppContext.shared.chatData.didGetLinkPreviewMediaDownloadProgress.sink { [weak self] (linkPreviewId, mediaOrder, progress, relativeFilePath) in
                    guard let self = self else { return }
                    guard linkPreviewId == self.chatLinkPreview?.id else { return }
                    DispatchQueue.main.async {
                        self.progressView.setProgress(Float(progress), animated: true)
                        if let relativeFilePath = relativeFilePath {
                            let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                            if let image = UIImage(contentsOfFile: fileURL.path) {
                                self.show(image: image)
                            }
                        }
                    }
                }
            }
        }
    }

    private func showPlaceholderImage() {
        mediaView.bringSubviewToFront(progressView)
        progressView.isHidden = false
    }

    func show(image: UIImage) {
        progressView.isHidden = true
        mediaView.image = image
        mediaView.isHidden = false
        // Loading cancellable is no longer needed
        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }
}
