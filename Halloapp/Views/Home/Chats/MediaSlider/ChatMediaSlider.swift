//
//  HalloApp
//
//  Created by Tony Jiang on 6/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import Core
import CoreCommon
import UIKit

protocol ChatMediaSliderDelegate: AnyObject {
    func chatMediaSlider(_ view: ChatMediaSlider, currentPage: Int)
}

class ChatMediaSlider: UIView, UIScrollViewDelegate, MediaListAnimatorDelegate {
    weak var delegate: ChatMediaSliderDelegate?
    public var currentPage: Int = 0
    
    private var msgID: String?
    private var imageViewDict: [Int: UIImageView] = [:]
    private var imageViewButtonDict: [Int: UIButton] = [:]
    private var downloadProgressIndicatorDict: [String: CircularProgressView] = [:]
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    func configure(with sliderMedia: [SliderMedia], size: CGSize, currentPage: Int = 0, msgID: String? = nil) {
        self.msgID = msgID
        var shouldListenForProgress: Bool = false
        for (index, media) in sliderMedia.enumerated() {

            let imageView = ZoomableImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                      y: 0,
                                                      width: size.width,
                                                      height: size.height))
            
            imageView.image = media.image
            imageView.contentMode = .scaleAspectFit
            imageView.roundCorner(20)
            imageView.clipsToBounds = true
            scrollView.addSubview(imageView)
            imageViewDict[media.order] = imageView
            
            if media.type == .video || (media.type == .image && imageView.image == nil) {
                let iconConfig = UIImage.SymbolConfiguration(pointSize: 30)
                let iconColor = UIColor.primaryWhiteBlack
                let iconName = (media.type == .image) ? "photo.fill" : "play.fill"
                let icon = UIImage(systemName: iconName, withConfiguration: iconConfig)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

                let buttonSize: CGFloat = 80
                let button:UIButton = UIButton(frame: CGRect(x: size.width * CGFloat(index), y: 0, width: size.width, height: size.height))
                button.setImage(icon, for: .normal)

                button.translatesAutoresizingMaskIntoConstraints = false
                button.layer.cornerRadius = buttonSize / 2
                button.clipsToBounds = true

                button.isUserInteractionEnabled = false

                let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
                let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
                blurredEffectView.isUserInteractionEnabled = false
                blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

                button.insertSubview(blurredEffectView, at: 0)
                blurredEffectView.constrain(to: button)

                if let imageView = button.imageView{
                    button.bringSubviewToFront(imageView)
                }

                imageViewButtonDict[media.order] = button
                scrollView.addSubview(button)
                
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: buttonSize),
                    button.heightAnchor.constraint(equalToConstant: buttonSize),
                    button.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
                    button.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
                ])
     
                if imageView.image == nil {
                    shouldListenForProgress = true
                    let progressView = createProgressView()
                    downloadProgressIndicatorDict[media.id] = progressView
                    
                    scrollView.addSubview(progressView)
                    progressView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor).isActive = true
                    progressView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor).isActive = true
                }
            }
        }
        
        if shouldListenForProgress {
            listenForProgress()
        }
                
        // Set the scrollView contentSize
        var contentSizeWidth = size.width * CGFloat(sliderMedia.count)
        if sliderMedia.count == 1 {
            contentSizeWidth -= 1 // disable extra scrolling for single image
        }
        scrollView.contentSize = CGSize(width: contentSizeWidth, height: 1)
        
        if sliderMedia.count > 1 {
            pageControl.numberOfPages = sliderMedia.count
            pageControl.currentPage = currentPage
            pageControl.isHidden = false
        }
        
        mainView.constrain(to: self) // constrain again since subviews were added to scrollview
        
        DispatchQueue.main.async {
            self.scrollToIndex(index: self.pageControl.currentPage, animated: false)
        }
        
    }
    
    private func createProgressView() -> CircularProgressView {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray5
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        progressView.heightAnchor.constraint(equalTo: progressView.widthAnchor, multiplier: 1).isActive = true
        progressView.setProgress(0.01, animated: true)
        return progressView
    }
    
    func listenForProgress() {
        FeedDownloadManager.downloadProgress.receive(on: DispatchQueue.main).sink { [weak self] (id, progress) in
            guard let self = self else { return }
            guard let progressIndicator = self.downloadProgressIndicatorDict[id] else { return }

            progressIndicator.setProgress(progress, animated: true)
            if progress >= 1 {
                progressIndicator.isHidden = true
            }
        }.store(in: &cancellableSet)
    }
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        guard let imageView = imageViewDict[sliderMedia.order] else { return }
        imageView.image = sliderMedia.image
        
        imageView.contentMode = .scaleAspectFit
        imageView.roundCorner(20)
        imageView.clipsToBounds = true
        
        guard let imageViewButton = imageViewButtonDict[sliderMedia.order] else { return }
        if sliderMedia.type == .image {
            imageViewButton.removeFromSuperview()
        }
    }
    
    func reset() {
        currentPage = 0
        pageControl.isHidden = true
        pageControl.numberOfPages = 0
        pageControl.currentPage = 0
        
        scrollView.contentSize = CGSize(width: 0, height: 0)
        scrollView.subviews.forEach({ $0.removeFromSuperview() })
        
        cancellableSet.forEach { $0.cancel() }
        cancellableSet.removeAll()
    }
    
    private func setup() {
        addSubview(mainView)
        mainView.constrain(to: self)
    }
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ scrollViewRow, pageControl ])
        view.axis = .vertical
        
        view.translatesAutoresizingMaskIntoConstraints = false
        pageControl.heightAnchor.constraint(equalToConstant: 25).isActive = true
        return view
    }()
    
    private lazy var scrollViewRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ scrollView ])
        view.axis = .horizontal
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.delegate = self
        return view
    }()
    
    private lazy var pageControl: UIPageControl = {
        let view = UIPageControl()
        view.numberOfPages = 0
        view.currentPage = 0

        view.pageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.2)
        view.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.7)
        
        view.addTarget(self, action: #selector(pageControlTap), for: .valueChanged)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    // MARK: Actions
    
    @IBAction func pageControlTap(_ sender: Any?) {
        guard let pageControl: UIPageControl = sender as? UIPageControl else {
            return
        }
        
        scrollToIndex(index: pageControl.currentPage, animated: true)
        delegate?.chatMediaSlider(self, currentPage: pageControl.currentPage)
    }
    
    // MARK: Helpers
    
    private func scrollToIndex(index: Int, animated: Bool) {
        let pageWidth: CGFloat = scrollView.frame.width
        let slideToX: CGFloat = CGFloat(index) * pageWidth
        
        scrollView.scrollRectToVisible(CGRect(x: slideToX, y:0, width:pageWidth, height: scrollView.frame.height), animated: animated)
    }
        
    // MARK: Scrollview Delegates
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.frame.width > 0 else { return }
        let pageWidth = scrollView.frame.width
        let viewCenterXInScrollViewCoordinates = scrollView.convert(center, from: self).x
        let pageIndex = Int(viewCenterXInScrollViewCoordinates / pageWidth)
        pageControl.currentPage = pageIndex
        currentPage = pageIndex
        delegate?.chatMediaSlider(self, currentPage: pageControl.currentPage)
    }

    // MARK: MediaExplorerTransitionDelegate

    var transitionViewContentMode: UIView.ContentMode {
        .scaleAspectFit
    }

    func getTransitionView(at index: MediaIndex) -> UIView? {
        // Handles the case when the index is -1
        if index.index == 0 && imageViewDict.count == 1 && imageViewDict.keys.first == -1 {
            return imageViewDict[-1]
        } else {
            return imageViewDict[index.index]
        }
    }

    func scrollToTransitionView(at index: MediaIndex) {
        scrollToIndex(index: index.index, animated: false)
    }
}

struct SliderMedia {
    let id: String
    let image: UIImage?
    let type: CommonMediaType
    let order: Int

    init(id: String, image: UIImage?, type: CommonMediaType, order: Int) {
        self.id = id
        self.image = image
        self.type = type
        self.order = order
    }
}
