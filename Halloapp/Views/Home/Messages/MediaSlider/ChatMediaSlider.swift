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
    
    private var imageViewList: [Int: UIImageView] = [:]
    private var imageViewOverlayList: [Int: UIImageView] = [:]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    func configure(with sliderMedia: [SliderMedia], size: CGSize, currentPage: Int = 0) {
        for (index, media) in sliderMedia.enumerated() {

            let imageView = ZoomableImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                      y: 0,
                                                      width: size.width,
                                                      height: size.height))
            
            imageView.image = media.image
            imageView.contentMode = .scaleAspectFit
            
            imageView.roundCorner(20)
            
            imageView.clipsToBounds = true

            imageViewList[media.order] = imageView

            scrollView.addSubview(imageViewList[media.order]!)
            
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
                
                imageViewOverlayList[media.order] = photoButtonOverlay
                scrollView.addSubview(imageViewOverlayList[media.order]!)
            }
            
            if media.type == .video {
                let playButtonOverlay = UIImageView(frame: CGRect(x: size.width * CGFloat(index),
                                                          y: 0,
                                                          width: size.width,
                                                          height: size.height))

                let targetWidth = size.width * 0.20
                playButtonOverlay.image = resizeImage(image: UIImage(systemName: "play.fill")!, newWidth: targetWidth)?.withRenderingMode(.alwaysTemplate)
                
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
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        guard let imageView = imageViewList[sliderMedia.order] else { return }
        imageView.image = sliderMedia.image
        
        guard let imageViewOverlay = imageViewOverlayList[sliderMedia.order] else { return }
        imageViewOverlay.removeFromSuperview()
    }
    
    func reset() {
        currentPage = 0
        pageControl.isHidden = true
        pageControl.numberOfPages = 0
        pageControl.currentPage = 0
        
        scrollView.contentSize = CGSize(width: 0, height: 0)
        scrollView.subviews.forEach({ $0.removeFromSuperview() })
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
    
    func resizeImage(image: UIImage, newWidth: CGFloat) -> UIImage? {
        let scale = newWidth / image.size.width
        let newHeight = image.size.height * scale
        UIGraphicsBeginImageContext(CGSize(width: newWidth, height: newHeight))
        image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
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

fileprivate extension UIImageView
{
    func roundCorner(_ radius: CGFloat) {
        guard let image = image else { return }
        let boundsScale = bounds.size.width / bounds.size.height
        let imageScale = image.size.width / image.size.height

        var rect: CGRect = bounds

        if boundsScale > imageScale {
            rect.size.width =  rect.size.height * imageScale
            rect.origin.x = (bounds.size.width - rect.size.width) / 2
        } else {
            rect.size.height = rect.size.width / imageScale
            rect.origin.y = (bounds.size.height - rect.size.height) / 2
        }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }
}
