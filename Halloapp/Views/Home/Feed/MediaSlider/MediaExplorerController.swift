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
    private var isTransition = false

    private var currentIndex: Int {
        didSet {
            if oldValue != currentIndex {
                pageControl?.currentPage = currentIndex

                let oldCell = collectionView.cellForItem(at: IndexPath(item: oldValue, section: 0))
                let currentCell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))

                if let cell = oldCell as? VideoCell {
                    cell.pause()
                } else if let cell = oldCell as? ImageCell {
                    cell.reset()
                }

                if let cell = currentCell as? VideoCell {
                    cell.resetVideoSize()
                    cell.play()
                } else if let cell = currentCell as? ImageCell {
                    cell.computeConstraints()
                    cell.reset()
                }
            }
        }
    }

    public weak var delegate: MediaExplorerTransitionDelegate?

    override var prefersStatusBarHidden: Bool {
        isSystemUIHidden
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

    func withNavigationController() -> UIViewController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .fullScreen
        controller.transitioningDelegate = self

        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.standardAppearance = .transparentAppearance
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.backgroundColor = .clear

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarBack"), style: .plain, target: self, action: #selector(backAction))

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

        let x = collectionView.frame.width * CGFloat(currentIndex)
        if abs(collectionView.contentOffset.x - x) > 0.01 {
            pageControl?.currentPage = currentIndex
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

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        isTransition = true

        super.viewWillTransition(to: size, with: coordinator)
        collectionView.collectionViewLayout.invalidateLayout()

        let indexPath = IndexPath(item: currentIndex, section: 0)
        coordinator.animate(alongsideTransition: { [weak self] context in
            guard let self = self else { return }

            if let cell = self.collectionView.cellForItem(at: indexPath) as? VideoCell {
                cell.resetVideoSize()
            } else if let cell = self.collectionView.cellForItem(at: indexPath) as? ImageCell {
                cell.computeConstraints()
                cell.reset()
            }
        }) { [weak self] context in
            guard let self = self else { return }
            self.isTransition = false
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
        pageControl.pageIndicatorTintColor = .white
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = media.count
        pageControl.layer.shadowColor = UIColor.black.cgColor
        pageControl.layer.shadowOpacity = 1
        pageControl.layer.shadowOffset = .zero
        pageControl.layer.shadowRadius = 0.3
        pageControl.addTarget(self, action: #selector(pageChangeAction), for: .valueChanged)

        return pageControl
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isTransition else { return }
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

        // Fade in/out animations on both status bar and navigation
        if isSystemUIHidden {
            UIView.animate(withDuration: 0.3, animations: {
                self.navigationController?.navigationBar.alpha = 0.0
            }, completion: { _ in
                self.navigationController?.setNavigationBarHidden(true, animated: true)
            })
        } else {
            self.navigationController?.setNavigationBarHidden(false, animated: true)
            self.navigationController?.navigationBar.alpha = 0.0

            UIView.animate(withDuration: 0.3, delay: Double(UINavigationController.hideShowBarDuration), options: [], animations: {
                self.navigationController?.navigationBar.alpha = 1.0
            }, completion: nil)
        }

        for cell in collectionView.visibleCells {
            if let cell = cell as? VideoCell {
                cell.isSystemUIHidden = isSystemUIHidden
            }
        }
    }

    @objc private func backAction() {
        delegate?.scrollMediaToVisible(atPostion: currentIndex)
        dismiss(animated: true)
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

fileprivate class ImageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static var reuseIdentifier: String {
        return String(describing: ImageCell.self)
    }

    private let spaceBetweenPages: CGFloat = 20

    public var scrollView: UIScrollView!

    private var originalOffset = CGPoint.zero
    private var imageConstraints: [NSLayoutConstraint] = []
    private var imageViewWidth: CGFloat = .zero
    private var imageViewHeight: CGFloat = .zero
    private var scale: CGFloat = 1
    private var animator: UIDynamicAnimator!

    private var width: CGFloat {
        imageViewWidth * scale
    }
    private var height: CGFloat {
        imageViewHeight * scale
    }
    private var minX: CGFloat {
        imageView.center.x - width / 2
    }
    private var maxX: CGFloat {
        imageView.center.x + width / 2
    }
    private var minY: CGFloat {
        imageView.center.y - height / 2
    }
    private var maxY: CGFloat {
        imageView.center.y + height / 2
    }


    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()


    var image: UIImage! {
        didSet {
            imageView.image = image
            reset()
            computeConstraints()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageView)
        contentView.clipsToBounds = true

        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onZoom(sender:)))
        imageView.addGestureRecognizer(zoomRecognizer)

        let dragRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onDrag(sender:)))
        dragRecognizer.delegate = self
        imageView.addGestureRecognizer(dragRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTapAction(sender:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        imageView.addGestureRecognizer(doubleTapRecognizer)

        animator = UIDynamicAnimator(referenceView: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func computeConstraints() {
        guard image != nil else { return }

        let scale = min((contentView.frame.width - spaceBetweenPages * 2) / image.size.width, contentView.frame.height / image.size.height)
        imageViewWidth = image.size.width * scale
        imageViewHeight = image.size.height * scale

        NSLayoutConstraint.deactivate(imageConstraints)
        imageConstraints = [
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: imageViewWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
        ]
        NSLayoutConstraint.activate(imageConstraints)
    }

    func reset() {
        imageView.transform = CGAffineTransform.identity
        imageView.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        scale = 1
        originalOffset = CGPoint.zero
        animator.removeAllBehaviors()
    }

    // perform zoom & drag simultaneously
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer.view == otherGestureRecognizer.view && otherGestureRecognizer is UIPinchGestureRecognizer
    }

    @objc func onZoom(sender: UIPinchGestureRecognizer) {
        if sender.state == .began {
            originalOffset = scrollView.contentOffset

            let temp = imageView.center
            animator.removeAllBehaviors()
            imageView.center = temp
        }

        if sender.state == .began || sender.state == .changed {
            guard sender.numberOfTouches > 1 else { return }

            let locations = [
                sender.location(ofTouch: 0, in: contentView),
                sender.location(ofTouch: 1, in: contentView),
            ]

            let zoomCenterX = (locations[0].x + locations[1].x) / 2
            let zoomCenterY = (locations[0].y + locations[1].y) / 2

            imageView.center.x += (zoomCenterX - imageView.center.x) * (1 - sender.scale)
            imageView.center.y += (zoomCenterY - imageView.center.y) * (1 - sender.scale)

            scale *= sender.scale
            imageView.transform = CGAffineTransform(scaleX: scale, y: scale)

            sender.scale = 1
        } else if sender.state == .ended {
            if scale < 1 {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
            } else {
                adjustImageView(scale: scale, center: imageView.center)
            }
        }
    }

    @objc func onDrag(sender: UIPanGestureRecognizer) {
        if sender.state == .began {
            originalOffset = scrollView.contentOffset

            let temp = imageView.center
            animator.removeAllBehaviors()
            imageView.center = temp
        }

        if sender.state == .began || sender.state == .changed {
            var translation = sender.translation(in: window)

            if scrollView.contentOffset.x == originalOffset.x {
                if translation.x > 0 && minX < spaceBetweenPages {
                    imageView.center.x += min(translation.x, spaceBetweenPages - minX)
                    translation.x = max(translation.x - spaceBetweenPages + minX, 0)
                } else if translation.x < 0 && maxX > contentView.bounds.maxX - spaceBetweenPages {
                    imageView.center.x += max(translation.x, contentView.bounds.maxX - spaceBetweenPages - maxX)
                    translation.x = min(translation.x - contentView.bounds.maxX + spaceBetweenPages + maxX, 0)
                }

                if translation.y > 0 && minY < 0 {
                    imageView.center.y += min(translation.y, -minY)
                    translation.y = max(translation.y + minY, 0)
                } else if translation.y < 0 && maxY > contentView.bounds.maxY {
                    imageView.center.y += max(translation.y, contentView.bounds.maxY - maxY)
                    translation.y = min(translation.y - contentView.bounds.maxY + maxY, 0)
                }
            }

            if translation.x != 0 {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translation.x, y: scrollView.contentOffset.y), animated: false)
            }

            sender.setTranslation(.zero, in: window)
        } else if sender.state == .ended {
            let velocity = sender.velocity(in: window)

            if shouldScrollPage(velocity: velocity.x) {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
                scrollPage(velocity: velocity.x)
            } else {
                if scale > 1 {
                    addInertialMotion(velocity: velocity)
                }

                scrollView.setContentOffset(originalOffset, animated: true)
            }
        }
    }

    @objc func onDoubleTapAction(sender: UITapGestureRecognizer) {
        let temp = imageView.center
        animator.removeAllBehaviors()
        imageView.center = temp

        let center: CGPoint

        if imageView.transform.isIdentity {
            let location = sender.location(in: contentView)
            scale = 2.5
            center = CGPoint(x: imageView.center.x + (contentView.bounds.midX - location.x) * scale,
                             y: imageView.center.y + (contentView.bounds.midY - location.y) * scale)
        } else {
            scale = 1
            center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        }

        adjustImageView(scale: scale, center: center)
    }

    private func adjustImageView(scale: CGFloat, center: CGPoint) {
        let width = imageViewWidth * scale
        let height = imageViewHeight * scale
        let minX = center.x - width / 2
        let maxX = center.x + width / 2
        let minY = center.y - height / 2
        let maxY = center.y + height / 2

        var x: CGFloat
        if width > bounds.width {
            x = center.x + max(contentView.bounds.maxX - spaceBetweenPages - maxX, 0) + min(contentView.bounds.minX + spaceBetweenPages - minX, 0)
        } else {
            x = contentView.bounds.midX
        }

        var y: CGFloat
        if height > bounds.height {
            y = center.y + max(contentView.bounds.maxY - maxY, 0) + min(contentView.bounds.minY - minY, 0)
        } else {
            y = contentView.bounds.midY
        }

        animate(scale: scale, center: CGPoint(x: x, y: y))
    }

    private func animate(scale: CGFloat, center: CGPoint) {
        UIView.animate(withDuration: 0.35) { [weak self] in
            guard let self = self else { return }
            self.imageView.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.imageView.center = center
        }
    }

    private func shouldScrollPage(velocity: CGFloat) -> Bool {
        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)
        if offset >= 0 && offset < scrollView.contentSize.width {
            let diff = scrollView.contentOffset.x - originalOffset.x
            return (abs(diff) > scrollView.frame.width / 2) || (abs(diff) > 0 && abs(velocity) > 200)
        }

        return false
    }

    private func scrollPage(velocity: CGFloat) {
        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)

        if offset >= 0 && offset < scrollView.contentSize.width {
            let distance = scrollView.contentOffset.x - offset
            let duration = min(TimeInterval(abs(distance / velocity)), 0.3)

            UIView.animate(withDuration: duration) {
                self.scrollView.setContentOffset(CGPoint(x: offset, y: self.originalOffset.y), animated: false)
                self.scrollView.layoutIfNeeded()
            }
        }
    }

    private func addInertialMotion(velocity: CGPoint) {
        var imageVelocity = CGPoint.zero
        let boundMinX: CGFloat, boundMaxX: CGFloat, boundMinY: CGFloat, boundMaxY: CGFloat

        // UICollisionBehavior doesn't take into account transform scaling
        if width > bounds.width {
            boundMinX = contentView.bounds.maxX - spaceBetweenPages - width / 2 - imageViewWidth / 2
            boundMaxX = contentView.bounds.minX + spaceBetweenPages + width / 2 + imageViewWidth / 2
            imageVelocity.x = velocity.x
        } else {
            boundMinX = contentView.bounds.midX - imageViewWidth / 2
            boundMaxX = contentView.bounds.midX + imageViewWidth / 2
        }

        // UICollisionBehavior doesn't take into account transform scaling
        if height > bounds.height {
            boundMinY = contentView.bounds.maxY - height / 2 - imageViewHeight / 2
            boundMaxY = contentView.bounds.minY + height / 2 + imageViewHeight / 2
            imageVelocity.y = velocity.y
        } else {
            boundMinY = contentView.bounds.midY - imageViewHeight / 2
            boundMaxY = contentView.bounds.midY + imageViewHeight / 2
        }

        let dynamicBehavior = UIDynamicItemBehavior(items: [imageView])
        dynamicBehavior.addLinearVelocity(imageVelocity, for: imageView)
        dynamicBehavior.resistance = 10

        // UIKit Dynamics resets the transform and ignores scale
        dynamicBehavior.action = { [weak self] in
            guard let self = self else { return }
            self.imageView.transform = CGAffineTransform(scaleX: self.scale, y: self.scale)
        }
        animator.addBehavior(dynamicBehavior)

        let boundaries = CGRect(x: boundMinX, y: boundMinY, width: boundMaxX - boundMinX, height: boundMaxY - boundMinY)
        let collisionBehavior = UICollisionBehavior(items: [imageView])
        collisionBehavior.addBoundary(withIdentifier: NSString("boundaries"), for: UIBezierPath(rect: boundaries))
        animator.addBehavior(collisionBehavior)
    }
}

fileprivate class VideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: VideoCell.self)
    }

    private let spaceBetweenPages: CGFloat = 20

    private var statusObservation: NSKeyValueObservation?
    private var videoBoundsObservation: NSKeyValueObservation?

    private lazy var playerController: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.view.backgroundColor = .clear
        controller.allowsPictureInPicturePlayback = false

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
        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
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

        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
        contentView.addSubview(playerController.view)
        videoBoundsObservation = playerController.observe(\.videoBounds) { controller, change in
            guard controller.videoBounds.size != .zero else { return }

            let bounds = controller.videoBounds
            let x = controller.view.frame.midX - bounds.width / 2
            let y = controller.view.frame.midY - bounds.height / 2

            controller.view.frame = CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetVideoSize() {
        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
    }

    func play(time: CMTime = .zero) {
        playerController.player?.seek(to: time)
        playerController.player?.play()
    }

    func pause() {
        playerController.player?.pause()
    }

    func currentTime() -> CMTime {
        guard let player = playerController.player else { return .zero }
        return player.currentTime()
    }

    func isPlaying() -> Bool {
        guard let player = playerController.player else { return false }
        return player.rate > 0
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
        return 0.7
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
              let fromController = transitionContext.viewController(forKey: .from)
        else {
            transitionContext.completeTransition(true)
            return
        }

        let toView = transitionContext.view(forKey: .to)
        if let view = toView {
            transitionContext.containerView.addSubview(view)
        }

        let fromView = transitionContext.view(forKey: .from)
        if let view = fromView, !presenting {
            transitionContext.containerView.addSubview(view)
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
                toView?.alpha = 0.0
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
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.4) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                        toView?.alpha = 1.0
                    }
                } else {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.6) {
                        fromView?.alpha = 0.0
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }
                }
            }) { [weak self] finished in
                guard let self = self else { return }
                let success = !transitionContext.transitionWasCancelled

                if self.presenting && !success {
                    toView?.removeFromSuperview()
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
