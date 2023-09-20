//
//  MediaExplorerController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import Core
import CoreCommon
import CoreData
import Foundation
import UIKit
import Photos
import CocoaLumberjackSwift

class MediaExplorerController : UIViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate, UIViewControllerMediaSaving {

    private let spaceBetweenPages: CGFloat = 20

    private var media: [MediaExplorerMedia]
    private var collectionView: UICollectionView!
    private var tapRecorgnizer: UITapGestureRecognizer!
    private var doubleTapRecorgnizer: UITapGestureRecognizer!
    private var swipeExitRecognizer: SwipeToExitGestureRecognizer!
    private var isSystemUIHidden = false
    private var isTransition = false
    private var animator: MediaListAnimator?
    private var fetchedResultsController: NSFetchedResultsController<CommonMedia>?
    private var canSaveMedia = false
    private var transitionHasFinished = false

    private var currentIndex: Int {
        didSet {
            if oldValue != currentIndex {
                if pageControlContainer.superview != nil {
                    pageControl.currentPage = currentIndex
                }

                let oldCell = collectionView.cellForItem(at: IndexPath(item: oldValue, section: 0))
                let currentCell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))

                if let cell = oldCell as? MediaExplorerImageCell {
                    cell.reset()
                } else if let cell = oldCell as? MediaExplorerVideoCell {
                    cell.pause()
                }

                if let cell = currentCell as? MediaExplorerVideoCell {
                    cell.play()
                } else if let cell = currentCell as? MediaExplorerImageCell {
                    cell.computeConstraints()
                    cell.reset()
                }
            }
        }
    }

    public weak var animatorDelegate: MediaListAnimatorDelegate?

    override var prefersStatusBarHidden: Bool {
        isSystemUIHidden
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        transitionHasFinished ? .all : .portrait
    }

    private lazy var backBtn: UIView = {
        var backButtonConfiguration: UIButton.Configuration = .plain()
        backButtonConfiguration.background.backgroundColor = .black.withAlphaComponent(0.7)
        backButtonConfiguration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        backButtonConfiguration.baseForegroundColor = .white
        backButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: -1, bottom: 0, trailing: 0)
        backButtonConfiguration.cornerStyle = .capsule
        backButtonConfiguration.image = UIImage(named: "NavbarBack")?.withRenderingMode(.alwaysTemplate)

        let backBtn = LargeHitButton(type: .custom)
        backBtn.configuration = backButtonConfiguration
        backBtn.targetIncrease = 16
        backBtn.addTarget(self, action: #selector(backAction), for: [.touchUpInside, .touchUpOutside])
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backBtn.widthAnchor.constraint(equalToConstant: 44),
            backBtn.heightAnchor.constraint(equalToConstant: 44),
        ])

        return backBtn
    }()

    private lazy var shareBtn: UIView = {
        var shareButtonConfiguration: UIButton.Configuration = .plain()
        shareButtonConfiguration.background.backgroundColor = .black.withAlphaComponent(0.7)
        shareButtonConfiguration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        shareButtonConfiguration.baseForegroundColor = .white
        shareButtonConfiguration.cornerStyle = .capsule
        shareButtonConfiguration.image = UIImage(named: "Download")?.withRenderingMode(.alwaysTemplate)

        let shareBtn = LargeHitButton(type: .custom)
        shareBtn.configuration = shareButtonConfiguration
        shareBtn.targetIncrease = 16
        shareBtn.addTarget(self, action: #selector(shareButtonPressed), for: [.touchUpInside, .touchUpOutside])
        shareBtn.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            shareBtn.widthAnchor.constraint(equalToConstant: 44),
            shareBtn.heightAnchor.constraint(equalToConstant: 44),
        ])

        return shareBtn
    }()

    private lazy var slideshowButton: UIView = {
        var slideshowButtonConfiguration: UIButton.Configuration = .plain()
        slideshowButtonConfiguration.background.backgroundColor = .black.withAlphaComponent(0.7)
        slideshowButtonConfiguration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        slideshowButtonConfiguration.baseForegroundColor = .white
        slideshowButtonConfiguration.cornerStyle = .capsule
        slideshowButtonConfiguration.image = UIImage(systemName: "play.rectangle.fill")?.withRenderingMode(.alwaysTemplate)

        let slideshowButton = LargeHitButton(type: .custom)
        slideshowButton.configuration = slideshowButtonConfiguration
        slideshowButton.targetIncrease = 16
        slideshowButton.addTarget(self, action: #selector(openSlideshow), for: [.touchUpInside])
        slideshowButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            slideshowButton.widthAnchor.constraint(equalToConstant: 44),
            slideshowButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        return slideshowButton
    }()

    @objc private func openSlideshow() {
        let slideshowViewController = SlideshowViewController(media: feedMedia ?? [])        
        slideshowViewController.modalPresentationStyle = .fullScreen
        present(slideshowViewController, animated: true)
    }

    private lazy var navigationView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let arrangedSubviews: [UIView]
        if ServerProperties.isInternalUser, feedMedia != nil {
            arrangedSubviews = [backBtn, spacer, slideshowButton, shareBtn]
        } else {
            arrangedSubviews = [backBtn, spacer, shareBtn]
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 4)

        return stack
    }()

    private lazy var pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = UIColor.lavaOrange.withAlphaComponent(0.7)
        pageControl.pageIndicatorTintColor = .white
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = media.count
        pageControl.addTarget(self, action: #selector(pageChangeAction), for: .valueChanged)

        return pageControl
    }()

    private lazy var pageControlContainer: UIView = {
        let container = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.1)
        container.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.masksToBounds = true
        container.layer.cornerRadius = 14

        container.contentView.addSubview(pageControl)
        pageControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -24).isActive = true
        pageControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 24).isActive = true
        pageControl.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        pageControl.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true

        return container
    }()

    private var source: MediaItemSource = .unknown

    // maintain original media structures for slideshow
    private var feedMedia: [FeedMedia]?

    init(media: [FeedMedia], index: Int, canSaveMedia: Bool, source: MediaItemSource) {
        self.feedMedia = media
        self.media = media.filter({ $0.type != .audio }).map { item in
            let viewContext = MainAppContext.shared.feedData.viewContext
            let progress = MainAppContext.shared.feedData.downloadTask(for: item, using: viewContext)?.downloadProgress.eraseToAnyPublisher()

            var update: AnyPublisher<(URL?, UIImage?, CGSize), Never>?
            switch(item.type) {
            case .image:
                update = item.imageDidBecomeAvailable.map { _ in (item.fileURL, item.image, item.size) }.eraseToAnyPublisher()
            case .video:
                update = item.videoDidBecomeAvailable.map { _ in (item.fileURL, item.image, item.size) }.eraseToAnyPublisher()
            case .audio:
                fatalError("audio is not supported in fullscreen")
            case .document:
                fatalError("documents are not supported in fullscreen")
            }

            return MediaExplorerMedia(
                url: item.fileURL,
                image: item.image,
                type: item.type,
                size: item.size,
                order: item.order,
                chunkedInfo: item.chunkedInfo,
                update: update,
                progress: progress)
        }
        self.currentIndex = index
        self.canSaveMedia = canSaveMedia
        self.source = source

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self
    }

    init(media: [CommonMedia], index: Int, canSaveMedia: Bool, source: MediaItemSource) {
        self.media = media.map { MediaExplorerMedia(media: $0) }
        self.source = source
        self.currentIndex = index
        self.canSaveMedia = canSaveMedia

        super.init(nibName: nil, bundle: nil)

        if case .chat = source, media.count > index, media[index].message != nil {
            self.currentIndex = computePosition(for: media[index])

            fetchedResultsController = makeFetchedResultsController(media[index])
            fetchedResultsController?.delegate = self
            try? fetchedResultsController?.performFetch()
        }

        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self
    }

    init(imagePublisher: AnyPublisher<(URL?, UIImage?, CGSize), Never>, progress: AnyPublisher<Float, Never>? = nil) {
        let imageMedia = MediaExplorerMedia(type: .image, size: .zero, update: imagePublisher, progress: progress)
        self.media = [imageMedia]
        self.currentIndex = 0
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        shareBtn.isHidden = !canSaveMedia

        collectionView = makeCollectionView()
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: -spaceBetweenPages),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: spaceBetweenPages),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        view.addSubview(navigationView)
        navigationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        navigationView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        navigationView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        navigationView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        if media.count > 1 && fetchedResultsController == nil {
            view.addSubview(pageControlContainer)
            pageControlContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
            pageControlContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        }
    }
    
    @objc func shareButtonPressed() {
        Task {
            await saveMedia(source: source) {
                let media = self.explorerMedia(at: currentIndex)
                guard let url = media.url else { return [] }
                return [(media.type, url)]
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let x = collectionView.frame.width * CGFloat(currentIndex)
        if abs(collectionView.contentOffset.x - x) > 0.01 {
            if pageControlContainer.superview != nil {
                pageControl.currentPage = currentIndex
            }

            collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        transitionHasFinished = true

        if let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? MediaExplorerVideoCell {
            cell.play(time: animatorDelegate?.timeForVideo(at: MediaIndex(index: currentIndex)) ?? .zero)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        for cell in collectionView.visibleCells {
            if let cell = cell as? MediaExplorerVideoCell {
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

            if let cell = self.collectionView.cellForItem(at: indexPath) as? MediaExplorerImageCell {
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
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isPagingEnabled = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInsetAdjustmentBehavior = .never

        collectionView.register(MediaExplorerImageCell.self, forCellWithReuseIdentifier: MediaExplorerImageCell.reuseIdentifier)
        collectionView.register(MediaExplorerVideoCell.self, forCellWithReuseIdentifier: MediaExplorerVideoCell.reuseIdentifier)
        
        collectionView.dataSource = self
        collectionView.delegate = self

        tapRecorgnizer = UITapGestureRecognizer(target: self, action: #selector(onTapAction(sender:)))
        tapRecorgnizer.delegate = self
        collectionView.addGestureRecognizer(tapRecorgnizer)

        doubleTapRecorgnizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTapAction(sender:)))
        doubleTapRecorgnizer.numberOfTapsRequired = 2
        doubleTapRecorgnizer.delegate = self
        collectionView.addGestureRecognizer(doubleTapRecorgnizer)

        swipeExitRecognizer = SwipeToExitGestureRecognizer(direction: .vertical, action: backAction)
        swipeExitRecognizer.delegate = self
        collectionView.addGestureRecognizer(swipeExitRecognizer)

        return collectionView
    }

    private func request(with media: CommonMedia, limitToMessage: Bool = false) -> NSFetchRequest<CommonMedia> {
        let request: NSFetchRequest<CommonMedia> = CommonMedia.fetchRequest()

        if let message = media.message, let toUserId = message.toUserId {
            let base = """
                ((message.fromUserID = %@ AND message.toUserID = %@) || (message.toUserID = %@ && message.fromUserID = %@)) &&
                (typeValue == %d || typeValue == %d)
            """

            if limitToMessage {
                // TODO: Use compound predicate instead of concatenating query strings
                request.predicate = NSPredicate(format: base + " && message.timestamp < %@", message.fromUserId, toUserId, message.fromUserId, toUserId, CommonMediaType.image.rawValue, CommonMediaType.video.rawValue, message.timestamp! as NSDate)
            } else {
                request.predicate = NSPredicate(format: base, message.fromUserId, toUserId, message.fromUserId, toUserId, CommonMediaType.image.rawValue, CommonMediaType.video.rawValue)
            }

            request.sortDescriptors = [
                NSSortDescriptor(key: "message.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \CommonMedia.order, ascending: true),
            ]
        } else if let message = media.message, let toGroupId = message.toGroupID, let timestamp = message.timestamp {
            let base = """
                message.toGroupID = %@ && (typeValue == %d || typeValue == %d)
            """

            if limitToMessage {
                // TODO: Use compound predicate instead of concatenating query strings
                request.predicate = NSPredicate(format: base + " && message.timestamp < %@", toGroupId, CommonMediaType.image.rawValue, CommonMediaType.video.rawValue, timestamp as NSDate)
            } else {
                request.predicate = NSPredicate(format: base, toGroupId, CommonMediaType.image.rawValue, CommonMediaType.video.rawValue)
            }

            request.sortDescriptors = [
                NSSortDescriptor(key: "message.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \CommonMedia.order, ascending: true),
            ]
        }

        return request
    }

    private func makeFetchedResultsController(_ media: CommonMedia) -> NSFetchedResultsController<CommonMedia> {
        let request = request(with: media)
        request.fetchBatchSize = 5

        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }

    private func computePosition(for media: CommonMedia) -> Int {
        let request = request(with: media, limitToMessage: true)
        let preceding = try? MainAppContext.shared.chatData.viewContext.count(for: request)

        return (preceding ?? 0) + max(0, media.index)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isTransition else { return }

        let rem = scrollView.contentOffset.x.truncatingRemainder(dividingBy: scrollView.frame.width)

        if rem == 0 {
            currentIndex = Int(scrollView.contentOffset.x / scrollView.frame.width)
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return fetchedResultsController?.sections?.count ?? 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchedResultsController?.sections?[section].numberOfObjects ?? media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = explorerMedia(at: indexPath)

        switch item.type {
        case .image:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaExplorerImageCell.reuseIdentifier, for: indexPath) as! MediaExplorerImageCell
            cell.scrollView = collectionView
            cell.media = item
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaExplorerVideoCell.reuseIdentifier, for: indexPath) as! MediaExplorerVideoCell
            cell.scrollView = collectionView
            cell.media = item
            return cell
        case .audio:
            fatalError("audio is not supported in fullscreen")
        case .document:
            fatalError("documents are not supported in fullscreen")
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? MediaExplorerVideoCell {
            cell.pause()
        }
    }

    func explorerMedia(at index: Int) -> MediaExplorerMedia {
        return explorerMedia(at: IndexPath(item: index, section: 0))
    }

    func explorerMedia(at indexPath: IndexPath) -> MediaExplorerMedia {
        if let controller = fetchedResultsController {
            return MediaExplorerMedia(media: controller.object(at: indexPath))
        } else {
            return media[indexPath.item]
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tapRecorgnizer {
            if let other = otherGestureRecognizer as? UITapGestureRecognizer {
                return other.numberOfTapsRequired == 1
            }
        }

        if gestureRecognizer == swipeExitRecognizer {
            return true
        }

        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == doubleTapRecorgnizer, let other = otherGestureRecognizer as? UITapGestureRecognizer {
            return other.numberOfTapsRequired == 1
        }

        return false
    }

    private func toggleSystemUI() {
        isSystemUIHidden = !isSystemUIHidden

        navigationView.alpha = isSystemUIHidden ? 1 : 0
        pageControlContainer.alpha = isSystemUIHidden ? 1 : 0

        UIView.animate(withDuration: 0.3) {
            self.navigationView.alpha = self.isSystemUIHidden ? 0 : 1
            self.pageControlContainer.alpha = self.isSystemUIHidden ? 0 : 1
            self.setNeedsStatusBarAppearanceUpdate()
        }

        for cell in collectionView.visibleCells {
            if let cell = cell as? MediaExplorerVideoCell {
                cell.isSystemUIHidden = isSystemUIHidden
            }
        }
    }

    @objc private func backAction() {
        dismiss(animated: true)
    }

    @objc private func pageChangeAction() {
        if pageControlContainer.superview != nil, currentIndex != pageControl.currentPage {
            let x = collectionView.frame.width * CGFloat(pageControl.currentPage)
            collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: true)
        }
    }

    @objc private func onTapAction(sender: UITapGestureRecognizer) {
        toggleSystemUI()
    }

    @objc private func onDoubleTapAction(sender: UITapGestureRecognizer) {
        let indexPath = IndexPath(item: currentIndex, section: 0)

        if let cell = collectionView.cellForItem(at: indexPath) as? MediaExplorerVideoCell {
            cell.togglePlay()
        }
    }

    // MARK: UIViewControllerTransitioningDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == swipeExitRecognizer {
            let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))
            if let cell = cell as? MediaExplorerImageCell, cell.isZoomed {
                return false
            }
        }

        return true
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        let currentMedia = explorerMedia(at: currentIndex)
        guard let url = currentMedia.url else { return nil }

        let index = MediaIndex(index: currentMedia.order, chatMessageID: currentMedia.chatMessageID)

        animator = MediaListAnimator(presenting: true, media: url, with: currentMedia.type, and: currentMedia.size, at: index)
        animator?.fromDelegate = animatorDelegate
        animator?.toDelegate = self

        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let currentMedia = explorerMedia(at: currentIndex)
        guard let url = currentMedia.url else { return nil }

        let index = MediaIndex(index: currentMedia.order, chatMessageID: currentMedia.chatMessageID)

        animator = MediaListAnimator(presenting: false, media: url, with: currentMedia.type, and: currentMedia.size, at: index)
        animator?.fromDelegate = self
        animator?.toDelegate = animatorDelegate

        return animator
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        if swipeExitRecognizer.inProgress {
            swipeExitRecognizer.animator = self.animator
            return self.animator
        } else {
            return nil
        }
    }
}

extension MediaExplorerController: MediaListAnimatorDelegate {
    func getTransitionView(at index: MediaIndex) -> UIView? {
        // in fullscreen, the only visible view is the one currently displayed
        let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))

        if let imageCell = cell as? MediaExplorerImageCell {
            return imageCell.imageView
        } else if let videoCell = cell as? MediaExplorerVideoCell {
            return videoCell.video
        }

        return nil
    }

    func scrollToTransitionView(at index: MediaIndex) {
        // on entering transition the currentIndex is set in the init function
        collectionView.scrollToItem(at: IndexPath(row: currentIndex, section: 0), at: .centeredHorizontally, animated: false)
    }

    func transitionDidEnd(presenting: Bool, with index: MediaIndex, success: Bool) {
        if !success, !presenting {
            // Restore collectionView position in place.
            // It alsp prevents brisk diagonal movements to activate collectionView swipe
            // while swipe exit is in progress
            let x = collectionView.frame.width * CGFloat(currentIndex)
            collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: false)
        }
    }
}

// MARK: NSFetchedResultsControllerDelegate
extension MediaExplorerController: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard let chatMedia = anObject as? CommonMedia else { return }

        MediaExplorerMedia.updated.send(chatMedia)
    }
}

class MediaExplorerMedia {
    static let updated = PassthroughSubject<CommonMedia, Never>()

    var url: URL?
    var image: UIImage?
    var type: CommonMediaType
    var size: CGSize
    var ready = CurrentValueSubject<Bool, Never>(false)
    var progress = CurrentValueSubject<Float, Never>(0)
    var chunkedInfo: ChunkedMediaInfo?
    var chatMessageID: ChatMessageID?
    var order: Int

    private var updateCancellable: AnyCancellable?
    private var progressCancellable: AnyCancellable?

    init(url: URL? = nil, image: UIImage? = nil, type: CommonMediaType, size: CGSize, order: Int = 0, chunkedInfo: ChunkedMediaInfo? = nil, update: AnyPublisher<(URL?, UIImage?, CGSize), Never>? = nil, progress: AnyPublisher<Float, Never>? = nil) {
        self.url = url
        self.image = image
        self.type = type
        self.size = size
        self.order = order
        self.chunkedInfo = chunkedInfo

        listen(update: update, progress: progress)
    }

    init(media: CommonMedia) {
        let mediaID = media.id

        url = media.mediaURL
        type = media.type
        size = media.size
        order = Int(media.order)
        chunkedInfo = ChunkedMediaInfo(commonMedia: media)

        if media.type == .image, let url = media.mediaURL {
            image = UIImage(contentsOfFile: url.path)
        }

        if let message = media.message {
            chatMessageID = message.id
        }

        let update = MediaExplorerMedia.updated
            .filter { $0.id == mediaID }
            .map { (media: CommonMedia) -> (URL?, UIImage?, CGSize) in
                var image: UIImage?
                if media.type == .image, let url = media.mediaURL {
                    image = UIImage(contentsOfFile: url.path)
                }

                return (media.mediaURL, image, media.size)
            }
            .eraseToAnyPublisher()

        let progress = FeedDownloadManager.downloadProgress
            .filter { id, _ in mediaID == id }
            .map { _, progress in progress }
            .eraseToAnyPublisher()

        listen(update: update, progress: progress)
    }

    private func listen(update: AnyPublisher<(URL?, UIImage?, CGSize), Never>?, progress: AnyPublisher<Float, Never>?) {
        if (type == .video && url == nil) || (type == .image && image == nil) {
            updateCancellable = update?.sink { [weak self] url, image, size in
                guard let self = self else { return }
                self.url = url
                self.image = image
                self.size = size
                self.ready.send(true)
            }

            progressCancellable = progress?.sink { [weak self] value in
                guard let self = self else { return }
                self.progress.send(value)
            }
        } else {
            self.ready.send(true)
            self.progress.send(1)
        }
    }

    func computeSize() {
        guard size == .zero else { return }

        if let image = image {
            size = image.size
        }

        if let url = url, type == .video, let videoSize = VideoUtils.resolutionForLocalVideo(url: url) {
            size = videoSize
        }
    }
}

extension Localizations {
    
    static var saveSuccessfulLabel: String {
        return NSLocalizedString("media.save.saved", value: "Saved to Camera Roll", comment: "Label indicating that media was successfully saved to the camera roll")
    }
    
    static var mediaSaveError: String {
        return NSLocalizedString("media.save.not.saved", value: "Photo could not be saved", comment: "Alert displayed explaining to the user that the media save operation failed")
    }
    
    static var mediaPermissionsError: String {
        return NSLocalizedString("media.save.needs.permissions", value: "Needs photos permissions", comment: "Alert title telling the user that the photos couldn't be saved due to camera role privacy settings")
    }
    
    static var mediaPermissionsErrorDescription: String {
        return NSLocalizedString("media.save.no.access", value: "Photos cannot be saved without access to the camera roll.", comment: "Description telling the user why the photos couldn't be saved")
    }
}
