//
//  HalloApp
//
//  Created by Tony Jiang on 6/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Core
import UIKit

protocol ChatMediaSliderDelegate: AnyObject {
    func chatMediaSlider(_ view: ChatMediaSlider, currentPage: Int)
}

class ChatMediaSlider: UIView, UIScrollViewDelegate {
    weak var delegate: ChatMediaSliderDelegate?
    public var currentPage: Int = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private var imageViewList: [Int: UIImageView] = [:]
    private var imageViewOverlayList: [Int: UIImageView] = [:]
    
    func configure(with sliderMedia: [SliderMedia], size: CGSize, currentPage: Int = 0) {

        for (index, media) in sliderMedia.enumerated() {

            
            let imageView = ZoomableImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                      y: 0,
                                                      width: size.width,
                                                      height: size.height))
            
            imageView.image = media.image
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true

            self.imageViewList[media.order] = imageView

            scrollView.addSubview(self.imageViewList[media.order]!)
            
            if media.type == .image && media.image == nil {
                let photoButtonOverlay = UIImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                          y: 0,
                                                          width: size.width,
                                                          height: size.height))

                let targetWidth: CGFloat = 30.0
                photoButtonOverlay.image = self.resizeImage(image: UIImage(systemName: "photo.fill")!, newWidth: targetWidth)?.withRenderingMode(.alwaysTemplate)

                photoButtonOverlay.tintColor = UIColor.systemGray6
                photoButtonOverlay.contentMode = .center
                photoButtonOverlay.alpha = 0.8
                
                self.imageViewOverlayList[media.order] = photoButtonOverlay
                scrollView.addSubview(self.imageViewOverlayList[media.order]!)
            }
            
            if media.type == .video {
                let playButtonOverlay = UIImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                          y: 0,
                                                          width: size.width,
                                                          height: size.height))

                let targetWidth = size.width * 0.20
                playButtonOverlay.image = self.resizeImage(image: UIImage(systemName: "play.fill")!, newWidth: targetWidth)?.withRenderingMode(.alwaysTemplate)
                
                playButtonOverlay.tintColor = UIColor.systemGray6
                playButtonOverlay.contentMode = .center
                playButtonOverlay.alpha = 0.8
                
                scrollView.addSubview(playButtonOverlay)
            }
            
        }
        
        // Set the scrollView contentSize
        var contentSizeWidth = size.width * CGFloat(sliderMedia.count)
        if sliderMedia.count == 1 {
            contentSizeWidth -= 1 // disable extra scrolling for single image
        }
        scrollView.contentSize = CGSize(width: contentSizeWidth, height: size.height)
        
        if sliderMedia.count > 1 {
            self.addSubview(self.pageControl)
            self.pageControl.numberOfPages = sliderMedia.count
            self.pageControl.currentPage = currentPage
            self.pageControl.currentPageIndicatorTintColor = UIColor(named: "LavaOrange")
            self.pageControl.pageIndicatorTintColor = UIColor.systemGray.withAlphaComponent(0.8)
            self.pageControl.addTarget(self, action: #selector(self.pageControlTap), for: .valueChanged)
            
            self.pageControl.translatesAutoresizingMaskIntoConstraints = false
            let leading = NSLayoutConstraint(item: self.pageControl, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leading, multiplier: 1, constant: 0)
            let trailing = NSLayoutConstraint(item: self.pageControl, attribute: .trailing, relatedBy: .equal, toItem: self, attribute: .trailing, multiplier: 1, constant: 0)
            let bottom = NSLayoutConstraint(item: self.pageControl, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: 0)
            self.addConstraints([leading, trailing, bottom])
        }
        
        DispatchQueue.main.async {
            self.scrollToIndex(index: self.pageControl.currentPage, animated: false)
        }
        
    }
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        guard let imageView = self.imageViewList[sliderMedia.order] else { return }
        imageView.image = sliderMedia.image
        
        guard let imageViewOverlay = self.imageViewOverlayList[sliderMedia.order] else { return }
        imageViewOverlay.removeFromSuperview()
    }
    
    func reset() {
        self.currentPage = 0
        self.pageControl.numberOfPages = 0
        self.pageControl.currentPage = 0
        self.pageControl.removeFromSuperview()
        self.scrollView.contentSize = CGSize(width: 0, height: 0)
        self.scrollView.subviews.forEach({ $0.removeFromSuperview() })
    }
    
    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.frame = self.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
        return view
    }()
    
    private func setupView() {
        self.addSubview(self.scrollView)
    }
    
    // MARK: actions
    
    @IBAction func pageControlTap(_ sender: Any?) {
        guard let pageControl: UIPageControl = sender as? UIPageControl else {
            return
        }
        
        scrollToIndex(index: pageControl.currentPage, animated: true)
        self.delegate?.chatMediaSlider(self, currentPage: pageControl.currentPage)
    }
    
    private func scrollToIndex(index: Int, animated: Bool) {
        let pageWidth: CGFloat = self.scrollView.frame.width
        let slideToX: CGFloat = CGFloat(index) * pageWidth
        
        self.scrollView.scrollRectToVisible(CGRect(x: slideToX, y:0, width:pageWidth, height: self.scrollView.frame.height), animated: animated)
    }
    
    // MARK: scrollview delegates
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.frame.width > 0 else { return }
        let pageWidth = scrollView.frame.width
        let viewCenterXInScrollViewCoordinates = scrollView.convert(self.center, from: self).x
        let pageIndex = Int(viewCenterXInScrollViewCoordinates / pageWidth)
        self.pageControl.currentPage = pageIndex
        self.currentPage = pageIndex
        self.delegate?.chatMediaSlider(self, currentPage: pageControl.currentPage)
    }
    
    // MARK: helpers
    
    func resizeImage(image: UIImage, newWidth: CGFloat) -> UIImage? {

        let scale = newWidth / image.size.width
        let newHeight = image.size.height * scale
        UIGraphicsBeginImageContext(CGSize(width: newWidth, height: newHeight))
        image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
}

struct SliderMedia {
    let image: UIImage?
    let type: ChatMessageMediaType
    let order: Int

    init(image: UIImage?, type: ChatMessageMediaType, order: Int) {
        self.image = image
        self.type = type
        self.order = order
    }
}
