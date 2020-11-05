//
//  MediaExplorerController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Core
import Foundation
import UIKit

protocol MediaExplorerTransitionDelegate: AnyObject {
    func getTransitionView(atPostion index: Int) -> UIView?
    func scrollMediaToVisible(atPostion index: Int)
}

class MediaExplorerController : UIViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate {

    private let spaceBetweenPages: CGFloat = 20

    private let media: [MediaExplorerMedia]
    private var collectionView: UICollectionView!
    private var pageControl: UIPageControl!
    private var tapRecorgnizer: UITapGestureRecognizer!
    private var swipeDownRecognizer: UIPanGestureRecognizer!
    private var swipeDownStart: CGPoint?
    private var isSystemUIHidden = false

    private var currentIndex: Int {
        didSet {
            if oldValue != currentIndex {
                pageControl?.currentPage = currentIndex
                
                if let cell = collectionView.cellForItem(at: IndexPath(item: oldValue, section: 0)) as? VideoCell {
                    cell.pause()
                } else if let cell = collectionView.cellForItem(at: IndexPath(item: oldValue, section: 0)) as? ImageCell {
                    cell.reset()
                }

                if let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? VideoCell {
                    cell.play()
                }
            }
        }
    }

    public weak var delegate: MediaExplorerTransitionDelegate?

    override var prefersStatusBarHidden: Bool {
        true
    }

    init(media: [FeedMedia], index: Int) {
        self.media = media.map {
            MediaExplorerMedia(url: $0.fileURL, image: $0.image, type: ($0.type == .image ? .image : .video), size: $0.size)
        }
        self.currentIndex = index

        super.init(nibName: nil, bundle: nil)
    }

    init(media: [ChatMedia], index: Int) {
        self.media = media.map {
            let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent($0.relativeFilePath ?? "", isDirectory: false)
            let image: UIImage? = $0.type == .image ? UIImage(contentsOfFile: url.path) : nil
            return MediaExplorerMedia(url: url, image: image, type: ($0.type == .image ? .image : .video), size: $0.size)
        }
        self.currentIndex = index

        super.init(nibName: nil, bundle: nil)
    }

    init(media: [ChatQuotedMedia], index: Int) {
        self.media = media.map {
            let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent($0.relativeFilePath ?? "", isDirectory: false)
            let image: UIImage? = $0.type == .image ? UIImage(contentsOfFile: url.path) : nil
            return MediaExplorerMedia(url: url, image: image, type: ($0.type == .image ? .image : .video), size: .zero)
        }
        self.currentIndex = index

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func withNavigationController() -> UINavigationController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .fullScreen
        controller.transitioningDelegate = self

        return controller
    }

    override func viewDidLoad() {
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.backgroundColor = .clear

        let backIcon = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: backIcon, style: .plain, target: self, action: #selector(backAction))

        collectionView = makeCollectionView()
        self.view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: -spaceBetweenPages),
            collectionView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: spaceBetweenPages),
            collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if media.count > 1 {
            pageControl = makePageControl()
            self.view.addSubview(pageControl)

            NSLayoutConstraint.activate([
                pageControl.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
                pageControl.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            ])
        }

        toggleSystemUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let page = pageControl?.currentPage, page != currentIndex {
            pageControl?.currentPage = currentIndex
            let x = collectionView.frame.width * CGFloat(currentIndex)
            collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if media[currentIndex].type == .video {
            if let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? VideoCell {
                cell.play()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        for cell in collectionView.visibleCells {
            if let cell = cell as? VideoCell {
                cell.pause()
            }
        }
    }

    private func makeCollectionView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero
        layout.scrollDirection = .horizontal

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isPagingEnabled = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInsetAdjustmentBehavior = .never

        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: ImageCell.reuseIdentifier)
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseIdentifier)
        
        collectionView.dataSource = self
        collectionView.delegate = self

        tapRecorgnizer = UITapGestureRecognizer(target: self, action: #selector(onTapAction(sender:)))
        tapRecorgnizer.delegate = self
        collectionView.addGestureRecognizer(tapRecorgnizer)

        // Not using UISwipeGestureRecognizer because slow swipes are indistinguishable from drag down on images
        swipeDownRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onSwipeDownAction(sender:)))
        swipeDownRecognizer.maximumNumberOfTouches = 1
        swipeDownRecognizer.delegate = self
        collectionView.addGestureRecognizer(swipeDownRecognizer)

        return collectionView
    }

    private func makePageControl() -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.7)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = media.count
        pageControl.addTarget(self, action: #selector(pageChangeAction), for: .valueChanged)

        return pageControl
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let rem = scrollView.contentOffset.x.truncatingRemainder(dividingBy: scrollView.frame.width)

        if rem == 0 {
            let index = Int(scrollView.contentOffset.x / scrollView.frame.width)

            if index != currentIndex {
                currentIndex = index
            }
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = media[indexPath.item]

        switch item.type {
        case .image:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCell.reuseIdentifier, for: indexPath) as! ImageCell
            cell.image = item.image
            cell.scrollView = collectionView
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseIdentifier, for: indexPath) as! VideoCell
            cell.url = item.url
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tapRecorgnizer {
            if let other = otherGestureRecognizer as? UITapGestureRecognizer {
                return other.numberOfTapsRequired == 1
            }
        }

        if gestureRecognizer == swipeDownRecognizer {
            return true
        }

        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tapRecorgnizer {
            if let other = otherGestureRecognizer as? UITapGestureRecognizer {
                return other.numberOfTapsRequired > 1
            }
        }

        return false
    }

    private func toggleSystemUI() {
        isSystemUIHidden = !isSystemUIHidden

        navigationController?.setNavigationBarHidden(isSystemUIHidden, animated: true)

        for cell in collectionView.visibleCells {
            if let cell = cell as? VideoCell {
                cell.isSystemUIHidden = isSystemUIHidden
            }
        }
    }

    @objc private func backAction() {
        delegate?.scrollMediaToVisible(atPostion: currentIndex)
        self.dismiss(animated: true)
    }

    @objc private func pageChangeAction() {
        if currentIndex != pageControl.currentPage {
            let x = collectionView.frame.width * CGFloat(pageControl.currentPage)
            collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: true)
        }
    }

    @objc private func onTapAction(sender: UITapGestureRecognizer) {
        toggleSystemUI()
    }

    @objc private func onSwipeDownAction(sender: UIPanGestureRecognizer) {
        let location = sender.location(in: sender.view)
        let velocity = sender.velocity(in: sender.view)

        switch sender.state {
        case .began:
            swipeDownStart = location
        case .cancelled:
            swipeDownStart = nil
        case .ended:
            guard let start = swipeDownStart else { return }
            let distance = location.y - start.y

            if distance > 100 && velocity.y > 200 {
                backAction()
            }

            swipeDownStart = nil
        default:
            if velocity.y < 200 {
                swipeDownStart = nil
            }
        }
    }

    // MARK: UIViewControllerTransitioningDelegate

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animator = Animator(media: media[currentIndex], atPosition: currentIndex, presenting: true)
        animator.delegate = delegate

        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animator = Animator(media: media[currentIndex], atPosition: currentIndex, presenting: false)
        animator.delegate = delegate

        return animator
    }
}

fileprivate class ImageCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ImageCell.self)
    }

    public var scrollView: UIScrollView!

    private var previousScale = CGFloat(1.0)
    private var previousNumberOfTouches = 0
    private var previousLocation = CGPoint.zero
    private var originalFrame = CGRect.zero
    private var originalOffset = CGPoint.zero

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()

    private var imageConstraints: [NSLayoutConstraint] = []
    var image: UIImage! {
        didSet {
            let scale = min((contentView.frame.width - 40) / image.size.width, contentView.frame.height / image.size.height)

            NSLayoutConstraint.deactivate(imageConstraints)
            imageConstraints = [
                imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: image.size.width * scale),
                imageView.heightAnchor.constraint(equalToConstant: image.size.height * scale),
            ]
            NSLayoutConstraint.activate(imageConstraints)

            reset()

            imageView.image = image
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageView)
        contentView.clipsToBounds = true

        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onZoom(sender:)))
        imageView.addGestureRecognizer(zoomRecognizer)

        let dragRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onDrag(sender:)))
        dragRecognizer.maximumNumberOfTouches = 1
        dragRecognizer.minimumNumberOfTouches = 1
        imageView.addGestureRecognizer(dragRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTapAction(sender:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        imageView.addGestureRecognizer(doubleTapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        imageView.transform = CGAffineTransform.identity
        previousScale = 1.0
        previousNumberOfTouches = 0
        previousLocation = CGPoint.zero
        originalFrame = CGRect.zero
        originalOffset = CGPoint.zero
    }

    @objc func onZoom(sender: UIPinchGestureRecognizer) {
        initOriginalValues()

        let location = sender.location(in: self)

        if sender.state == .began {
            previousLocation = location
            previousScale = 1.0
        }

        if sender.state == .began || sender.state == .changed {
            if sender.numberOfTouches != previousNumberOfTouches {
                previousLocation = location
            }

            let x = imageView.frame.midX - originalFrame.midX + location.x - previousLocation.x
            let y = imageView.frame.midY - originalFrame.midY + location.y - previousLocation.y
            let scale = sender.scale * imageView.frame.width / originalFrame.width / previousScale

            imageView.transform = CGAffineTransform.init(translationX: x, y: y).scaledBy(x: scale, y: scale)

            previousScale = sender.scale
            previousLocation = location
            previousNumberOfTouches = sender.numberOfTouches
        } else if sender.state == .ended {
            adjustImagePosition()
        }
    }

    @objc func onDrag(sender: UIPanGestureRecognizer) {
        initOriginalValues()

        let location = sender.location(in: window)
        if sender.state == .began {
            previousLocation = location
        }

        if sender.state == .began || sender.state == .changed {
            let x = location.x - previousLocation.x
            let y = location.y - previousLocation.y

            if shouldDragImage(translation: x) {
                imageView.transform = imageView.transform.concatenating(CGAffineTransform(translationX: x, y: y))
            } else {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - x, y: scrollView.contentOffset.y), animated: false)
            }

            previousLocation = location
        } else if sender.state == .ended {
            adjustImagePosition()
            adjustScrollViewPage(velocity: sender.velocity(in: window).x)
        }
    }

    @objc func onDoubleTapAction(sender: UITapGestureRecognizer) {
        initOriginalValues()

        var transform = CGAffineTransform.identity
        let scale = imageView.frame.width / originalFrame.width

        if scale == 1.0 {
            let location = sender.location(in: imageView)
            let x = location.x - imageView.frame.midX
            let y = location.y - imageView.frame.midY

            transform = CGAffineTransform.init(translationX: -x, y: -y).scaledBy(x: 2, y: 2)
        }

        UIView.animate(withDuration: 0.35) { [weak self] in
            guard let self = self else { return }
            self.imageView.transform = transform
        }
    }

    private func initOriginalValues() {
        if originalFrame == CGRect.zero {
            originalFrame = imageView.frame
            originalOffset = scrollView.contentOffset
        }
    }

    private func adjustImagePosition() {
        UIView.animate(withDuration: 0.35) { [weak self] in
            guard let self = self else { return }

            if self.originalFrame.width > self.imageView.frame.width {
                self.imageView.transform = CGAffineTransform.identity
            } else {
                let x = max(self.originalFrame.maxX - self.imageView.frame.maxX, 0) + min(self.originalFrame.minX - self.imageView.frame.minX, 0)
                let y = max(self.originalFrame.maxY - self.imageView.frame.maxY, 0) + min(self.originalFrame.minY - self.imageView.frame.minY, 0)

                self.imageView.transform = self.imageView.transform.concatenating(CGAffineTransform(translationX: x, y: y))
            }
        }
    }

    private func adjustScrollViewPage(velocity: CGFloat) {
        guard scrollView.contentOffset.x != originalOffset.x else { return }

        let diff = scrollView.contentOffset.x - originalOffset.x

        if abs(diff) > scrollView.frame.width / 2 || abs(velocity) > 200 {
            let x = originalOffset.x + scrollView.frame.width * (diff > 0 ? 1 : -1)

            if x >= 0 && x < scrollView.contentSize.width {
                scrollView.setContentOffset(CGPoint(x: x, y: originalOffset.y), animated: true)

                UIView.animate(withDuration: 0.35) { [weak self] in
                    guard let self = self else { return }
                    self.imageView.transform = CGAffineTransform.identity
                }
            } else {
                scrollView.setContentOffset(originalOffset, animated: true)
            }
        } else {
            scrollView.setContentOffset(originalOffset, animated: true)
        }
    }

    private func shouldDragImage(translation: CGFloat) -> Bool {
        if scrollView.contentOffset.x != originalOffset.x {
            return false
        }

        if translation < 0 {
            return imageView.frame.maxX > originalFrame.maxX
        } else {
            return imageView.frame.minX < originalFrame.minX
        }
    }
}

fileprivate class VideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: VideoCell.self)
    }

    private var statusObservation: NSKeyValueObservation?
    private var videoBoundsObservation: NSKeyValueObservation?

    private lazy var playerController: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.view.backgroundColor = .clear

        return controller
    }()

    var isSystemUIHidden = false {
        didSet {
            playerController.showsPlaybackControls = !isSystemUIHidden
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        statusObservation = nil
        videoBoundsObservation = nil
        url = nil
        playerController.view.frame = bounds.insetBy(dx: 20, dy: 0)
    }

    var url: URL! {
        didSet {
            if url != nil {
                let player = AVPlayer(url: url)

                statusObservation = player.observe(\.status) { [weak self] player, change in
                    guard let self = self else { return }
                    guard player.status == .readyToPlay else { return }
                    self.playerController.player = player
                }
            } else {
                playerController.player?.pause()
                statusObservation = nil
                playerController.player = nil
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        playerController.view.frame = bounds.insetBy(dx: 20, dy: 0)
        contentView.addSubview(playerController.view)
        videoBoundsObservation = playerController.observe(\.videoBounds) { controller, change in
            guard controller.videoBounds.size != .zero else { return }

            let x = controller.view.frame.midX - controller.videoBounds.width / 2
            let y = controller.view.frame.midY - controller.videoBounds.height / 2
            let bounds = controller.videoBounds

            controller.view.frame = CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play() {
        playerController.player?.seek(to: .zero)
        playerController.player?.play()
    }

    func pause() {
        playerController.player?.pause()
    }
}

fileprivate enum MediaExplorerMediaType {
    case image, video
}

fileprivate struct MediaExplorerMedia {
    var url: URL?
    var image: UIImage?
    var type: MediaExplorerMediaType
    var size: CGSize

    mutating func computeSize() {
        guard size == .zero else { return }

        if let image = image {
            size = image.size
        }

        if let url = url, type == .video, let videoSize = VideoUtils.resolutionForLocalVideo(url: url) {
            size = videoSize
        }
    }
}

fileprivate class VideoTransitionView: UIView {
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}

fileprivate class Animator: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    weak var delegate: MediaExplorerTransitionDelegate?

    private var media: MediaExplorerMedia
    private let index: Int
    private let presenting: Bool

    init(media: MediaExplorerMedia, atPosition index: Int, presenting: Bool) {
        self.media = media
        self.index = index
        self.presenting = presenting

        self.media.computeSize()
    }

    private func computeSize(containerSize: CGSize, contentSize: CGSize) -> CGSize {
        var scale = CGFloat(1.0)
        if contentSize.width > contentSize.height {
            // .scaleAspectFit
            scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        } else {
            // .scaleAspectFill
            scale = max(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        }

        let width = min(containerSize.width, contentSize.width * scale)
        let height = min(containerSize.height, contentSize.height * scale)

        return CGSize(width: width, height: height)
    }

    private func computeScaleAspectFit(containerSize: CGSize, contentSize: CGSize, transitionSize: CGSize) -> CGFloat {
        let contentFitScale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        let transitionFitScale = min(contentSize.width / transitionSize.width, contentSize.height / transitionSize.height)

        return contentFitScale * transitionFitScale
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

    func getTransitionView() -> UIView? {
        if media.type == .image {
            guard let image = media.image else { return nil }

            let imageView = UIImageView(image: image)
            imageView.contentMode = media.size.width > media.size.height ? .scaleAspectFit : .scaleAspectFill
            imageView.clipsToBounds = true

            return imageView
        } else if media.type == .video {
            guard let url = media.url else { return nil }

            let videoView = VideoTransitionView()
            videoView.player = AVPlayer(url: url)
            videoView.playerLayer.videoGravity = media.size.width > media.size.height ? .resizeAspect : .resizeAspectFill

            return videoView
        }

        return nil
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let delegate = delegate,
              let toController = transitionContext.viewController(forKey: .to),
              let fromController = transitionContext.viewController(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let fromView = transitionContext.view(forKey: .from)
        else {
            transitionContext.completeTransition(true)
            return
        }

        if presenting {
            transitionContext.containerView.addSubview(toView)
        } else {
            transitionContext.containerView.addSubview(toView)
            transitionContext.containerView.addSubview(fromView)
        }

        // Ensurees that the toView and fromView have rendered their transition views
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                transitionContext.completeTransition(true)
                return
            }

            guard let transitionView = self.getTransitionView(),
                  let originView = delegate.getTransitionView(atPostion: self.index),
                  let originFrame = originView.superview?.convert(originView.frame, to: transitionContext.containerView)
            else {
                transitionContext.completeTransition(true)
                return
            }

            let fromViewStartFrame = transitionContext.initialFrame(for: fromController)
            let toViewFinalFrame = transitionContext.finalFrame(for: toController)
            let originMediaSize = self.computeSize(containerSize: originFrame.size, contentSize: self.media.size)

            var transitionViewFinalCenter = CGPoint.zero
            var transitionViewFinalTransform = CGAffineTransform.identity
            if self.presenting {
                let scale = self.computeScaleAspectFit(containerSize: toViewFinalFrame.size, contentSize: self.media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: scale, y: scale)

                transitionView.frame.size = originMediaSize
                transitionView.center = CGPoint(x: originFrame.midX, y: originFrame.midY)
                toView.alpha = 0.0
                transitionViewFinalCenter = CGPoint(x: toViewFinalFrame.midX, y: toViewFinalFrame.midY)
            } else {
                let scale = self.computeScaleAspectFit(containerSize: fromViewStartFrame.size, contentSize: self.media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)

                transitionView.frame.size = originMediaSize.applying(CGAffineTransform(scaleX: scale, y: scale))
                transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
                transitionViewFinalCenter = CGPoint(x: originFrame.midX, y: originFrame.midY)
            }

            transitionContext.containerView.addSubview(transitionView)

            UIView.animateKeyframes(withDuration: self.transitionDuration(using: nil), delay: 0, options: [], animations: {
                if self.presenting {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.8) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                        toView.alpha = 1.0
                    }
                } else {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.2) {
                        fromView.alpha = 0.0
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }
                }
            }) { [weak self] finished in
                guard let self = self else { return }
                let success = !transitionContext.transitionWasCancelled

                if (self.presenting && !success) || (!self.presenting && success) {
                    toView.removeFromSuperview()
                }

                transitionView.removeFromSuperview()

                transitionContext.completeTransition(success)
            }
        }
    }
}

extension UIImageView: MediaExplorerTransitionDelegate {
    func getTransitionView(atPostion index: Int) -> UIView? {
        return self
    }

    func scrollMediaToVisible(atPostion index: Int) {
    }
}
