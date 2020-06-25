
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import UIKit

struct MediaCarouselViewConfiguration {
    var isPagingEnabled = true
    var isZoomEnabled = true
    var alwaysScaleToFitContent = false
    var cellSpacing: CGFloat = 20
    var cornerRadius: CGFloat = 10

    static var `default`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration() }
    }
}

fileprivate struct LayoutConstants {
    static let pageControlSpacingTop: CGFloat = -4
    static let pageControlSpacingBottom: CGFloat = -12
}

class MediaCarouselView: UIView, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    private let configuration: MediaCarouselViewConfiguration

    private enum MediaSliderSection: Int {
        case main = 0
    }

    private let feedDataItem: FeedDataItem?

    private let media: [FeedMedia]

    private var currentIndex = 0 {
        didSet {
            self.feedDataItem?.currentMediaIndex = currentIndex
            self.pageControl?.currentPage = currentIndex

            if oldValue != currentIndex {
                if let videoCell = collectionView.cellForItem(at: IndexPath(row: oldValue, section: MediaSliderSection.main.rawValue)) as? MediaCarouselVideoCollectionViewCell {
                    videoCell.stopPlayback()
                }
            }
        }
    }

    private var mediaIndexToScrollToInLayoutSubviews: Int? = nil

    private func setCurrentIndex(_ index: Int, animated: Bool) {
        let pageWidth = self.collectionView.frame.width
        var contentOffset = self.collectionView.contentOffset
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            contentOffset.x = CGFloat(self.media.count - 1 - index) * pageWidth
        } else {
            contentOffset.x = CGFloat(index) * pageWidth
        }
        self.collectionView.setContentOffset(contentOffset, animated: animated)
    }

    class func preferredHeight(for media: [FeedMedia], width: CGFloat) -> CGFloat {
        guard !media.isEmpty else { return 0 }

        let tallestItem = media.max { return $0.size.height < $1.size.height }
        let tallestItemAspectRatio = tallestItem!.size.height / tallestItem!.size.width
        let maxAllowedAspectRatio: CGFloat = 5/4
        var height = (width * min(maxAllowedAspectRatio, tallestItemAspectRatio)).rounded()

        if media.count > 1 {
            height += MediaCarouselView.pageControlAreaHeight
        }
        return height
    }

    static private let cellReuseIdentifierImage = "MediaCarouselCellImage"
    static private let cellReuseIdentifierVideo = "MediaCarouselCellVideo"

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = configuration.cellSpacing
        layout.minimumInteritemSpacing = configuration.cellSpacing // This is actually necessary for the collection view to have correct content size.
        layout.scrollDirection = .horizontal
        if configuration.isPagingEnabled {
            layout.sectionInset = UIEdgeInsets(top: 0, left: 0.5*configuration.cellSpacing, bottom: 0, right: 0.5*configuration.cellSpacing)
        } else {
            layout.sectionInset = .zero
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(MediaCarouselImageCollectionViewCell.self, forCellWithReuseIdentifier: MediaCarouselView.cellReuseIdentifierImage)
        collectionView.register(MediaCarouselVideoCollectionViewCell.self, forCellWithReuseIdentifier: MediaCarouselView.cellReuseIdentifierVideo)
        collectionView.isPagingEnabled = configuration.isPagingEnabled
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var pageControl: UIPageControl? = nil
    private static let pageControlAreaHeight: CGFloat = {
        let pageControl = UIPageControl()
        pageControl.numberOfPages = 2
        pageControl.sizeToFit()
        return LayoutConstants.pageControlSpacingTop + pageControl.frame.height + LayoutConstants.pageControlSpacingBottom
    }()

    private var dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>?

    convenience init(feedDataItem: FeedDataItem, configuration: MediaCarouselViewConfiguration = MediaCarouselViewConfiguration.default) {
        self.init(media: feedDataItem.media, feedDataItem: feedDataItem, configuration: configuration)
    }

    convenience init(media: [FeedMedia], configuration: MediaCarouselViewConfiguration = MediaCarouselViewConfiguration.default) {
        self.init(media: media, feedDataItem: nil, configuration: configuration)
    }

    required init(media: [FeedMedia], feedDataItem: FeedDataItem?, configuration: MediaCarouselViewConfiguration) {
        self.media = media
        self.feedDataItem = feedDataItem
        self.configuration = configuration
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(feedDataItem)")
    }

    private func commonInit() {
        self.clipsToBounds = true
        self.isUserInteractionEnabled = true
        self.layoutMargins = .zero

        self.addSubview(self.collectionView)

        if configuration.isPagingEnabled {
            self.collectionView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -0.5*configuration.cellSpacing).isActive = true
            self.collectionView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0.5*configuration.cellSpacing).isActive = true
        } else {
            self.collectionView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
            self.collectionView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        }
        self.collectionView.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true

        if self.media.count > 1 && configuration.isPagingEnabled {
            let pageControl = UIPageControl()
            pageControl.pageIndicatorTintColor = UIColor(named: "Tint")?.withAlphaComponent(0.2)
            pageControl.currentPageIndicatorTintColor = UIColor(named: "LavaOrange")
            pageControl.translatesAutoresizingMaskIntoConstraints = false
            pageControl.numberOfPages = self.media.count
            pageControl.addTarget(self, action: #selector(pageControlAction), for: .valueChanged)
            pageControl.sizeToFit()
            addSubview(pageControl)

            pageControl.topAnchor.constraint(equalTo: self.collectionView.bottomAnchor, constant: LayoutConstants.pageControlSpacingTop).isActive = true
            pageControl.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor, constant: -LayoutConstants.pageControlSpacingBottom).isActive = true
            pageControl.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true

            self.pageControl = pageControl
        } else {
            self.collectionView.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
        }
        self.collectionView.delegate = self

        let dataSource = UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>(collectionView: self.collectionView) { [weak self] collectionView, indexPath, feedMedia in
            guard let self = self else { return nil }

            let reuseIdentifier: String = {
                switch feedMedia.type {
                case .image: return Self.cellReuseIdentifierImage
                case .video: return Self.cellReuseIdentifierVideo
                }
            }()
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as? MediaCarouselCollectionViewCell {
                cell.scaleContentToFit = self.configuration.alwaysScaleToFitContent
                cell.isZoomEnabled = self.configuration.isZoomEnabled
                cell.cornerRadius = self.configuration.cornerRadius
                cell.configure(with: feedMedia)
                return cell
            }
            return MediaCarouselCollectionViewCell()
        }
        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
        snapshot.appendSections([.main])
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            snapshot.appendItems(self.media.reversed())
        } else {
            snapshot.appendItems(self.media)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        self.dataSource = dataSource
    }

    @objc(pageControlAction)
    private func pageControlAction() {
        self.setCurrentIndex(self.pageControl?.currentPage ?? 0, animated: true)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil && feedDataItem?.currentMediaIndex != nil {
            // Delay scrolling until view has a non-zero size.
            mediaIndexToScrollToInLayoutSubviews = (feedDataItem?.currentMediaIndex)!
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if self.bounds != .zero && mediaIndexToScrollToInLayoutSubviews != nil {
            setCurrentIndex(mediaIndexToScrollToInLayoutSubviews!, animated: false)
            mediaIndexToScrollToInLayoutSubviews = nil
        }
    }

    func stopPlayback() {
        for cell in collectionView.visibleCells {
            if let videoCell = cell as? MediaCarouselVideoCollectionViewCell {
                videoCell.stopPlayback()
            }
        }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if configuration.isPagingEnabled {
            var size = self.bounds.size
            if self.pageControl != nil && size.height > Self.pageControlAreaHeight {
                size.height -= Self.pageControlAreaHeight
            }
            return size
        } else {
            guard let mediaItem = dataSource?.itemIdentifier(for: indexPath),
                  let collectionViewFlowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
                return .zero
            }
            var cellHeight = collectionView.frame.height - collectionView.contentInset.top - collectionView.contentInset.bottom
            cellHeight -= (collectionViewFlowLayout.sectionInset.top + collectionViewFlowLayout.sectionInset.bottom)

            let cellWidth = ceil(cellHeight * (mediaItem.size.width / mediaItem.size.height))
            return CGSize(width: cellWidth, height: cellHeight)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard configuration.isPagingEnabled else { return }

        let pageWidth = scrollView.frame.width
        let viewCenterXInScrollViewCoordinates = scrollView.convert(self.center, from: self).x
        let pageIndex = Int(viewCenterXInScrollViewCoordinates / pageWidth)
        if scrollView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            self.currentIndex = self.media.count - 1 - pageIndex
        } else {
            self.currentIndex = pageIndex
        }
    }

}

fileprivate class MediaCarouselCollectionViewCell: UICollectionViewCell {
    var scaleContentToFit: Bool = false
    var isZoomEnabled: Bool = true
    var cornerRadius: CGFloat = 10

    func configure(with media: FeedMedia) {

    }
}

fileprivate class MediaCarouselImageCollectionViewCell: MediaCarouselCollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var placeholderImageView: UIImageView!
    private var imageView: ZoomableImageView!
    private var imageLoadingCancellable: AnyCancellable?

    override var cornerRadius: CGFloat {
        didSet {
            if oldValue != cornerRadius {
                imageView.cornerRadius = cornerRadius
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }

    private func commonInit() {
        placeholderImageView = UIImageView(frame: self.contentView.bounds)
        placeholderImageView.contentMode = .center
        placeholderImageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "photo")
        placeholderImageView.tintColor = .systemGray
        self.contentView.addSubview(placeholderImageView)

        imageView = ZoomableImageView(frame: self.contentView.bounds)
        imageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        imageView.cornerRadius = self.cornerRadius
        self.contentView.addSubview(imageView)
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        imageView.isZoomEnabled = isZoomEnabled
        if media.isMediaAvailable {
            show(image: media.image!)
        } else if imageLoadingCancellable == nil {
            showPlaceholderImage()
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { [weak self] (image) in
                guard let self = self else { return }
                self.show(image: image)
            }
        }
    }

    private func showPlaceholderImage() {
        placeholderImageView.isHidden = false
        imageView.isHidden = true
    }

    private func show(image: UIImage) {
        placeholderImageView.isHidden = true
        imageView.isHidden = false
        imageView.image = image
        imageView.contentMode = image.size.width > image.size.height || scaleContentToFit ? .scaleAspectFit : .scaleAspectFill

        // Loading cancellable is no longer needed
        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }
}

fileprivate class MediaCarouselVideoCollectionViewCell: MediaCarouselCollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var placeholderImageView: UIImageView!
    private var videoURL: URL?
    private var avPlayerViewController: AVPlayerViewController!
    private var avPlayerContext = 0
    private var avPlayerVCContext = 0

    private var videoLoadingCancellable: AnyCancellable?
    private var videoPlaybackCancellable: AnyCancellable?

    private static let videoDidStartPlaying = PassthroughSubject<URL, Never>()

    override func prepareForReuse() {
        super.prepareForReuse()

        videoURL = nil

        videoLoadingCancellable?.cancel()
        videoLoadingCancellable = nil

        videoPlaybackCancellable?.cancel()
        videoPlaybackCancellable = nil

        if avPlayerViewController.player != nil {
            avPlayerViewController.player?.removeObserver(self, forKeyPath: #keyPath(AVPlayer.rate), context: &avPlayerContext)
            avPlayerViewController.player = nil
        }

        avPlayerViewController.view.frame = self.bounds
        avPlayerViewController.view.layer.mask = nil
    }

    private func commonInit() {
        placeholderImageView = UIImageView(frame: self.contentView.bounds)
        placeholderImageView.contentMode = .center
        placeholderImageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "video")
        placeholderImageView.tintColor = .systemGray
        self.contentView.addSubview(placeholderImageView)

        avPlayerViewController = AVPlayerViewController()
        avPlayerViewController.view.frame = self.contentView.bounds
        avPlayerViewController.view.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        avPlayerViewController.view.isHidden = true
        avPlayerViewController.view.backgroundColor = .clear
        self.contentView.addSubview(avPlayerViewController.view)

        avPlayerViewController.addObserver(self, forKeyPath: #keyPath(AVPlayerViewController.videoBounds), options: [ ], context:&avPlayerVCContext)
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        avPlayerViewController.videoGravity = media.size.width > media.size.height || scaleContentToFit ? .resizeAspect : .resizeAspectFill

        if media.isMediaAvailable {
            showPlayer(forVideoURL: media.fileURL!)
        } else {
            if videoLoadingCancellable == nil {
                showPlaceholderImage()
                videoLoadingCancellable = media.videoDidBecomeAvailable.sink { [weak self] (videoURL) in
                    guard let self = self else { return }
                    self.showPlayer(forVideoURL: videoURL)
                }
            }
        }
    }

    private func showPlayer(forVideoURL videoURL: URL) {
        assert(avPlayerViewController.player == nil)
        assert(videoPlaybackCancellable == nil)

        self.videoURL = videoURL

        let avPlayer = AVPlayer(url: videoURL)
        avPlayerViewController.player = avPlayer
        avPlayerViewController.view.isHidden = false

        placeholderImageView.isHidden = true

        // Monitor when this cell's video starts playing and send out broadcast when it does.
        avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.rate), options: [ .new ], context: &avPlayerContext)

        // Cancel playback when other video starts playing.
        videoPlaybackCancellable = Self.videoDidStartPlaying.sink { [weak self] (videoURL) in
            guard let self = self else { return }
            if self.videoURL != videoURL {
                self.stopPlayback()
            }
        }

        // Loading cancellable is no longer needed
        videoLoadingCancellable?.cancel()
        videoLoadingCancellable = nil
    }

    private func showPlaceholderImage() {
        avPlayerViewController.view.isHidden = true
        placeholderImageView.isHidden = false
    }

    func stopPlayback() {
        avPlayerViewController.player?.pause()
    }

    private func updatePlayerViewFrame() {
        // Video takes entire cell content.
        if avPlayerViewController.videoBounds.size == .zero || avPlayerViewController.videoGravity == .resizeAspectFill {
            setPlayerView(frame: self.contentView.bounds)
            return
        }

        let videoSize = avPlayerViewController.videoBounds.integral.size
        let cellAspectRatio = self.contentView.bounds.width /  self.contentView.bounds.height
        let videoAspectRatio = videoSize.width / videoSize.height

        // Stop updating frame if desired size was reached.
        guard abs(cellAspectRatio - videoAspectRatio) > 0.01 else {
            return
        }

        var rect = self.contentView.bounds
        if cellAspectRatio > videoAspectRatio {
            rect.size.width = ceil(rect.height * videoAspectRatio)
            rect.origin.x = (self.contentView.bounds.width - rect.width) / 2
        } else {
            rect.size.height = ceil(rect.width / videoAspectRatio)
            rect.origin.y = (self.contentView.bounds.height - rect.height) / 2
        }
        setPlayerView(frame: rect)
    }

    private func setPlayerView(frame: CGRect) {
        avPlayerViewController.view.frame = frame

        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: avPlayerViewController.view.bounds, cornerRadius: self.cornerRadius).cgPath
        avPlayerViewController.view.layer.mask = maskLayer
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &avPlayerContext || context == &avPlayerVCContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        if keyPath == #keyPath(AVPlayer.rate) {
            if let rate = change?[.newKey] as? NSNumber {
                if rate.doubleValue == 1 {
                    Self.videoDidStartPlaying.send(videoURL!)
                }
            }
        }

        if keyPath == #keyPath(AVPlayerViewController.videoBounds) {
            updatePlayerViewFrame()
        }
    }

}
