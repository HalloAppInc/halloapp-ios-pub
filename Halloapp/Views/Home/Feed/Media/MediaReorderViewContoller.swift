//
//  MediaReorderViewContoller.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 4.08.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

class MediaReorderViewContoller: UIViewController {
    public weak var animatorDelegate: MediaListAnimatorDelegate?
    
    private(set) var media: [PendingMedia]
    private(set) var index: Int

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        layout.itemSize = CGSize(width: 125, height: 186)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(MediaCell.self, forCellWithReuseIdentifier: MediaCell.reuseIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self

        return collectionView
    }()

    init(media: [PendingMedia], index: Int) {
        self.media = media
        self.index = index

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func withNavigationController() -> UINavigationController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .overFullScreen
        controller.transitioningDelegate = self

        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Localizations.changeOrderTitle
        view.backgroundColor = .feedBackground
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            collectionView.widthAnchor.constraint(equalTo: view.widthAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 186),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        collectionView.beginInteractiveMovementForItem(at: IndexPath(row: index, section: 0))
    }

    public func move(using gesture: UIGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        collectionView.updateInteractiveMovementTargetPosition(CGPoint(x: location.x, y: collectionView.bounds.midY))
    }

    public func end() {
        collectionView.endInteractiveMovement()
    }
}

// MARK: MediaListAnimatorDelegate
extension MediaReorderViewContoller: MediaListAnimatorDelegate {
    var transitionViewRadius: CGFloat {
        20
    }

    func scrollToTransitionView(at index: MediaIndex) {
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: IndexPath(row: index.index, section: 0), at: .centeredHorizontally, animated: false)
    }

    func getTransitionView(at index: MediaIndex) -> UIView? {
        guard let cell = collectionView.cellForItem(at: IndexPath(row: index.index, section: 0)) as? MediaCell else { return nil }
        return cell.imageView
    }
}

// MARK: UICollectionViewDataSource
extension MediaReorderViewContoller: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaCell.reuseIdentifier, for: indexPath)
        guard let cell = cell as? MediaCell else { return cell }
        guard indexPath.row < media.count else { return cell }

        cell.configure(with: media[indexPath.row], highlight: index == indexPath.row)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        media.insert(media.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
        index = destinationIndexPath.row
    }
}

// MARK: UIViewControllerTransitioningDelegate
extension MediaReorderViewContoller: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard index < media.count else { return nil }
        guard media[index].ready.value else { return nil }
        guard let url = media[index].fileURL else { return nil }
        guard let size = media[index].size else { return nil }

        let animator = MediaListAnimator(presenting: true, media: url, with: media[index].type, and: size, at: MediaIndex(index: index))
        animator.fromDelegate = animatorDelegate
        animator.toDelegate = self

        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard index < media.count else { return nil }
        guard media[index].ready.value else { return nil }
        guard let url = media[index].fileURL else { return nil }
        guard let size = media[index].size else { return nil }


        let animator = MediaListAnimator(presenting: false, media: url, with: media[index].type, and: size, at: MediaIndex(index: index))
        animator.fromDelegate = self
        animator.toDelegate = animatorDelegate

        return animator
    }
}

fileprivate class MediaCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: MediaCell.self)
    }

    private(set) lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.masksToBounds = true
        imageView.layer.cornerRadius = 20

        return imageView
    }()

    private lazy var borderView: RoundedRectView = {
        let borderView = RoundedRectView()
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.fillColor = .clear
        borderView.strokeColor = UIColor.lavaOrange
        borderView.lineWidth = 2
        borderView.cornerRadius = 20

        return borderView
    }()

    private lazy var imageViewHeightConstraint: NSLayoutConstraint = {
        imageView.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var imageViewWidthConstraint: NSLayoutConstraint = {
        imageView.widthAnchor.constraint(equalToConstant: 0)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageView)
        contentView.addSubview(borderView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageViewHeightConstraint,
            imageViewWidthConstraint,
            borderView.topAnchor.constraint(equalTo: imageView.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with media: PendingMedia, highlight: Bool) {
        guard media.ready.value else { return }
        guard let size = media.size else { return }

        let scale = min(bounds.width / size.width, bounds.height / size.height)

        imageViewWidthConstraint.constant = size.width * scale
        imageViewHeightConstraint.constant = size.height * scale

        switch media.type {
        case .image:
            imageView.image = media.image
        case .video:
            guard let url = media.fileURL else { return }
            imageView.image = VideoUtils.videoPreviewImage(url: url, size: bounds.size)
        case .audio:
            break
        }

        borderView.isHidden = !highlight
    }
}

private extension Localizations {
    static var changeOrderTitle: String {
        NSLocalizedString("media.reorder.title", value: "Change Order", comment: "Title when changing media order")
    }
}
