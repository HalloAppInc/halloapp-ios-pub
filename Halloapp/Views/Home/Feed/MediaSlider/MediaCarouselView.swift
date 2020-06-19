
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import UIKit

class MediaCarouselView: UIView, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    // MARK: Public Config
    var alwaysScaleToFitContent: Bool = false
    var isZoomEnabled: Bool = true

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

    static private let cellSpacing: CGFloat = 20

    static private let cellReuseIdentifierImage = "MediaCarouselCellImage"
    static private let cellReuseIdentifierVideo = "MediaCarouselCellVideo"

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = MediaCarouselView.cellSpacing
        layout.minimumInteritemSpacing = MediaCarouselView.cellSpacing // This is actually necessary for the collection view to have correct content size.
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0.5*MediaCarouselView.cellSpacing, bottom: 0, right: 0.5*MediaCarouselView.cellSpacing)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(MediaCarouselImageCollectionViewCell.self, forCellWithReuseIdentifier: MediaCarouselView.cellReuseIdentifierImage)
        collectionView.register(MediaCarouselVideoCollectionViewCell.self, forCellWithReuseIdentifier: MediaCarouselView.cellReuseIdentifierVideo)
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var pageControl: UIPageControl? = nil
    private static let pageControlSpacingTop: CGFloat = -4
    private static let pageControlSpacingBottom: CGFloat = -12
    private static let pageControlAreaHeight: CGFloat = {
        let pageControl = UIPageControl()
        pageControl.numberOfPages = 2
        pageControl.sizeToFit()
        return MediaCarouselView.pageControlSpacingTop + pageControl.frame.height + MediaCarouselView.pageControlSpacingBottom
    }()

    private var dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>?

    convenience init(feedDataItem: FeedDataItem) {
        self.init(media: feedDataItem.media, feedDataItem: feedDataItem)
    }

    convenience init(media: [FeedMedia]) {
        self.init(media: media, feedDataItem: nil)
    }

    required init(media: [FeedMedia], feedDataItem: FeedDataItem?) {
        self.media = media
        self.feedDataItem = feedDataItem
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(feedDataItem)")
    }

    private func commonInit() {
        self.clipsToBounds = true
        self.isUserInteractionEnabled = true

        self.addSubview(self.collectionView)

        self.collectionView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -0.5*Self.cellSpacing).isActive = true
        self.collectionView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.collectionView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0.5*Self.cellSpacing).isActive = true

        if self.media.count > 1 {
            let pageControl = UIPageControl()
            pageControl.pageIndicatorTintColor = UIColor(named: "Tint")?.withAlphaComponent(0.2)
            pageControl.currentPageIndicatorTintColor = UIColor(named: "LavaOrange")
            pageControl.translatesAutoresizingMaskIntoConstraints = false
            pageControl.numberOfPages = self.media.count
            pageControl.addTarget(self, action: #selector(pageControlAction), for: .valueChanged)
            pageControl.sizeToFit()
            addSubview(pageControl)

            pageControl.topAnchor.constraint(equalTo: self.collectionView.bottomAnchor, constant: Self.pageControlSpacingTop).isActive = true
            pageControl.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -Self.pageControlSpacingBottom).isActive = true
            pageControl.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true

            self.pageControl = pageControl
        } else {
            self.collectionView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
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
                cell.scaleContentToFit = self.alwaysScaleToFitContent
                cell.isZoomEnabled = self.isZoomEnabled
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

    func dismantle() {
        let indexPaths = collectionView.indexPathsForVisibleItems
        for indexPath in indexPaths {
            if let mediaCell = collectionView.cellForItem(at: indexPath) as? MediaCarouselCollectionViewCell {
                mediaCell.dismantle()
            }
        }
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
        var size = self.bounds.size
        if self.pageControl != nil && size.height > Self.pageControlAreaHeight {
            size.height -= Self.pageControlAreaHeight
        }
        return size
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
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

    func configure(with media: FeedMedia) {

    }

    func dismantle() {

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
        imageView.cornerRadius = 10
        self.contentView.addSubview(imageView)
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        imageView.isZoomEnabled = isZoomEnabled
        if media.isMediaAvailable {
            show(image: media.image!)
        } else if imageLoadingCancellable == nil {
            showPlaceholderImage()
            imageLoadingCancellable = media.imageDidBecomeAvailable.sink { (image) in
                self.show(image: image)
            }
        }
    }

    override func dismantle() {
        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
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
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        avPlayerViewController.videoGravity = media.size.width > media.size.height || scaleContentToFit ? .resizeAspect : .resizeAspectFill

        if media.isMediaAvailable {
            showPlayer(forVideoURL: media.fileURL!)
        } else {
            if videoLoadingCancellable == nil {
                showPlaceholderImage()
                videoLoadingCancellable = media.videoDidBecomeAvailable.sink { (videoURL) in
                    self.showPlayer(forVideoURL: videoURL)
                }
            }
        }
    }

    override func dismantle() {
        videoLoadingCancellable?.cancel()
        videoLoadingCancellable = nil

        videoPlaybackCancellable?.cancel()
        videoPlaybackCancellable = nil

        if let avPlayer = avPlayerViewController.player {
            avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.rate), context: &avPlayerContext)
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
        videoPlaybackCancellable = Self.videoDidStartPlaying.sink { (videoURL) in
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

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &avPlayerContext else {
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
    }

}
