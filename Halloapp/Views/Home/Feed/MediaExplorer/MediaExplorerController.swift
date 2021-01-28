//
//  MediaExplorerController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Core
import CoreData
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
    private var swipeExitRecognizer: UIPanGestureRecognizer!
    private var swipeExitInProgress = false
    private var isSystemUIHidden = false
    private var isTransition = false
    private var animator: MediaExplorerAnimator!
    private var fetchedResultsController: NSFetchedResultsController<ChatMedia>?

    private var currentIndex: Int {
        didSet {
            if oldValue != currentIndex {
                pageControl?.currentPage = currentIndex

                let oldCell = collectionView.cellForItem(at: IndexPath(item: oldValue, section: 0))
                let currentCell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))

                if let cell = oldCell as? MediaExplorerVideoCell {
                    cell.pause()
                } else if let cell = oldCell as? MediaExplorerImageCell {
                    cell.reset()
                }

                if let cell = currentCell as? MediaExplorerVideoCell {
                    cell.resetVideoSize()
                    cell.play()
                } else if let cell = currentCell as? MediaExplorerImageCell {
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

        self.currentIndex = computePosition(for: media[index])

        fetchedResultsController = makeFetchedResultsController(media[index])
        try? fetchedResultsController?.performFetch()
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

        view.backgroundColor = .black

        collectionView = makeCollectionView()
        self.view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: -spaceBetweenPages),
            collectionView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: spaceBetweenPages),
            collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        if media.count > 1 && fetchedResultsController == nil {
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

        if let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? MediaExplorerVideoCell {
            cell.play()
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

            if let cell = self.collectionView.cellForItem(at: indexPath) as? MediaExplorerVideoCell {
                cell.resetVideoSize()
            } else if let cell = self.collectionView.cellForItem(at: indexPath) as? MediaExplorerImageCell {
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

        swipeExitRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onSwipeExitAction(sender:)))
        swipeExitRecognizer.maximumNumberOfTouches = 1
        swipeExitRecognizer.delegate = self
        collectionView.addGestureRecognizer(swipeExitRecognizer)

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

    private func makeFetchedResultsController(_ media: ChatMedia) -> NSFetchedResultsController<ChatMedia> {
        let request: NSFetchRequest<ChatMedia> = ChatMedia.fetchRequest()
        request.fetchBatchSize = 5

        if let message = media.message {
            request.predicate = .init(format: "(message.fromUserId = %@ AND message.toUserId = %@) || (message.toUserId = %@ && message.fromUserId = %@)", message.fromUserId, message.toUserId, message.fromUserId, message.toUserId)
            request.sortDescriptors = [
                NSSortDescriptor(key: "message.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \ChatMedia.order, ascending: true),
            ]
        } else if let message = media.groupMessage {
            request.predicate = .init(format: "groupMessage.groupId = %@", message.groupId)
            request.sortDescriptors = [
                NSSortDescriptor(key: "groupMessage.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \ChatMedia.order, ascending: true),
            ]
        }

        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }

    private func computePosition(for media: ChatMedia) -> Int {
        let request: NSFetchRequest<ChatMedia> = ChatMedia.fetchRequest()

        if let message = media.message {
            request.predicate = .init(format: "((message.fromUserId = %@ AND message.toUserId = %@) || (message.toUserId = %@ && message.fromUserId = %@)) && message.timestamp < %@", message.fromUserId, message.toUserId, message.fromUserId, message.toUserId, message.timestamp! as NSDate)
            request.sortDescriptors = [
                NSSortDescriptor(key: "message.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \ChatMedia.order, ascending: true),
            ]
        } else if let message = media.groupMessage {
            request.predicate = .init(format: "groupMessage.groupId = %@ && groupMessage.timestamp < %@", message.groupId, message.timestamp! as NSDate)
            request.sortDescriptors = [
                NSSortDescriptor(key: "groupMessage.timestamp", ascending: true),
                NSSortDescriptor(keyPath: \ChatMedia.order, ascending: true),
            ]
        }

        let preceding = try? MainAppContext.shared.chatData.viewContext.count(for: request)

        return (preceding ?? 0) + media.index
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
            cell.image = item.image
            cell.scrollView = collectionView
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaExplorerVideoCell.reuseIdentifier, for: indexPath) as! MediaExplorerVideoCell
            cell.url = item.url
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }

    func explorerMedia(at index: Int) -> MediaExplorerMedia {
        return explorerMedia(at: IndexPath(item: index, section: 0))
    }

    func explorerMedia(at indexPath: IndexPath) -> MediaExplorerMedia {
        if let controller = fetchedResultsController {
            let chatMedia = controller.object(at: indexPath)
            let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(chatMedia.relativeFilePath ?? "", isDirectory: false)
            let image: UIImage? = chatMedia.type == .image ? UIImage(contentsOfFile: url.path) : nil
            return MediaExplorerMedia(url: url, image: image, type: (chatMedia.type == .image ? .image : .video), size: chatMedia.size)
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
            if let cell = cell as? MediaExplorerVideoCell {
                cell.isSystemUIHidden = isSystemUIHidden
            }
        }
    }

    @objc private func backAction() {
        let currentMedia = explorerMedia(at: currentIndex)
        let originalPosition = media.firstIndex { $0.url == currentMedia.url }

        if let position = originalPosition {
            delegate?.scrollMediaToVisible(atPostion: position)
        }

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

    @objc private func onSwipeExitAction(sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: sender.view)

        let startThreshold: CGFloat = 20
        let finishThreshold: CGFloat = 100

        switch sender.state {
        case .changed:
            let cell = collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))
            if let cell = cell as? MediaExplorerImageCell, cell.isZoomed {
                return
            }

            if !swipeExitInProgress && translation.y > startThreshold && translation.y > abs(translation.x) {
                sender.setTranslation(.zero, in: sender.view)
                swipeExitInProgress = true
                backAction()
            } else if swipeExitInProgress {
                animator.move(translation)
            }
        case .cancelled:
            guard swipeExitInProgress else { return }
            swipeExitInProgress = false
            animator.cancelInteractiveTransition()
        case .ended:
            guard swipeExitInProgress else { return }
            swipeExitInProgress = false

            if translation.x * translation.x + translation.y * translation.y > finishThreshold * finishThreshold {
                animator.finishInteractiveTransition()
            } else {
                animator.cancelInteractiveTransition()
            }
        default:
            break
        }
    }

    // MARK: UIViewControllerTransitioningDelegate

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        let currentMedia = explorerMedia(at: currentIndex)
        let originalPosition = media.firstIndex { $0.url == currentMedia.url }

        animator = MediaExplorerAnimator(media: currentMedia, between: originalPosition, and: currentIndex, presenting: true)
        animator.delegate = delegate
        animator.delegateExplorer = self

        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let currentMedia = explorerMedia(at: currentIndex)
        let originalPosition = media.firstIndex { $0.url == currentMedia.url }

        animator = MediaExplorerAnimator(media: currentMedia, between: originalPosition, and: currentIndex, presenting: false)
        animator.delegate = delegate
        animator.delegateExplorer = self

        return animator
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return swipeExitInProgress ? self.animator : nil
    }
}

extension MediaExplorerController: MediaExplorerTransitionDelegate {
    func getTransitionView(atPostion index: Int) -> UIView? {
        return collectionView.cellForItem(at: IndexPath(item: index, section: 0))
    }

    func scrollMediaToVisible(atPostion index: Int) {
    }

    func hideCollectionView() {
        collectionView.isHidden = true
    }

    func showCollectionView() {
        collectionView.isHidden = false
    }
}

enum MediaExplorerMediaType {
    case image, video
}

struct MediaExplorerMedia {
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

extension UIImageView: MediaExplorerTransitionDelegate {
    func getTransitionView(atPostion index: Int) -> UIView? {
        return self
    }

    func scrollMediaToVisible(atPostion index: Int) {
    }
}
