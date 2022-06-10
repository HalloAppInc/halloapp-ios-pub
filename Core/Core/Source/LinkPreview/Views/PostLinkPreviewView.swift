//
//  PostLinkPreviewView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import UIKit
import SwiftUI


extension UIColor {
    class var linkPreviewPostBackground: UIColor {
        UIColor(named: "LinkPreviewPostBackground")!
    }

    class var linkPreviewPostSquareBackground: UIColor {
        UIColor(named: "LinkPreviewPostSquareBackground")!
    }

    class var linkPreviewPostSquareDarkBackground: UIColor {
        UIColor(named: "LinkPreviewPostSquareDarkBackground")!
    }
}

public enum LinkPreviewConfiguration{
    case rectangleImage
    case squareImage
    case noImage
}

public class PostLinkPreviewView: UIView {

    public var imageLoadingCancellable: AnyCancellable?
    public var downloadProgressCancellable: AnyCancellable?
    public var mediaStatusCancellable: AnyCancellable?
    public var linkPreviewURL: URL?
    public var linkPreviewData: LinkPreviewData?
    private var textStackHeightConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var previewImageHeightConstraint: NSLayoutConstraint?
    private var configuration: LinkPreviewConfiguration = .noImage
    private var rectangleLinkPreviewView: PostLinkPreviewRectangleView = PostLinkPreviewRectangleView()
    private var squareLinkPreviewView: PostLinkPreviewSquareView = PostLinkPreviewSquareView()
    private var noImageLinkPreviewView: PostLinkPreviewNoImageView = PostLinkPreviewNoImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
 
    private lazy var contentView: UIStackView = {
        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.backgroundColor = .linkPreviewPostBackground
        contentView.clipsToBounds = true
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        contentView.layer.cornerRadius = 15
        contentView.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        contentView.layer.shadowRadius = 4
        contentView.layer.shadowOpacity = 0.5
        contentView.translatesAutoresizingMaskIntoConstraints = false
        return contentView
    }()
    
    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }

    public func configure(linkPreviewData: LinkPreviewData, previewImage: UIImage?) {

        self.linkPreviewData = linkPreviewData
        
        setViewConfiguration(mediaSize: previewImage?.size)
        switch configuration {
        case .rectangleImage:
            guard let previewImage = previewImage else {
                return
            }
            rectangleLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title, previewImage: previewImage)
            contentView.addArrangedSubview(rectangleLinkPreviewView)
        case .squareImage:
            guard let previewImage = previewImage else {
                return
            }
            squareLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title, description: linkPreviewData.description, previewImage: previewImage)
            contentView.addArrangedSubview(squareLinkPreviewView)
        case .noImage:
            noImageLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title)
            contentView.addArrangedSubview(noImageLinkPreviewView)
        }
    }
    
    public func setViewConfiguration(mediaSize: CGSize?) {
        if let mediaSize = mediaSize {
            configuration = (mediaSize.width / mediaSize.height) >= 1.25 ? .rectangleImage : .squareImage
        } else {
            configuration = .noImage
        }
    }
    

    public func configureView(mediaSize: CGSize? = nil) {
        imageLoadingCancellable = nil
        mediaStatusCancellable = nil
        downloadProgressCancellable = nil
        guard let linkPreviewData = linkPreviewData else {
            return
        }
        setViewConfiguration(mediaSize: mediaSize)
        switch configuration {
        case .rectangleImage:
            squareLinkPreviewView.isHidden = true
            noImageLinkPreviewView.isHidden = true
            rectangleLinkPreviewView.isHidden = false
            rectangleLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title, previewImage: nil)
            contentView.addArrangedSubview(rectangleLinkPreviewView)
        case .squareImage:
            squareLinkPreviewView.isHidden = false
            rectangleLinkPreviewView.isHidden = true
            noImageLinkPreviewView.isHidden = true
            squareLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title, description: linkPreviewData.description, previewImage: nil)
            contentView.addArrangedSubview(squareLinkPreviewView)
        case .noImage:
            rectangleLinkPreviewView.isHidden = true
            noImageLinkPreviewView.isHidden = false
            squareLinkPreviewView.isHidden = true
            noImageLinkPreviewView.configure(url: linkPreviewData.url, title: linkPreviewData.title)
            contentView.addArrangedSubview(noImageLinkPreviewView)
        }
    }

    public func showPlaceholderImage() {
        switch configuration {
        case .rectangleImage:
            rectangleLinkPreviewView.showPlaceholderImage()
        case .squareImage:
            squareLinkPreviewView.showPlaceholderImage()
        case .noImage:
            break
        }
    }

    public func show(image: UIImage) {
        switch configuration {
        case .rectangleImage:
            rectangleLinkPreviewView.show(image: image)
        case .squareImage:
            squareLinkPreviewView.show(image: image)
        case .noImage:
            break
        }
        // Loading cancellable is no longer needed
        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }

    public func hideProgressView() {
        switch configuration {
        case .rectangleImage:
            rectangleLinkPreviewView.hideProgressView()
        case .squareImage:
            squareLinkPreviewView.hideProgressView()
        case .noImage:
            break
        }
    }

    public func showProgressView() {
        switch configuration {
        case .rectangleImage:
            rectangleLinkPreviewView.showProgressView()
        case .squareImage:
            squareLinkPreviewView.showProgressView()
        case .noImage:
            break
        }
    }

    public func setProgress(_ progress: Float, animated: Bool) {
        switch configuration {
        case .rectangleImage:
            rectangleLinkPreviewView.setProgress(progress, animated: animated)
        case .squareImage:
            squareLinkPreviewView.setProgress(progress, animated: animated)
        case .noImage:
            break
        }
    }
}
