//
//  PostComposerLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/19/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import Combine
import UIKit

private extension Localizations {
    static var loadingPreview: String {
        NSLocalizedString("loading.preview", value: "Loading Preview...", comment: "Displayed while waiting for link preview to load")
    }
}

public class PostComposerLinkPreviewView: UIView {

    private let didFinish: ((Bool, LinkPreviewData?, UIImage?) -> Void)
    private var latestURL: URL?
    private var linkPreviewUrl: URL?
    private var linkDetectionTimer = Timer()
    private var linkPreviewData: LinkPreviewData?
    private var linkViewImage: UIImage?


    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.text = Localizations.loadingPreview
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .natural
        return titleLabel
    }()

    private lazy var linkPreviewCloseButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "CloseCircle"), for: .normal)
        closeButton.addTarget(self, action: #selector(didTapCloseLinkPreviewPanel), for: .touchUpInside)
        return closeButton
    }()

    private lazy var linkView: PostLinkPreviewView = {
        let linkView = PostLinkPreviewView()
        linkView.translatesAutoresizingMaskIntoConstraints = false
        return linkView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [ titleLabel , linkPreviewCloseButton ])
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6

        stack.clipsToBounds = true
        stack.distribution = .fillProportionally
        stack.isLayoutMarginsRelativeArrangement = false
        return stack
    }()

    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }

    public init(didFinish: @escaping ((Bool, LinkPreviewData?, UIImage?) -> Void)) {
        self.didFinish = didFinish
        super.init(frame: .zero)

        backgroundColor = .commentVoiceNoteBackground
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.cornerRadius = 15
        layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.5
        preservesSuperviewLayoutMargins = true
        addSubview(vStack)

        NSLayoutConstraint.activate([
            titleLabel.heightAnchor.constraint(equalToConstant: 187),
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        self.addSubview(linkPreviewCloseButton)

        NSLayoutConstraint.activate([
            linkPreviewCloseButton.trailingAnchor.constraint(equalTo: vStack.trailingAnchor, constant: -10),
            linkPreviewCloseButton.topAnchor.constraint(equalTo: vStack.topAnchor, constant: 10)
        ])
    }

    public func updateLink(url: URL?) {
        latestURL = url
        if !linkDetectionTimer.isValid {
            // Start timer for 1 second before fetching link preview.
            setLinkDetectionTimers(url: url)
        }
    }

    private func setLinkDetectionTimers(url: URL?) {
        linkPreviewUrl = url
        linkDetectionTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateLinkDetectionTimer), userInfo: nil, repeats: true)
    }

    @objc private func updateLinkDetectionTimer() {
        linkDetectionTimer.invalidate()
        // After waiting for 1 second, if the url did not change, fetch link preview info
            if latestURL == linkPreviewUrl {
                // Have we already fetched the link? then do not fetch again
                if linkView.linkPreviewData?.url == latestURL {
                    return
                }
                fetchURLPreview()
            } else {
                // link has changed... reset link fetch cycle
                setLinkDetectionTimers(url: latestURL)
            }
    }

    func fetchURLPreview() {
        guard let url = linkPreviewUrl else { return }
        self.titleLabel.isHidden = false
        self.vStack.removeArrangedSubview(linkView)
        linkView.removeFromSuperview()
        LinkPreviewMetadataProvider.startFetchingMetadata(for: url) { linkPreviewData, previewImage, error in
            guard let data = linkPreviewData, error == nil else {
                // Error fetching link preview.. remove link preview loading state
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.resetLinkDetection()
                    self.didFinish(true, self.linkPreviewData, self.linkViewImage)
                }
                return
            }
            self.linkPreviewData = data
            self.linkViewImage = previewImage
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.linkView.configure(linkPreviewData: data, previewImage: previewImage)
                self.titleLabel.isHidden = true
                self.vStack.addArrangedSubview(self.linkView)
                NSLayoutConstraint.activate([
                   self.linkView.leadingAnchor.constraint(equalTo: self.vStack.leadingAnchor),
                   self.linkView.trailingAnchor.constraint(equalTo: self.vStack.trailingAnchor),
                   self.linkView.topAnchor.constraint(equalTo: self.vStack.topAnchor),
                   self.linkView.bottomAnchor.constraint(equalTo: self.vStack.bottomAnchor)
                ])
                self.didFinish(false, self.linkPreviewData, self.linkViewImage)
            }
        }
    }

    @objc private func didTapCloseLinkPreviewPanel() {
        resetLinkDetection()
        didFinish(true, self.linkPreviewData, self.linkViewImage)
    }

    private func resetLinkDetection() {
        linkDetectionTimer.invalidate()
        linkPreviewUrl = nil
        latestURL = nil
        linkPreviewData = nil
        linkViewImage = nil
    }
}
