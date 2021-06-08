
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
    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int)
    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat)
}

struct VideoPlaybackInfo {
    var playbackTime: CMTime
    var videoURL: URL
}

struct MediaCarouselViewConfiguration {
    var isPagingEnabled = true
    var isZoomEnabled = true
    var showVideoPlaybackControls = true
    var disablePlayback = false
    var alwaysScaleToFitContent = false
    var cellSpacing: CGFloat = 20
    var cornerRadius: CGFloat = 15
    var borderWidth: CGFloat = 1 / UIScreen.main.scale
    var borderColor: UIColor? = .opaqueSeparator
    var gutterWidth: CGFloat = 0
    var pageIndicatorTintAlpha: CGFloat = 0.2 // not currently used but keep for now in case design changes
    var currentPageIndicatorTintAlpha: CGFloat = 1.0
    var downloadProgressViewSize: CGFloat = 80 // Diameter of the circular progress view. Set to 0 to hide progress view.

    static var `default`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration() }
    }

    static var `composer`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration(pageIndicatorTintAlpha: 0.3, currentPageIndicatorTintAlpha: 1.0) }
    }

    static var minimal: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration(isPagingEnabled: false, isZoomEnabled: false, showVideoPlaybackControls: false, cellSpacing: 10, cornerRadius: 5) }
    }
}

fileprivate struct LayoutConstants {
    static let pageControlSpacingTop: CGFloat = -4
    static let pageControlSpacingBottom: CGFloat = -12
}

class MediaCarouselView: UIView, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, MediaExplorerTransitionDelegate {

    let configuration: MediaCarouselViewConfiguration

    private enum MediaSliderSection: Int {
        case main = 0
    }

    private let feedDataItem: FeedDataItem?

    private var media: [FeedMedia]
    private var playbackInfo: VideoPlaybackInfo? = nil
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

    class func stopAllPlayback() {
        MediaCarouselVideoCollectionViewCell.videoDidStartPlaying.send(nil)
    }

    class func preferredHeight(for media: [FeedMedia], width: CGFloat) -> CGFloat {
        let maxHeight = UIScreen.main.bounds.height - 320

        let aspectRatios: [CGFloat] = media.compactMap {
            guard $0.size.width > 0 else { return nil }
            return $0.size.height / $0.size.width
        }
        guard let tallestItemAspectRatio = aspectRatios.max() else { return 0 }

        var height = tallestItemAspectRatio * width
        if media.count > 1 {
            height += MediaCarouselView.pageControlAreaHeight
        }

        return min(maxHeight, height)
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
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as?
                MediaCarouselCollectionViewCell {
                if indexPath.item == self.currentIndex,
                   let videoCell = cell as? MediaCarouselVideoCollectionViewCell
                {
                    videoCell.apply(configuration: self.configuration)
                    if let playbackInfo = self.playbackInfo, playbackInfo.videoURL == feedMedia.fileURL {
                        videoCell.setInitialPlaybackTime(time: playbackInfo.playbackTime)
                    }
                    self.playbackInfo = nil
                    videoCell.configure(with: feedMedia)
                    if self.shouldAutoPlay {
                        videoCell.startPlayback()
                    }
                } else {
                    cell.apply(configuration: self.configuration)
                    cell.configure(with: feedMedia)
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

        // Use this instead of `didSelectItemAt` as the latter is activated by multi finger
        // tapping or even when lifting fingers after a pinch gesture
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapAction))
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.numberOfTapsRequired = 1
        collectionView.addGestureRecognizer(tapRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTapAction))
        doubleTapRecognizer.numberOfTouchesRequired = 1
        doubleTapRecognizer.numberOfTapsRequired = 2
        collectionView.addGestureRecognizer(doubleTapRecognizer)

        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(zoomAction))
        collectionView.addGestureRecognizer(zoomRecognizer)
    }

    private func updatePageControl() {
        if media.count > 1 && configuration.isPagingEnabled {
            if (pageControl == nil) {
                let pageControl = UIPageControl()
                pageControl.pageIndicatorTintColor = UIColor.pageIndicatorInactive
                pageControl.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(configuration.currentPageIndicatorTintAlpha)
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
        guard let dataSource = dataSource else { return }

        stopPlayback()
        playbackInfo = getCurrentPlaybackInfo()

        var snapshot = NSDiffableDataSourceSnapshot<MediaSliderSection, FeedMedia>()
        snapshot.appendSections([.main])
        if collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            snapshot.appendItems(media.reversed())
        } else {
            snapshot.appendItems(media)
        }

        dataSource.apply(snapshot, animatingDifferences: false)
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

    @objc private func tapAction(sender: UITapGestureRecognizer) {
        guard let indexPath = collectionView.indexPathForItem(at: sender.location(in: collectionView)) else { return }
        stopPlayback()
        delegate?.mediaCarouselView(self, didTapMediaAtIndex: indexPath.row)
    }

    @objc private func doubleTapAction(sender: UITapGestureRecognizer) {
        guard let indexPath = collectionView.indexPathForItem(at: sender.location(in: collectionView)) else { return }
        delegate?.mediaCarouselView(self, didDoubleTapMediaAtIndex: indexPath.row)
    }

    @objc private func zoomAction(sender: UIPinchGestureRecognizer) {
        guard let indexPath = collectionView.indexPathForItem(at: sender.location(in: collectionView)) else { return }
        delegate?.mediaCarouselView(self, didZoomMediaAtIndex: indexPath.row, withScale: sender.scale)
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

    func getCurrentPlaybackInfo() -> VideoPlaybackInfo? {
        if let videoCell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: MediaSliderSection.main.rawValue)) as? MediaCarouselVideoCollectionViewCell, let videoURL = videoCell.videoURL {
            return VideoPlaybackInfo(playbackTime: videoCell.getCurrentPlaybackTime(), videoURL: videoURL)
        }
        return nil
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

    // MARK: MediaExplorerTransitionDelegate
    func getTransitionView(atPostion index: Int) -> UIView? {
        let indexPath = IndexPath(row: index, section: MediaSliderSection.main.rawValue)
        return collectionView.cellForItem(at: indexPath)
    }

    func scrollMediaToVisible(atPostion index: Int) {
        if collectionView.isPagingEnabled {
            setCurrentIndex(index, animated: false)
        } else {
            let indexPath = IndexPath(row: index, section: MediaSliderSection.main.rawValue)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
    }

    func currentTimeForVideo(atPostion index: Int) -> CMTime? {
        let indexPath = IndexPath(row: index, section: MediaSliderSection.main.rawValue)

        if let cell = collectionView.cellForItem(at: indexPath) as? MediaCarouselVideoCollectionViewCell {
            return cell.getCurrentPlaybackTime()
        }

        return nil
    }
}

fileprivate class MediaCarouselCollectionViewCell: UICollectionViewCell {

    private(set) var scaleContentToFit: Bool = false

    private var downloadProgressViewSize: CGFloat = 80 {
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
    private var mediaStatusCancellable: AnyCancellable?

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
        mediaStatusCancellable?.cancel()
        mediaStatusCancellable = nil
    }

    func apply(configuration: MediaCarouselViewConfiguration) {
        scaleContentToFit = configuration.alwaysScaleToFitContent
        downloadProgressViewSize = configuration.downloadProgressViewSize
    }

    func configure(with media: FeedMedia) {
        updateMediaStatusUI(with: media)
        if mediaStatusCancellable == nil {
            mediaStatusCancellable = media.mediaStatusDidChange.sink { [weak self] media in
                guard let self = self else { return }
                DDLogVerbose("MediaCarouselCollectionViewCell/mediaStatusCancellable/status \(media.isDownloadRequired)")
                DispatchQueue.main.async {
                    self.updateMediaStatusUI(with: media)
                }
            }
        }
    }

    func updateMediaStatusUI(with media: FeedMedia) {
        DDLogVerbose("MediaCarouselView/updateMediaStatusUI/media: \(media.id), \(media.isDownloadRequired)")
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
        guard downloadProgressCancellable == nil else {
            // This could happen when we switch media.status from downloading to downloadError.
            // we continue to show progress bar, but we dont have any task for progress.
            // so we cancel and wait.
            downloadProgressCancellable?.cancel()
            downloadProgressCancellable = nil
            return
        }

        if let progress = media.progress {
            // Dont update view on completion - since download could have succeeded or failed.
            downloadProgressCancellable = progress.receive(on: DispatchQueue.main).sink() { [weak self] (progress) in
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
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
    }

    override func apply(configuration: MediaCarouselViewConfiguration) {
        super.apply(configuration: configuration)

        imageView.cornerRadius = configuration.cornerRadius
        imageView.isZoomEnabled = configuration.isZoomEnabled
        imageView.borderWidth = configuration.borderWidth
        imageView.borderColor = configuration.borderColor
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        if media.isMediaAvailable {
            if let image = media.image {
                show(image: image)
            } else {
                showPlaceholderImage()
                MainAppContext.shared.errorLogger?.logError(FeedMediaError.missingImage)
            }
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
    private(set) var videoURL: URL?
    private var videoSize: CGSize?

    private var avPlayerViewController: AVPlayerViewController!
    private var playButton: UIButton!
    private var initialPlaybackTime: CMTime = .zero
    private var isPlayerAtStart = true

    private var videoLoadingCancellable: AnyCancellable?
    private var videoPlaybackCancellable: AnyCancellable?

    private var avPlayerRateObservation: NSKeyValueObservation?
    private var avPlayerStatusObservation: NSKeyValueObservation?
    private var avPlayerVCVideoBoundsObservation: NSKeyValueObservation?

    private var cornerRadius: CGFloat = 0 {
        didSet {
            avPlayerBorderView?.cornerRadius = cornerRadius
        }
    }
    private var borderWidth: CGFloat = 0 {
        didSet {
            avPlayerBorderView?.lineWidth = borderWidth
        }
    }
    private var borderColor: UIColor? {
        didSet {
            avPlayerBorderView?.strokeColor = borderColor
        }
    }
    private var avPlayerBorderView: RoundedRectView?
    private var showsVideoPlaybackControls = true
    private var disablePlayback = false {
        didSet {
            playButton.isUserInteractionEnabled = !disablePlayback
        }
    }

    public static let videoDidStartPlaying = PassthroughSubject<URL?, Never>()
    private static var videoURLToAutoplay: URL? = nil

    override func prepareForReuse() {
        super.prepareForReuse()

        videoURL = nil
        initialPlaybackTime = .zero

        videoLoadingCancellable?.cancel()
        videoLoadingCancellable = nil

        videoPlaybackCancellable?.cancel()
        videoPlaybackCancellable = nil

        avPlayerStatusObservation = nil
        avPlayerRateObservation = nil

        if avPlayerViewController.player != nil {
            avPlayerViewController.player = nil
        }

        avPlayerViewController.view.frame = self.bounds
        avPlayerViewController.view.layer.mask = nil
        avPlayerViewController.showsPlaybackControls = false

        playButton.isHidden = true
        isPlayerAtStart = true
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

        avPlayerVCVideoBoundsObservation = avPlayerViewController.observe(\.videoBounds, options: [ ], changeHandler: { [weak self] (_, _) in
            guard let self = self else { return }
            self.updatePlayerViewFrame()
        })

        initPlayButton()
    }

    private func initPlayButton() {
        let size: CGFloat = 100
        let config = UIImage.SymbolConfiguration(pointSize: 30)
        let iconColor = UIColor.primaryWhiteBlack
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

        let button = UIButton.systemButton(with: icon, target: self, action: #selector(startPlayback))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
        blurredEffectView.isUserInteractionEnabled = false
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

        button.insertSubview(blurredEffectView, at: 0)
        blurredEffectView.constrain(to: button)

        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        playButton = button
        playButton.isHidden = true
    }

    override func apply(configuration: MediaCarouselViewConfiguration) {
        super.apply(configuration: configuration)

        cornerRadius = configuration.cornerRadius
        borderWidth = configuration.borderWidth
        borderColor = configuration.borderColor
        showsVideoPlaybackControls = configuration.showVideoPlaybackControls
        disablePlayback = configuration.disablePlayback
    }

    override func configure(with media: FeedMedia) {
        super.configure(with: media)

        avPlayerViewController.videoGravity = .resizeAspect
        videoSize = media.size

        if media.isMediaAvailable {
            showPlayer(forVideoURL: media.fileURL!)
        } else {
            if videoLoadingCancellable == nil {
                showPlaceholderImage()
                videoLoadingCancellable = media.videoDidBecomeAvailable.sink { [weak self] (videoURL) in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.showPlayer(forVideoURL: videoURL)
                    }
                }
            }
        }
    }

    private func showPlayer(forVideoURL videoURL: URL) {
        assert(avPlayerViewController.player == nil)
        assert(videoPlaybackCancellable == nil)

        assert(avPlayerRateObservation == nil)
        assert(avPlayerStatusObservation == nil)

        self.videoURL = videoURL
        avPlayerViewController.view.isHidden = false
        placeholderImageView.isHidden = true

        let avPlayer = AVPlayer(url: videoURL)
        // Monitor when this cell's video starts playing and send out broadcast when it does.
        avPlayerRateObservation = avPlayer.observe(\.rate, options: [ ], changeHandler: { [weak self] (player, change) in
            if player.rate == 1 {
                Self.videoDidStartPlaying.send(videoURL)
            }
            guard let self = self else { return }
            if player.rate == 0 && self.showsVideoPlaybackControls {
                self.playButton.isHidden = false
            }

            if player.rate == 0 {
                self.isPlayerAtStart = player.currentTime() == .zero || player.currentTime() == player.currentItem?.duration

                if self.isPlayerAtStart {
                    self.showInitialFrame()
                }
            }
        })
        // Monitor when the video is ready for playing and only then attach the player to the view controller.
        avPlayerStatusObservation = avPlayer.observe(\.status, options: [ .new ], changeHandler: { [weak self] (player, change) in
            guard let self = self else { return }
            if player.status == .readyToPlay {
                self.avPlayerViewController.player = player

                if self.initialPlaybackTime == .zero {
                    self.isPlayerAtStart = true
                    self.showInitialFrame()
                }

                if self.showsVideoPlaybackControls {
                    self.playButton.isHidden = false
                }

                if let videoURLToAutoplay = Self.videoURLToAutoplay {
                    if videoURLToAutoplay == videoURL {
                        Self.videoURLToAutoplay = nil
                        self.startPlayback()
                    }
                }
            }
        })

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

        updatePlayerViewFrame()
    }

    private func showInitialFrame() {
        guard let player = avPlayerViewController.player else { return }
        guard let item = player.currentItem else { return }

        let seekTime = VideoUtils.getThumbnailTime(duration: item.duration)
        player.seek(to: seekTime)
    }

    private func showPlaceholderImage() {
        avPlayerViewController.view.isHidden = true
        placeholderImageView.isHidden = false
    }

    func getCurrentPlaybackTime() -> CMTime {
        return avPlayerViewController.player?.currentTime() ?? .zero
    }

    func setInitialPlaybackTime(time: CMTime) {
        initialPlaybackTime = time
    }

    func stopPlayback() {
        if Self.videoURLToAutoplay == videoURL {
            Self.videoURLToAutoplay = nil
        }
        avPlayerViewController.player?.pause()
    }

    @objc func startPlayback() {
        guard !disablePlayback else { return }

        Self.videoURLToAutoplay = avPlayerViewController.player == nil ? videoURL : nil
        if avPlayerViewController.player?.timeControlStatus == AVPlayer.TimeControlStatus.paused {
            if showsVideoPlaybackControls {
                playButton.isHidden = true
            }

            if let player = avPlayerViewController.player, let duration = player.currentItem?.duration {
                if initialPlaybackTime > .zero && initialPlaybackTime < duration {
                    player.seek(to: initialPlaybackTime)
                    initialPlaybackTime = .zero
                } else if player.currentTime() == duration || isPlayerAtStart {
                    player.seek(to: .zero)
                }

                player.play()
            }
        }
    }

    private func updatePlayerViewFrame() {
        guard let videoSize = videoSize, videoSize.height > 0 && videoSize.width > 0 && avPlayerViewController.videoGravity != .resizeAspectFill else
        {
            // Video takes entire cell content.
            setPlayerView(frame: contentView.bounds)
            return
        }
        let contentSize = contentView.bounds.size
        let videoScale = min(contentSize.height/videoSize.height, contentSize.width/videoSize.width)
        let playerSize = videoSize.applying(.init(scaleX: videoScale, y: videoScale))
        let playerFrame = CGRect(
            origin: CGPoint(x: (contentSize.width - playerSize.width) / 2, y: (contentSize.height - playerSize.height) / 2),
            size: playerSize)

        setPlayerView(frame: playerFrame)
    }

    private func setPlayerView(frame: CGRect) {
        guard avPlayerViewController.view.frame != frame else {
            DDLogInfo("MediaCarouselView/setPlayerViewFrame/skipping [equal]")
            return
        }
        avPlayerViewController.view.frame = frame

        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: avPlayerViewController.view.bounds, cornerRadius: cornerRadius).cgPath
        avPlayerViewController.view.layer.mask = maskLayer

        updatePlayerBorder()
    }

    private func updatePlayerBorder() {
        // No border
        guard borderColor != nil && borderWidth > 0 else {
            avPlayerBorderView?.removeFromSuperview()
            return
        }

        // Border
        let borderView: RoundedRectView
        if let existingBorderView = avPlayerBorderView {
            borderView = existingBorderView
        } else {
            borderView = RoundedRectView()
            borderView.fillColor = .clear
            borderView.cornerRadius = cornerRadius
            borderView.strokeColor = borderColor
            borderView.lineWidth = borderWidth
            borderView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
            avPlayerBorderView = borderView
        }
        if let contentOverlayView = avPlayerViewController.contentOverlayView {
            contentOverlayView.addSubview(borderView)
            borderView.frame = contentOverlayView.bounds
        }
    }

}
