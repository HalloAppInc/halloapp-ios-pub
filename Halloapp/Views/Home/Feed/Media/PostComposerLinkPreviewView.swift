//
//  PostComposerLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/19/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import Combine
import LinkPresentation
import UIKit

class PostComposerLinkPreviewView: UIView {

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

    private lazy var linkView: LPLinkView = {
        let linkView = LPLinkView()
        return linkView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [ titleLabel ])
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.backgroundColor = .commentVoiceNoteBackground
        stack.layer.borderWidth = 0.5
        stack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        stack.layer.cornerRadius = 15
        stack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        stack.layer.shadowOffset = CGSize(width: 0, height: 2)
        stack.layer.shadowRadius = 4
        stack.layer.shadowOpacity = 0.5
        stack.isLayoutMarginsRelativeArrangement = true
        stack.clipsToBounds = true
        stack.distribution = .fillProportionally
        return stack
    }()

    required init?(coder: NSCoder) {
        fatalError("Use init(didFinish:)")
    }

    init(didFinish: @escaping ((Bool, LinkPreviewData?, UIImage?) -> Void)) {
        self.didFinish = didFinish
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true
        self.addSubview(vStack)

        vStack.heightAnchor.constraint(equalToConstant: 200).isActive = true
        vStack.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
    }

    func updateLink(url: URL?) {
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
                if linkView.metadata.originalURL == latestURL {
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
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = 10
        metadataProvider.startFetchingMetadata(for: url) { (metadata, error) in
            guard let data = metadata, error == nil else {
                // Error fetching link preview.. remove link preview loading state
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.resetLinkDetection()
                    self.didFinish(true, self.linkPreviewData, self.linkViewImage)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.titleLabel.isHidden = true
                self.linkView.metadata = data
                self.linkView.preservesSuperviewLayoutMargins = true
                self.vStack.insertArrangedSubview(self.linkView, at: self.vStack.arrangedSubviews.count)
                self.linkView.leadingAnchor.constraint(equalTo: self.vStack.leadingAnchor).isActive = true
                self.linkView.trailingAnchor.constraint(equalTo: self.vStack.trailingAnchor).isActive = true

                self.linkPreviewData = LinkPreviewData(id : nil, url: data.url, title: data.title ?? "", description: "", previewImages: [])
                if let imageProvider = data.imageProvider {
                    imageProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                        if let image = image as? UIImage {
                            self.linkViewImage = image
                            self.didFinish(false, self.linkPreviewData, self.linkViewImage)
                        }
                    }
                } else {
                    self.didFinish(false, self.linkPreviewData, self.linkViewImage)
                }
            }
        }
    }

    private func resetLinkDetection() {
        linkDetectionTimer.invalidate()
        linkPreviewUrl = nil
        latestURL = nil
        linkPreviewData = nil
        linkViewImage = nil
    }
}
