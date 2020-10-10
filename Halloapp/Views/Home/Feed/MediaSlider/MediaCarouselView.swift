
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Combine
import Core
import UIKit

protocol MediaCarouselViewDelegate: AnyObject {
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int)
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int)
}

struct MediaCarouselViewConfiguration {
    var isPagingEnabled = true
    var isZoomEnabled = true
    var showVideoPlaybackControls = true
    var disablePlayback = false
    var alwaysScaleToFitContent = false
    var cellSpacing: CGFloat = 20
    var cornerRadius: CGFloat = 15
    var gutterWidth: CGFloat = 0
    var downloadProgressViewSize: CGFloat = 80 // Diameter of the circular progress view. Set to 0 to hide progress view.

    static var `default`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration() }
    }

    static var minimal: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration(isPagingEnabled: false, isZoomEnabled: false, showVideoPlaybackControls: false, cellSpacing: 10, cornerRadius: 5) }
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

    private var media: [FeedMedia]
    public var shouldAutoPlay = false

    private var collectionBottomConstraint: NSLayoutConstraint!
    weak var delegate: MediaCarouselViewDelegate?

    private var currentIndex = 0 {
        didSet {
            feedDataItem?.currentMediaIndex = currentIndex
            pageControl?.currentPage = currentIndex

            if oldValue != currentIndex {
                if let videoCell = collectionView.cellForItem(at: IndexPath(row: oldValue, section: MediaSliderSection.main.rawValue)) as? MediaCarouselVideoCollectionViewCell {
                    videoCell.stopPlayback()
                }

                if shouldAutoPlay {
                    playCurrentVideo()
                }

                if let delegate = delegate {
                    delegate.mediaCarouselView(self, indexChanged: currentIndex)
                }
            }
        }
    }

    private var mediaIndexToScrollToInLayoutSubviews: Int? = nil

    private func setCurrentIndex(_ index: Int, animated: Bool) {
        let pageWidth = collectionView.frame.width
        var contentOffset = collectionView.contentOffset
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            contentOffset.x = CGFloat(media.count - 1 - index) * pageWidth
        } else {
            contentOffset.x = CGFloat(index) * pageWidth
        }
        collectionView.setContentOffset(contentOffset, animated: animated)
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
        collectionView.allowsSelection = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        return collectionView
    }()

    private lazy var pageControl: UIPageControl? = nil
    public static let pageControlAreaHeight: CGFloat = {
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
        clipsToBounds = false
        isUserInteractionEnabled = true
        layoutMargins = .zero

        // Collection view container lets items remain visible when scrolling through "gutter" but clip at edge of card
        let collectionViewContainer = UIView()
        collectionViewContainer.translatesAutoresizingMaskIntoConstraints = false
        collectionViewContainer.clipsToBounds = true

        collectionViewContainer.addSubview(collectionView)
        addSubview(collectionViewContainer)

        collectionViewContainer.constrain([.top, .bottom], to: collectionView)
        collectionViewContainer.constrain(anchor: .leading, to: self, constant: -configuration.gutterWidth)
        collectionViewContainer.constrain(anchor: .trailing, to: self, constant: configuration.gutterWidth)

        if configuration.isPagingEnabled {
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -0.5*configuration.cellSpacing).isActive = true
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0.5*configuration.cellSpacing).isActive = true
        } else {
            collectionView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
            collectionView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        }
        collectionView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        collectionBottomConstraint = collectionView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)

        updatePageControl()
        collectionView.delegate = self

        let dataSource = UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>(collectionView: collectionView) { [weak self] collectionView, indexPath, feedMedia in
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
                cell.downloadProgressViewSize = self.configuration.downloadProgressViewSize
                if let videoCell = cell as? MediaCarouselVideoCollectionViewCell {
                    videoCell.showsVideoPlaybackControls = self.configuration.showVideoPlaybackControls
                    videoCell.disablePlayback = self.configuration.disablePlayback
                }
                cell.configure(with: feedMedia)
                if self.shouldAutoPlay,
                    indexPath.item == self.currentIndex,
                    let videoCell = cell as? MediaCarouselVideoCollectionViewCell
                {
                    videoCell.startPlayback()
                }
                return cell
            }
            return MediaCarouselCollectionViewCell()
        }
        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
        snapshot.appendSections([.main])
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            snapshot.appendItems(media.reversed())
        } else {
            snapshot.appendItems(media)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        self.dataSource = dataSource
    }

    private func updatePageControl() {
        if media.count > 1 && configuration.isPagingEnabled {
            if (pageControl == nil) {
                let pageControl = UIPageControl()
                pageControl.pageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.2)
                pageControl.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.7)
                pageControl.translatesAutoresizingMaskIntoConstraints = false
                pageControl.addTarget(self, action: #selector(pageControlAction), for: .valueChanged)
                pageControl.sizeToFit()
                addSubview(pageControl)

                pageControl.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: LayoutConstants.pageControlSpacingTop).isActive = true
                pageControl.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor, constant: -LayoutConstants.pageControlSpacingBottom).isActive = true
                pageControl.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true

                self.pageControl = pageControl
            }
            pageControl?.numberOfPages = media.count
            collectionBottomConstraint.isActive = false
        } else {
            if pageControl != nil {
                pageControl?.removeFromSuperview()
                pageControl = nil
            }
            collectionBottomConstraint.isActive = true
        }
    }

    public func refreshData(media: [FeedMedia], index: Int) {
        stopPlayback()

        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
        snapshot.appendSections([.main])
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            snapshot.appendItems(media.reversed())
        } else {
            snapshot.appendItems(media)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        self.media = media
        updatePageControl()

        let newIndex = max(0, min(index, self.media.count - 1))
        if newIndex != currentIndex {
            currentIndex = newIndex
            setCurrentIndex(newIndex, animated: true)
        } else if self.shouldAutoPlay {
            playCurrentVideo()
        }
    }

    @objc private func pageControlAction() {
        setCurrentIndex(pageControl?.currentPage ?? 0, animated: true)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil, configuration.isPagingEnabled, let mediaIndex = feedDataItem?.currentMediaIndex {
            // Delay scrolling until view has a non-zero size.
            mediaIndexToScrollToInLayoutSubviews = mediaIndex
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let mediaIndex = mediaIndexToScrollToInLayoutSubviews {
            // DispatchAsync is needed because collection view isn't resized at this point
            // because of complex view hierarchy and non-trivial auto layout constraints.
            DispatchQueue.main.async {
                if self.collectionView.frame.size != .zero {
                    self.setCurrentIndex(mediaIndex, animated: false)
                    self.mediaIndexToScrollToInLayoutSubviews = nil
               }
            }
        }
    }

    func stopPlayback() {
        for cell in collectionView.visibleCells {
            if let videoCell = cell as? MediaCarouselVideoCollectionViewCell {
                videoCell.stopPlayback()
            }
        }
    }

    func playCurrentVideo() {
        if let videoCell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: MediaSliderSection.main.rawValue)) as? MediaCarouselVideoCollectionViewCell {
            videoCell.startPlayback()
        }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if configuration.isPagingEnabled {
            var size = bounds.size
            if pageControl != nil && size.height > Self.pageControlAreaHeight {
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
        let viewCenterXInScrollViewCoordinates = scrollView.convert(center, from: self).x
        let pageIndex = Int(viewCenterXInScrollViewCoordinates / pageWidth)
        if scrollView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            currentIndex = media.count - 1 - pageIndex
        } else {
            currentIndex = pageIndex
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let delegate = delegate {
            delegate.mediaCarouselView(self, didTapMediaAtIndex: indexPath.item)
        }
    }

}

fileprivate class MediaCarouselCollectionViewCell: UICollectionViewCell {

    var scaleContentToFit: Bool = false
    var isZoomEnabled: Bool = true
    var cornerRadius: CGFloat = 10
    var downloadProgressViewSize: CGFloat = 80 {
        didSet {
            if downloadProgressViewSize == 0 {
                hideProgressView()
            } else if let constraint = downloadProgressViewWidthConstraint {
                constraint.constant = downloadProgressViewSize
            }
        }
    }
    private var downloadProgressViewWidthConstraint: NSLayoutConstraint?
    var downloadProgressCancellable: AnyCancellable?

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3 // Same color as the placeholder
        progressView.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressViewWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: downloadProgressViewSize)
        downloadProgressViewWidthConstraint?.isActive = true
        progressView.heightAnchor.constraint(equalTo: progressView.widthAnchor, multiplier: 1).isActive = true
        return progressView
    }()

    override func prepareForReuse() {
        super.prepareForReuse()
        if let progressView = progressViewIfExists() {
            progressView.isHidden = true
        }
        downloadProgressCancellable?.cancel()
        downloadProgressCancellable = nil
    }

    func configure(with media: FeedMedia) {
        guard media.isDownloadRequired else {
            hideProgressView()
            downloadProgressCancellable?.cancel()
            downloadProgressCancellable = nil
            return
        }
        guard downloadProgressViewSize > 0 else { return }
        showProgressView()
        startObservingDownloadProgressIfNecessary(media)
    }

    func startObservingDownloadProgressIfNecessary(_ media: FeedMedia) {
        guard downloadProgressCancellable == nil else { return }

        if let downloadTask = MainAppContext.shared.feedData.downloadTask(for: media) {
            downloadProgressCancellable = downloadTask.downloadProgress.sink(receiveCompletion: { [weak self] (_) in
                guard let self = self else { return }
                self.progressView.setProgress(1, withAnimationDuration: 0.1) {
                    self.hideProgressView()
                }
            }) { [weak self] (progress) in
                guard let self = self else { return }
                self.progressView.setProgress(progress, animated: true)
            }
        } else {
            // Download task might not be set up yet if feed post has been received and made visible immediately.
            progressView.setProgress(0, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.startObservingDownloadProgressIfNecessary(media)
            }
        }
    }

    private func progressViewIfExists() -> CircularProgressView? {
        return contentView.subviews.first(where: { $0.isKind(of: CircularProgressView.self) }) as? CircularProgressView
    }

    private func showProgressView() {
        if progressView.superview == nil {
            contentView.addSubview(progressView)
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        }
        contentView.bringSubviewToFront(progressView)
        progressView.isHidden = false
    }

    private func hideProgressView() {
        progressViewIfExists()?.isHidden = true
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
        placeholderImageView = UIImageView(frame: contentView.bounds)
        placeholderImageView.contentMode = .center
        placeholderImageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "photo")
        placeholderImageView.tintColor = .systemGray3
        contentView.addSubview(placeholderImageView)

        imageView = ZoomableImageView(frame: contentView.bounds)
        imageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        imageView.cornerRadius = cornerRadius
        contentView.addSubview(imageView)
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

    deinit {
        if avPlayerViewController.player != nil {
            avPlayerViewController.player?.removeObserver(self, forKeyPath: #keyPath(AVPlayer.rate), context: &avPlayerContext)
            avPlayerViewController.player?.removeObserver(self, forKeyPath: #keyPath(AVPlayer.status), context: &avPlayerContext)
            avPlayerViewController.player = nil
        }
        avPlayerViewController.removeObserver(self, forKeyPath: #keyPath(AVPlayerViewController.videoBounds), context:&avPlayerVCContext)
    }

    private var placeholderImageView: UIImageView!
    private var videoURL: URL?
    private var avPlayerViewController: AVPlayerViewController!
    private var avPlayerContext = 0
    private var avPlayerVCContext = 0
    private var playButton: UIButton!

    private var videoLoadingCancellable: AnyCancellable?
    private var videoPlaybackCancellable: AnyCancellable?

    var showsVideoPlaybackControls = true
    var disablePlayback = false {
        didSet {
            playButton.isUserInteractionEnabled = !disablePlayback
        }
    }

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
            avPlayerViewController.player?.removeObserver(self, forKeyPath: #keyPath(AVPlayer.status), context: &avPlayerContext)
            avPlayerViewController.player = nil
        }

        avPlayerViewController.view.frame = self.bounds
        avPlayerViewController.view.layer.mask = nil
        avPlayerViewController.showsPlaybackControls = false

        playButton.isHidden = true
    }

    private func commonInit() {
        placeholderImageView = UIImageView(frame: contentView.bounds)
        placeholderImageView.contentMode = .center
        placeholderImageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "video")
        placeholderImageView.tintColor = .systemGray3
        contentView.addSubview(placeholderImageView)

        avPlayerViewController = AVPlayerViewController()
        avPlayerViewController.view.frame = contentView.bounds
        avPlayerViewController.view.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        avPlayerViewController.view.isHidden = true
        avPlayerViewController.view.backgroundColor = .clear
        avPlayerViewController.showsPlaybackControls = false
        contentView.addSubview(avPlayerViewController.view)

        avPlayerViewController.addObserver(self, forKeyPath: #keyPath(AVPlayerViewController.videoBounds), options: [ ], context:&avPlayerVCContext)

        initPlayButton()
    }

    private func initPlayButton() {
        let size: CGFloat = 60
        let config = UIImage.SymbolConfiguration(pointSize: 22)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(.white, renderingMode: .alwaysOriginal)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isUserInteractionEnabled = false

        let button = UIButton.systemButton(with: icon, target: self, action: #selector(startPlayback))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        button.insertSubview(blur, at: 0)

        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            blur.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            blur.topAnchor.constraint(equalTo: button.topAnchor),
            blur.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        playButton = button
        playButton.isHidden = true
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
        avPlayerViewController.view.isHidden = false
        placeholderImageView.isHidden = true

        let avPlayer = AVPlayer(url: videoURL)
        // Monitor when this cell's video starts playing and send out broadcast when it does.
        avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.rate), options: [ .new ], context: &avPlayerContext)
        // Monitor when the video is ready for playing and only then attach the player to the controller
        avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [ .new ], context: &avPlayerContext)

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

    @objc func startPlayback() {
        guard !disablePlayback else { return }

        if avPlayerViewController.player?.timeControlStatus == AVPlayer.TimeControlStatus.paused {
            if showsVideoPlaybackControls {
                playButton.isHidden = true
                avPlayerViewController.showsPlaybackControls = true
            }
            avPlayerViewController.player?.seek(to: .zero)
            avPlayerViewController.player?.play()
        }
    }

    private func updatePlayerViewFrame() {
        // Video takes entire cell content.
        if avPlayerViewController.videoBounds.size == .zero || avPlayerViewController.videoGravity == .resizeAspectFill {
            setPlayerView(frame: contentView.bounds)
            return
        }

        let videoSize = avPlayerViewController.videoBounds.integral.size
        let cellAspectRatio = contentView.bounds.width / contentView.bounds.height
        let videoAspectRatio = videoSize.width / videoSize.height

        // Stop updating frame if desired size was reached.
        guard abs(cellAspectRatio - videoAspectRatio) > 0.01 else {
            return
        }

        var rect = contentView.bounds
        if cellAspectRatio > videoAspectRatio {
            rect.size.width = ceil(rect.height * videoAspectRatio)
            rect.origin.x = (contentView.bounds.width - rect.width) / 2
        } else {
            rect.size.height = ceil(rect.width / videoAspectRatio)
            rect.origin.y = (contentView.bounds.height - rect.height) / 2
        }
        setPlayerView(frame: rect)
    }

    private func setPlayerView(frame: CGRect) {
        avPlayerViewController.view.frame = frame

        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: avPlayerViewController.view.bounds, cornerRadius: cornerRadius).cgPath
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

        if keyPath == #keyPath(AVPlayer.status) {
            if let player = object as? AVPlayer, player.status == .readyToPlay {
                self.avPlayerViewController.player = player

                if showsVideoPlaybackControls {
                    self.playButton.isHidden = false
                }
            }
        }

        if keyPath == #keyPath(AVPlayerViewController.videoBounds) {
            updatePlayerViewFrame()
        }
    }

}
