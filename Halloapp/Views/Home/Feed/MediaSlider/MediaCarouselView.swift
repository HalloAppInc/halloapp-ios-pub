
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
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
    var disablePlayback = true
    var alwaysScaleToFitContent = true
    var cellSpacing: CGFloat = 20
    var cornerRadius: CGFloat = 15
    var borderWidth: CGFloat = 1 / UIScreen.main.scale
    var borderColor: UIColor? = .opaqueSeparator
    var gutterWidth: CGFloat = 0
    var pageIndicatorTintAlpha: CGFloat = 0.2 // not currently used but keep for now in case design changes
    var currentPageIndicatorTintAlpha: CGFloat = 1.0
    var downloadProgressViewSize: CGFloat = 80 // Diameter of the circular progress view. Set to 0 to hide progress view.
    var supplementaryViewsProvider: ((Int) -> [MediaCarouselSupplementaryItem])?
    var pageControlViewsProvider: ((Int) -> [MediaCarouselSupplementaryItem])?
    var loadMediaSynchronously = false

    static var `default`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration() }
    }

    static var `composer`: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration(disablePlayback: false, cornerRadius: 20, pageIndicatorTintAlpha: 0.3, currentPageIndicatorTintAlpha: 1.0) }
    }

    static var minimal: MediaCarouselViewConfiguration {
        get { MediaCarouselViewConfiguration(isPagingEnabled: false, isZoomEnabled: false, showVideoPlaybackControls: false, cellSpacing: 10, cornerRadius: 5) }
    }

    static var moment: MediaCarouselViewConfiguration {
        var config = MediaCarouselViewConfiguration()
        config.cornerRadius = MomentView.Layout.innerRadius
        config.borderWidth = 0
        return config
    }
}

struct MediaCarouselSupplementaryItem {
    var anchors: [UIView.ConstraintAnchor]
    var view: UIView
}

fileprivate struct LayoutConstants {
    static let pageControlSpacingTop: CGFloat = 6
    static let pageControlSpacingBottom: CGFloat = 12
}

fileprivate var showMLImageRank: Bool {
    return DeveloperSetting.showMLImageRank
}

class MediaCarouselView: UIView, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, MediaListAnimatorDelegate {

    let configuration: MediaCarouselViewConfiguration

    private enum MediaSliderSection: Int {
        case main = 0
    }

    private(set) var media: [FeedMedia]
    private var playbackInfo: VideoPlaybackInfo? = nil
    public var shouldAutoPlay = false

    weak var delegate: MediaCarouselViewDelegate?

    private var currentIndex = 0 {
        didSet {
            if pageControl.numberOfPages > 1 {
                pageControl.currentPage = currentIndex
                pageControl.setNeedsLayout()
            }

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
        MainAppContext.shared.mediaDidStartPlaying.send(nil)
    }

    class func preferredHeight(for media: [FeedMedia], width: CGFloat, maxHeight: CGFloat? = nil) -> CGFloat {
        let maxHeight: CGFloat = {
            if let maxHeight = maxHeight {
                return maxHeight
            }
            // We're seeing some posts appear with missing media when opening app from notification.
            // Could be related to screen bounds flakiness immediately after waking? https://developer.apple.com/forums/thread/65337
            // For now let's assume portrait orientation. This will need to change if we support landscape.
            let screenBounds = UIScreen.main.bounds
            let screenLongDimension = max(screenBounds.height, screenBounds.width)
            if screenLongDimension != screenBounds.height {
                DDLogInfo("Unexpected landscape screen bounds: [\(screenBounds)]")
            }
            let minScreenHeight: CGFloat = 568 // 2016 iPhone SE
            if screenLongDimension < minScreenHeight {
                DDLogError("Screen bounds too small: [\(screenBounds)]")
                assert(false, "Invalid screen bounds detected!")
            }
            return max(screenLongDimension, minScreenHeight) - 320
        }()

        let aspectRatios: [CGFloat] = media.compactMap {
            guard $0.size.width > 0 else { return nil }
            return $0.size.height / $0.size.width
        }
        guard let tallestItemAspectRatio = aspectRatios.max() else { return 0 }

        let height = tallestItemAspectRatio * width
        return min(maxHeight, height)
    }

    static private let cellReuseIdentifierImage = "MediaCarouselCellImage"
    static private let cellReuseIdentifierVideo = "MediaCarouselCellVideo"
    static private let cellReuseIdentifierNonPlayingVideo = "MediaCarouselCellNonPlayingVideo"
    static private let cellReuseIdentifierEmpty = "MediaCarouselCellEmpty"

    private class MediaCarouselCollectionViewLayout: UICollectionViewFlowLayout {

        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
            return super.shouldInvalidateLayout(forBoundsChange: newBounds) || collectionView?.bounds.size != newBounds.size
        }

        override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
            if collectionView?.bounds.size != newBounds.size {
                let invalidationContext = UICollectionViewFlowLayoutInvalidationContext()
                invalidationContext.invalidateFlowLayoutDelegateMetrics = true
                invalidationContext.invalidateFlowLayoutAttributes = true
                return invalidationContext
            } else {
                return super.invalidationContext(forBoundsChange: newBounds)
            }
        }
    }
    
    private lazy var collectionView: UICollectionView = {
        let layout = MediaCarouselCollectionViewLayout()
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
        collectionView.register(MediaCarouselImageCollectionViewCell.self, forCellWithReuseIdentifier: Self.cellReuseIdentifierImage)
        collectionView.register(MediaCarouselVideoCollectionViewCell.self, forCellWithReuseIdentifier: Self.cellReuseIdentifierVideo)
        collectionView.register(MediaCarouselSimpleVideoViewCell.self, forCellWithReuseIdentifier: Self.cellReuseIdentifierNonPlayingVideo)
        collectionView.register(MediaCarouselEmptyCollectionViewCell.self, forCellWithReuseIdentifier: Self.cellReuseIdentifierEmpty)
        collectionView.isPagingEnabled = configuration.isPagingEnabled
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.allowsSelection = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        return collectionView
    }()
    
    private lazy var pageControlStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4

        return stack
    }()
    
    private lazy var pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.pageIndicatorTintColor = UIColor.pageIndicatorInactive
        pageControl.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(configuration.currentPageIndicatorTintAlpha)
        pageControl.addTarget(self, action: #selector(pageControlAction), for: .valueChanged)

        return pageControl
    }()
        
    public static let pageControlAreaHeight: CGFloat = {
        let pageControl = UIPageControl()
        pageControl.numberOfPages = 2
        pageControl.sizeToFit()
        return max(pageControl.frame.height, 52) - LayoutConstants.pageControlSpacingBottom
    }()

    private var dataSource: UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>?
    
    private var mlMediaOrdering = [String]()

    init(media: [FeedMedia], initialIndex: Int? = nil, configuration: MediaCarouselViewConfiguration = MediaCarouselViewConfiguration.default) {
        self.media = media
        self.configuration = configuration
        self.mediaIndexToScrollToInLayoutSubviews = initialIndex
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(media)")
    }

    func configureMediaCarousel(media: [FeedMedia], initialIndex: Int? = nil) {
        self.media = media
        self.mediaIndexToScrollToInLayoutSubviews = initialIndex
        setupView()
    }

    private func setupView() {
        clipsToBounds = false
        isUserInteractionEnabled = true
        layoutMargins = .zero

        setupPageControlStack()
        updatePageControl()
        setupCollectionView()
        
        let dataSource = UICollectionViewDiffableDataSource<MediaSliderSection, FeedMedia>(collectionView: collectionView) { [weak self] collectionView, indexPath, feedMedia in
            guard let self = self else { return nil }

            let reuseIdentifier: String = {
                switch feedMedia.type {
                case .image: return Self.cellReuseIdentifierImage
                case .video: return self.configuration.disablePlayback ? Self.cellReuseIdentifierNonPlayingVideo : Self.cellReuseIdentifierVideo
                case .audio: return Self.cellReuseIdentifierEmpty
                case .document: return Self.cellReuseIdentifierEmpty
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
                    videoCell.configure(with: feedMedia) { [weak self] in
                        if let viewProvider = self?.configuration.supplementaryViewsProvider {
                            return viewProvider(indexPath.row)
                        }

                        return []
                    }

                    if self.shouldAutoPlay {
                        videoCell.startPlayback()
                    }
                } else {
                    cell.apply(configuration: self.configuration)
                    cell.configure(with: feedMedia) { [weak self] in
                        if let viewProvider = self?.configuration.supplementaryViewsProvider {
                            return viewProvider(indexPath.row)
                        }
                        if showMLImageRank {
                            cell.mlRankLabel.text = {
                                if let self, let id = feedMedia.id, let i = self.mlMediaOrdering.firstIndex(of: id) {
                                    return "\(i + 1) / \(self.mlMediaOrdering.count)"
                                } else {
                                    return nil
                                }
                            }()
                        }
                        return []
                    }
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
        
        if showMLImageRank {
            Task {
                self.mlMediaOrdering = await ImageRanker.shared.rankMedia(media)
                collectionView.reloadData()
            }
        }
    }
    
    private func setupCollectionView() {
        let collectionViewContainer = UIView()
        collectionViewContainer.translatesAutoresizingMaskIntoConstraints = false
        collectionViewContainer.clipsToBounds = true
        // Collection view container lets items remain visible when scrolling through "gutter" but clip at edge of card
        collectionViewContainer.addSubview(collectionView)
        addSubview(collectionViewContainer)

        var containerConstraints = [
            collectionViewContainer.topAnchor.constraint(equalTo: topAnchor),
            collectionViewContainer.bottomAnchor.constraint(equalTo: pageControlStack.topAnchor),
            collectionViewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -configuration.gutterWidth),
            collectionViewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: configuration.gutterWidth)
        ]
        
        if configuration.isPagingEnabled {
            containerConstraints += [
                collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -0.5*configuration.cellSpacing),
                collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0.5*configuration.cellSpacing)
            ]
        } else {
            containerConstraints += [
                collectionView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
            ]
        }
        
        containerConstraints += [
            collectionView.topAnchor.constraint(equalTo: collectionViewContainer.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: collectionViewContainer.bottomAnchor)
        ]
        
        NSLayoutConstraint.activate(containerConstraints)
        collectionView.delegate = self
    }
    
    private func setupPageControlStack() {
        addSubview(pageControlStack)

        // Minimize size if all contents are hidden
        let minimumHeightContstraint = pageControlStack.heightAnchor.constraint(equalToConstant: 0)
        minimumHeightContstraint.priority = UILayoutPriority(1)
        let minimumWidthContstraint = pageControlStack.widthAnchor.constraint(equalToConstant: 0)
        minimumWidthContstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            minimumHeightContstraint,
            minimumWidthContstraint,
            pageControlStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageControlStack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func updatePageControl() {
        pageControl.numberOfPages = media.count

        var leadingViews = [UIView]()
        var trailingViews = [UIView]()

        if let viewsProvider = configuration.pageControlViewsProvider {
            for item in viewsProvider(pageControl.numberOfPages) {
                if item.anchors.contains(.leading) {
                    leadingViews.append(item.view)
                } else if item.anchors.contains(.trailing) {
                    trailingViews.append(item.view)
                }
            }
        }

        for view in pageControlStack.arrangedSubviews {
            view.removeFromSuperview()
        }

        for view in leadingViews.reversed() {
            pageControlStack.insertArrangedSubview(view, at: 0)
        }

        if pageControl.numberOfPages > 1 && configuration.isPagingEnabled {
            displayPageControl()
        }

        for view in trailingViews {
            pageControlStack.addArrangedSubview(view)
        }

        if (pageControlStack.arrangedSubviews.count > 0) {
            let viewsCount = leadingViews.count + trailingViews.count
            pageControlStack.isLayoutMarginsRelativeArrangement = true
            pageControlStack.layoutMargins.top = LayoutConstants.pageControlSpacingTop
            pageControlStack.layoutMargins.bottom = viewsCount > 0 ? 0 : -LayoutConstants.pageControlSpacingBottom
        }
    }
    
    private func displayPageControl() {
        // Putting UIPageControl in this container allows us to remove
        // the padding/margins it has on both sides, so that adjacent
        // views appear near the dots. Padding is different on different screen sizes

        // TODO: Remove manual calculation dependency
        // based on observation, required to avoid the padding
        // works on current devices (iPhone 8 - 13, iOS 13 - 15)
        let pageControlWidth = CGFloat(pageControl.numberOfPages) * CGFloat(9.67) + CGFloat(pageControl.numberOfPages - 1) * CGFloat(8)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pageControl)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: pageControlWidth),
            pageControl.topAnchor.constraint(equalTo: container.topAnchor),
            pageControl.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pageControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        pageControlStack.addArrangedSubview(container)
    }

    public func refreshData(media: [FeedMedia], index: Int, animated: Bool) {
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

        dataSource.apply(snapshot, animatingDifferences: animated)
        self.media = media

        updatePageControl()

        let newIndex = max(0, min(index, self.media.count - 1))
        if newIndex != currentIndex {
            currentIndex = newIndex
            setCurrentIndex(newIndex, animated: animated)
        } else if self.shouldAutoPlay {
            playCurrentVideo()
        }
    }

    @objc private func pageControlAction() {
        setCurrentIndex(pageControl.currentPage, animated: true)
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
            let size = CGSize(width: self.bounds.size.width, height: collectionView.frame.height)
            return size
        }
            
        guard
            let mediaItem = dataSource?.itemIdentifier(for: indexPath),
            let collectionViewFlowLayout = collectionViewLayout as? UICollectionViewFlowLayout
        else {
            return .zero
        }
        
        var cellHeight = collectionView.frame.height - collectionView.contentInset.top - collectionView.contentInset.bottom
        cellHeight -= (collectionViewFlowLayout.sectionInset.top + collectionViewFlowLayout.sectionInset.bottom)

        let cellWidth = ceil(cellHeight * (mediaItem.size.width / mediaItem.size.height))
        return CGSize(width: cellWidth, height: cellHeight)
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

    // MARK: MediaListAnimatorDelegate
    var transitionViewContentMode: UIView.ContentMode {
        .scaleAspectFit
    }

    var transitionViewRadius: CGFloat {
        configuration.cornerRadius
    }

    func getTransitionView(at index: MediaIndex) -> UIView? {
        let indexPath = IndexPath(row: index.index, section: MediaSliderSection.main.rawValue)
        if let imageCell = collectionView.cellForItem(at: indexPath) as? MediaCarouselImageCollectionViewCell {
            return imageCell
        } else if let videoCell = collectionView.cellForItem(at: indexPath) as? MediaCarouselVideoCollectionViewCell {
            return videoCell
        } else if let videoCell = collectionView.cellForItem(at: indexPath) as? MediaCarouselSimpleVideoViewCell {
            return videoCell
        }

        return nil
    }

    func scrollToTransitionView(at index: MediaIndex) {
        if collectionView.isPagingEnabled {
            setCurrentIndex(index.index, animated: false)
        } else {
            let indexPath = IndexPath(row: index.index, section: MediaSliderSection.main.rawValue)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
    }

    func timeForVideo(at index: MediaIndex) -> CMTime? {
        let indexPath = IndexPath(row: index.index, section: MediaSliderSection.main.rawValue)

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
    
    fileprivate lazy var mlRankLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .black
        label.textColor = .white
        return label
    }()

    private var supplementaryConstrains = [NSLayoutConstraint]()
    private var supplementaryItems = [MediaCarouselSupplementaryItem]()
    public var hasSupplementaryViews: Bool { supplementaryItems.count > 0 }

    private func addSupplementaryViews(_ items: [MediaCarouselSupplementaryItem]) {
        removeSupplementaryViews()
        supplementaryItems.append(contentsOf: items)

        for item in items {
            contentView.addSubview(item.view)
        }
    }

    private func removeSupplementaryViews() {
        for item in supplementaryItems {
            item.view.removeFromSuperview()
        }
        NSLayoutConstraint.deactivate(supplementaryConstrains)

        supplementaryConstrains.removeAll()
        supplementaryItems.removeAll()
    }

    func constrainSupplemenaryViews(to anchorView: UIView, offset: CGPoint) {
        NSLayoutConstraint.deactivate(supplementaryConstrains)
        supplementaryConstrains.removeAll()

        for item in supplementaryItems {
            for anchor in item.anchors {
                var constant: CGFloat = 0

                switch anchor {
                case .top:
                    constant = offset.y
                case .bottom:
                    constant = -offset.y
                case .leading:
                    constant = offset.x
                case .trailing:
                    constant = -offset.x
                default:
                    break
                }

                supplementaryConstrains.append(item.view.constrain(anchor: anchor, to: anchorView, constant: constant))
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let progressView = progressViewIfExists() {
            progressView.isHidden = true
        }
        downloadProgressCancellable?.cancel()
        downloadProgressCancellable = nil
        mediaStatusCancellable?.cancel()
        mediaStatusCancellable = nil
        removeSupplementaryViews()
        if showMLImageRank {
            mlRankLabel.text = nil
        }
    }

    func apply(configuration: MediaCarouselViewConfiguration) {
        scaleContentToFit = configuration.alwaysScaleToFitContent
        downloadProgressViewSize = configuration.downloadProgressViewSize
    }

    func configure(with media: FeedMedia, supplementaryViewsProvider viewsProvider: () -> [MediaCarouselSupplementaryItem]) {
        addSupplementaryViews(viewsProvider())

        if showMLImageRank && mlRankLabel.superview == nil {
            contentView.addSubview(mlRankLabel)
            mlRankLabel.constrain([.bottom, .centerX], to: contentView)
        }

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
        DDLogVerbose("MediaCarouselView/updateMediaStatusUI/media: \(media.id ?? "[missing media id]"), \(media.isDownloadRequired)")
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

fileprivate class MediaCarouselEmptyCollectionViewCell: MediaCarouselCollectionViewCell {
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

    override func layoutSubviews() {
        super.layoutSubviews()
        constrainSupplemenaryViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageLoadingCancellable?.cancel()
        imageLoadingCancellable = nil
    }

    private func commonInit() {
        placeholderImageView = UIImageView(frame: contentView.bounds)
        placeholderImageView.contentMode = .center
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeholderImageView.image = UIImage(systemName: "photo")
        placeholderImageView.tintColor = .systemGray3
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholderImageView)
        placeholderImageView.constrain(to: contentView)

        imageView = ZoomableImageView(frame: contentView.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        imageView.constrain(to: contentView)
    }

    override func apply(configuration: MediaCarouselViewConfiguration) {
        super.apply(configuration: configuration)
        if (configuration.alwaysScaleToFitContent) {
            imageView.contentMode = .scaleAspectFit
        } else {
            imageView.contentMode = .scaleAspectFill
        }
        imageView.cornerRadius = configuration.cornerRadius
        imageView.isZoomEnabled = configuration.isZoomEnabled
        imageView.borderWidth = configuration.borderWidth
        imageView.borderColor = configuration.borderColor
    }

    override func configure(with media: FeedMedia, supplementaryViewsProvider provider: () -> [MediaCarouselSupplementaryItem]) {
        super.configure(with: media, supplementaryViewsProvider: provider)

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

        constrainSupplemenaryViews()
    }

    private func constrainSupplemenaryViews() {
        guard hasSupplementaryViews else { return }
        guard let image = imageView?.image else { return }

        let scale = min(bounds.height / image.size.height, bounds.width / image.size.width)
        let scaledWidth = scale * image.size.width
        let scaledHeight = scale * image.size.height
        let offset = CGPoint(x: (bounds.width - scaledWidth) / 2, y: (bounds.height - scaledHeight) / 2)

        constrainSupplemenaryViews(to: imageView, offset: offset)
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

    private var avPlayerViewController: AVPlayerViewController?
  
    private lazy var playButton = playButtonView
  
    private var looper: AVPlayerLooper?
    private var initialPlaybackTime: CMTime = .zero
    private var isPlayerAtStart = true

    private var videoLoadingCancellable: AnyCancellable?
    private var videoPlaybackCancellable: AnyCancellable?

    private var avPlayerRateObservation: NSKeyValueObservation?
    private var avPlayerStatusObservation: NSKeyValueObservation?

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

    private static var videoURLToAutoplay: URL? = nil

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlayerViewFrame()
    }

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

        avPlayerViewController?.player = nil
        avPlayerViewController?.view.frame = self.bounds
        avPlayerViewController?.view.layer.mask = nil
        avPlayerViewController?.showsPlaybackControls = false

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

        let playerViewController = AVPlayerViewController()
        playerViewController.view.frame = contentView.bounds
        playerViewController.view.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        playerViewController.view.isHidden = true
        playerViewController.view.backgroundColor = .clear
        playerViewController.showsPlaybackControls = false
        avPlayerViewController = playerViewController
        contentView.addSubview(playerViewController.view)
        
        playButton.isHidden = true
    }

    override func apply(configuration: MediaCarouselViewConfiguration) {
        super.apply(configuration: configuration)

        if (configuration.alwaysScaleToFitContent) {
            avPlayerViewController?.videoGravity = .resizeAspect
        } else {
            avPlayerViewController?.videoGravity = .resizeAspectFill
        }
        cornerRadius = configuration.cornerRadius
        borderWidth = configuration.borderWidth
        borderColor = configuration.borderColor
        showsVideoPlaybackControls = configuration.showVideoPlaybackControls
        disablePlayback = configuration.disablePlayback
    }

    override func configure(with media: FeedMedia, supplementaryViewsProvider provider: () -> [MediaCarouselSupplementaryItem]) {
        super.configure(with: media, supplementaryViewsProvider: provider)

        videoSize = media.size

        if media.isMediaAvailable {
            showPlayer(forVideoURL: media.fileURL!)
        } else {
            if videoLoadingCancellable == nil {
                showPlaceholderImage()
                videoLoadingCancellable = media.videoDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] (videoURL) in
                    guard let self = self else { return }
                    self.videoSize = media.size
                    self.showPlayer(forVideoURL: videoURL)
                }
            }
        }
    }

    private func showPlayer(forVideoURL videoURL: URL) {
        assert(avPlayerViewController?.player == nil)
        assert(videoPlaybackCancellable == nil)

        assert(avPlayerRateObservation == nil)
        assert(avPlayerStatusObservation == nil)

        self.videoURL = videoURL
        avPlayerViewController?.view.isHidden = false
        placeholderImageView.isHidden = true

        let item = AVPlayerItem(url: videoURL)
        let avPlayer = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: avPlayer, templateItem: item)
        // Monitor when this cell's video starts playing and send out broadcast when it does.
        avPlayerRateObservation = avPlayer.observe(\.rate, options: [ ], changeHandler: { [weak self] (player, change) in
            if player.rate == 1 {
                MainAppContext.shared.mediaDidStartPlaying.send(videoURL)
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
                self.avPlayerViewController?.player = player

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
        videoPlaybackCancellable = MainAppContext.shared.mediaDidStartPlaying.sink { [weak self] (videoURL) in
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let player = self.avPlayerViewController?.player else { return }
            guard let item = player.currentItem else { return }

            let seekTime = VideoUtils.getThumbnailTime(duration: item.duration)
            player.seek(to: seekTime)
        }
    }

    private func showPlaceholderImage() {
        avPlayerViewController?.view.isHidden = true
        placeholderImageView.isHidden = false
    }

    func getCurrentPlaybackTime() -> CMTime {
        return avPlayerViewController?.player?.currentTime() ?? .zero
    }

    func setInitialPlaybackTime(time: CMTime) {
        initialPlaybackTime = time
    }

    func stopPlayback() {
        if Self.videoURLToAutoplay == videoURL {
            Self.videoURLToAutoplay = nil
        }
        avPlayerViewController?.player?.pause()
    }

    @objc func startPlayback() {
        guard !disablePlayback else { return }

        Self.videoURLToAutoplay = avPlayerViewController?.player == nil ? videoURL : nil
        if avPlayerViewController?.player?.timeControlStatus == AVPlayer.TimeControlStatus.paused {
            if showsVideoPlaybackControls {
                playButton.isHidden = true
            }

            if let player = avPlayerViewController?.player, let duration = player.currentItem?.duration {
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
        let videoSize: CGSize
        if let track = avPlayerViewController?.player?.currentItem?.asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            videoSize = CGSize(width: abs(size.width), height: abs(size.height))
        } else {
            videoSize = self.videoSize ?? .zero
        }

        guard videoSize.height > 0, videoSize.width > 0, avPlayerViewController?.videoGravity != .resizeAspectFill else {
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
        guard let avPlayerView = avPlayerViewController?.view else {
            return
        }
        avPlayerViewController?.view.frame = frame

        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: avPlayerView.bounds, cornerRadius: cornerRadius).cgPath
        avPlayerViewController?.view.layer.mask = maskLayer

        updatePlayerBorder()
        constrainSupplemenaryViews()
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
        if let contentOverlayView = avPlayerViewController?.contentOverlayView {
            contentOverlayView.addSubview(borderView)
            borderView.frame = contentOverlayView.bounds
        }
    }

    private func constrainSupplemenaryViews() {
        guard let avPlayerView = avPlayerViewController?.view else {
            return
        }
        constrainSupplemenaryViews(to: avPlayerView, offset: .zero)
    }

    // MARK: Custom Views
    
    /// View that gets overlayed on videos to indicate they can be played.
    private var playButtonView: UIView {
        let playButton = MediaCarouselVideoPlayButton()
        playButton.addTarget(self, action: #selector(startPlayback), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        return playButton
    }
}

fileprivate class MediaCarouselSimpleVideoViewCell: MediaCarouselCollectionViewCell {

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        imageView.tintColor = .systemGray3
        return imageView
    }()

    private let playButton: UIButton = {
        let playButton = MediaCarouselVideoPlayButton()
        playButton.isUserInteractionEnabled = false
        return playButton
    }()

    private let borderView: RoundedRectView = {
        let borderView = RoundedRectView()
        borderView.fillColor = .clear
        return borderView
    }()

    private(set) var videoURL: URL?
    private var videoLoadingCancellable: AnyCancellable?
    private var preferredContentMode: UIView.ContentMode = .scaleAspectFit
    private var showsVideoPlaybackControls = true
    private var isShowingPlaceholder = false {
        didSet {
            guard isShowingPlaceholder != oldValue else {
                return
            }
            imageView.contentMode = isShowingPlaceholder ? .center : preferredContentMode
            playButton.isHidden = isShowingPlaceholder || !showsVideoPlaybackControls
            borderView.isHidden = isShowingPlaceholder
            setNeedsLayout()
        }
    }
    private var loadMediaSynchronously = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playButton)

        contentView.addSubview(borderView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            playButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func apply(configuration: MediaCarouselViewConfiguration) {
        super.apply(configuration: configuration)

        preferredContentMode = configuration.alwaysScaleToFitContent ? .scaleAspectFit : .scaleAspectFill
        borderView.cornerRadius = configuration.cornerRadius
        borderView.strokeColor = configuration.borderColor
        borderView.lineWidth = configuration.borderWidth
        showsVideoPlaybackControls = configuration.showVideoPlaybackControls
        loadMediaSynchronously = configuration.loadMediaSynchronously
    }

    override func configure(with media: FeedMedia, supplementaryViewsProvider provider: () -> [MediaCarouselSupplementaryItem]) {
        super.configure(with: media, supplementaryViewsProvider: provider)

        configure(videoURL: media.fileURL)

        if !media.isMediaAvailable {
            videoLoadingCancellable = media.videoDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] videoURL in
                self?.configure(videoURL: videoURL)
            }
        }

        constrainSupplemenaryViews(to: imageView, offset: .zero)
    }

    private func configure(videoURL: URL?) {
        guard videoURL != self.videoURL else {
            return
        }
        self.videoURL = videoURL

        // show preview image
        isShowingPlaceholder = true
        imageView.image = UIImage(systemName: "video")

        if let videoURL = videoURL {
            if loadMediaSynchronously {
                if let image = VideoUtils.videoPreviewImage(url: videoURL) {
                    isShowingPlaceholder = false
                    imageView.image = image
                }
            } else {
                DispatchQueue.global().async { [weak self] in
                    let image = VideoUtils.videoPreviewImage(url: videoURL)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, let image = image, self.videoURL == videoURL else {
                            return
                        }
                        self.isShowingPlaceholder = false
                        self.imageView.image = image
                    }
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        defer {
            CATransaction.commit()
        }

        guard !isShowingPlaceholder, borderView.cornerRadius > 0 else {
            imageView.layer.mask = nil
            borderView.frame = bounds
            return
        }

        let imageBounds: CGRect
        if imageView.contentMode == .scaleAspectFit, let image = imageView.image {
            imageBounds = AVMakeRect(aspectRatio: image.size, insideRect: bounds)
        } else {
            imageBounds = bounds
        }

        let maskLayer = imageView.layer.mask ?? CALayer()
        maskLayer.cornerRadius = borderView.cornerRadius
        maskLayer.backgroundColor = UIColor.black.cgColor
        maskLayer.frame = imageBounds
        imageView.layer.mask = maskLayer

        borderView.frame = imageBounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        videoLoadingCancellable?.cancel()
    }
}

fileprivate class MediaCarouselVideoPlayButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 25, leading: 30, bottom: 25, trailing: 30)
        imageView?.tintColor = .primaryWhiteBlack
        setImage(UIImage(systemName: "play.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 30)), for: .normal)

        let blurredEffectBackgroundView = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.5)
        blurredEffectBackgroundView.isUserInteractionEnabled = false
        blurredEffectBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(blurredEffectBackgroundView, at: 0)
        blurredEffectBackgroundView.constrain(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 100, height: 100)
    }
}
