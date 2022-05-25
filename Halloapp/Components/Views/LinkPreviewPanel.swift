//
//  LinkPreviewPanel.swift
//  HalloApp
//
//  Created by Tanveer on 3/15/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core

class LinkPreviewPanel: UIView, InputContextPanel {
    var metadata: (UIImage?, LinkPreviewData)? {
        didSet { configure() }
    }
    
    init() {
        super.init(frame: .zero)
        
        addSubview(linkPreviewHStack)
        addSubview(activityIndicator)
        addSubview(closeButton)
        
        applyConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("LinkPreviewView coder init not implemented...")
    }
    
    private func applyConstraints() {
        let constraints = [
            activityIndicator.centerXAnchor.constraint(equalTo: self.layoutMarginsGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: self.layoutMarginsGuide.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: linkPreviewHStack.trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: linkPreviewHStack.topAnchor, constant: 8),
            linkPreviewMediaView.leadingAnchor.constraint(equalTo: linkPreviewHStack.leadingAnchor, constant: 8),
            linkPreviewHStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            linkPreviewHStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            linkPreviewHStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            linkPreviewHStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.heightAnchor.constraint(equalToConstant: 75)
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
    private func configure() {
        guard let metadata = metadata else {
            invalidateDisplay()
            return
        }

        display(metadata)
    }
    
    private func display(_ metadata: (UIImage?, LinkPreviewData)) {
        activityIndicator.stopAnimating()
        linkPreviewTitleLabel.text = metadata.1.title
        linkPreviewURLLabel.text = metadata.1.url.host
        
        linkPreviewMediaView.isHidden = false
        linkImageView.isHidden = false
        
        if let image = metadata.0 {
            linkPreviewMediaView.isHidden = false
            linkPreviewMediaView.image = image
            linkImageView.isHidden = false
        } else {
            linkPreviewMediaView.isHidden = true
            linkPreviewMediaView.image = nil
            linkImageView.isHidden = false
        }
    }
    
    private func invalidateDisplay() {
        activityIndicator.stopAnimating()
        linkPreviewTitleLabel.text = ""
        linkPreviewURLLabel.text = ""
        linkImageView.isHidden = true
        linkPreviewMediaView.image = nil
    }
    
    let activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    private lazy var linkPreviewTitleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(forTextStyle: .caption1, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.textColor = .label.withAlphaComponent(0.5)
        return titleLabel
    }()

    private lazy var linkImageView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()

    private lazy var linkPreviewURLLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.systemFont(forTextStyle: .caption1)
        urlLabel.textColor = .label.withAlphaComponent(0.5)
        urlLabel.textAlignment = .natural
        return urlLabel
    }()

    private var linkPreviewLinkStack: UIStackView {
        let linkStack = UIStackView(arrangedSubviews: [ linkImageView, linkPreviewURLLabel, UIView() ])
        linkStack.translatesAutoresizingMaskIntoConstraints = false
        linkStack.spacing = 2
        linkStack.alignment = .center
        linkStack.axis = .horizontal
        return linkStack
    }

    private lazy var linkPreviewTextStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ linkPreviewTitleLabel, linkPreviewLinkStack ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()

    private(set) lazy var linkPreviewMediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 8
        mediaView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        return mediaView
    }()

    private lazy var linkPreviewHStack: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ linkPreviewMediaView, linkPreviewTextStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = UIView()
        backgroundView.backgroundColor = .linkPreviewBackground
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        hStack.insertSubview(backgroundView, at: 0)
        backgroundView.leadingAnchor.constraint(equalTo: hStack.leadingAnchor).isActive = true
        backgroundView.topAnchor.constraint(equalTo: hStack.topAnchor).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: hStack.trailingAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor).isActive = true

        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.backgroundColor = .commentVoiceNoteBackground
        hStack.layer.borderWidth = 0.5
        hStack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        hStack.layer.cornerRadius = 15
        hStack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        hStack.layer.shadowOffset = CGSize(width: 0, height: 2)
        hStack.layer.shadowRadius = 4
        hStack.layer.shadowOpacity = 0.5
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.clipsToBounds = true

        return hStack
    }()
    
    private(set) lazy var closeButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate), for: .normal)

        closeButton.tintColor = .label.withAlphaComponent(0.5)
        closeButton.widthAnchor.constraint(equalToConstant: 12).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return closeButton
    }()
}
