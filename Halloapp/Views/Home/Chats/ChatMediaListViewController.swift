//
//  ChatMediaListViewController.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 6.06.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import AVKit
import Combine
import Core
import Foundation
import UIKit

class ChatMediaListViewController: UIViewController {
    public weak var animatorDelegate: MediaListAnimatorDelegate?

    private let userID: String
    private let message: ChatMessage
    private let index: Int

    private var animator: MediaListAnimator?
    private var swipeExitRecognizer: SwipeToExitGestureRecognizer?

    init(userID: String, message: ChatMessage, index: Int) {
        self.userID = userID
        self.message = message
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

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .gothamFont(ofFixedSize: 16, weight: .medium)
        label.textColor = .primaryBlackWhite.withAlphaComponent(0.9)

        return label
    }()

    private lazy var titleView: UIStackView = {
        let imageConf = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let image = UIImage(systemName: "person", withConfiguration: imageConf)?.withTintColor(.primaryBlackWhite)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6

        return stack
    }()

    private lazy var collectionView: UICollectionView = {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(400))
        let item = NSCollectionLayoutItem(layoutSize: size)
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        group.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .none, top: .fixed(3), trailing: .none, bottom: .fixed(3))
        let section = NSCollectionLayoutSection(group: group)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        collectionView.delegate = self

        collectionView.register(MediaCell.self, forCellWithReuseIdentifier: MediaCell.reuseIdentifier)

        swipeExitRecognizer = SwipeToExitGestureRecognizer(direction: .horizontal, action: backAction)
        swipeExitRecognizer?.delegate = self
        collectionView.addGestureRecognizer(swipeExitRecognizer!)

        return collectionView
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Int> = {
        UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { [weak self]
            (collectionView: UICollectionView, indexPath: IndexPath, itemIdentifier: Int) -> UICollectionViewCell? in
            guard let self = self else { return nil }

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaCell.reuseIdentifier, for: indexPath) as? MediaCell
            cell?.configure(with: self.message.orderedMedia[itemIdentifier])

            return cell
        }
    }()

    private lazy var snapshot: NSDiffableDataSourceSnapshot<Int, Int> = {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([1])
        snapshot.appendItems(Array(0..<message.orderedMedia.count))

        return snapshot
    }()

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))

        return item
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        titleLabel.text = MainAppContext.shared.contactStore.fullName(for: userID, in: contactsViewContext)

        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem = leftBarButtonItem

        view.addSubview(collectionView)
        collectionView.constrain(to: view)

        collectionView.dataSource = dataSource
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    @objc private func backAction() {
        dismiss(animated: true)
    }
}

// MARK: UICollectionViewDelegate
extension ChatMediaListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let controller = MediaExplorerController(media: message.orderedMedia, index: indexPath.row, canSaveMedia: true, source: .chat)
        controller.animatorDelegate = self

        present(controller, animated: true)
    }
}

// MARK: UIGestureRecognizerDelegate
extension ChatMediaListViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if gestureRecognizer == swipeExitRecognizer {
            return true
        }

        return false
    }
}

// MARK: UIViewControllerTransitioningDelegate
extension ChatMediaListViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let media = message.orderedMedia[index]
        guard let url = media.mediaURL else { return nil }

        let index = MediaIndex(index: index, chatMessageID: message.id)
        let animator = MediaListAnimator(presenting: true, media: url, with: media.type, and: media.size, at: index)
        animator.fromDelegate = animatorDelegate
        animator.toDelegate = self

        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let indexPath: IndexPath? = {
            if let swipeExitRecognizer = swipeExitRecognizer, swipeExitRecognizer.inProgress {
                return collectionView.indexPathForItem(at: swipeExitRecognizer.start)
            } else {
                return collectionView.indexPathsForVisibleItems.min()
            }
        }()

        guard let indexPath = indexPath else { return nil }

        let media = message.orderedMedia[indexPath.row]
        guard let url = media.mediaURL else { return nil }

        let index = MediaIndex(index: indexPath.row, chatMessageID: message.id)
        animator = MediaListAnimator(presenting: false, media: url, with: media.type, and: media.size, at: index)
        animator?.fromDelegate = self
        animator?.toDelegate = animatorDelegate

        return animator
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let swipeExitRecognizer = swipeExitRecognizer else { return nil }

        if swipeExitRecognizer.inProgress {
            swipeExitRecognizer.animator = self.animator
            return self.animator
        } else {
            return nil
        }
    }
}

// MARK: MediaListAnimatorDelegate
extension ChatMediaListViewController: MediaListAnimatorDelegate {

    var transitionViewRadius: CGFloat {
        10
    }

    func transitionDidBegin(presenting: Bool, with index: MediaIndex) {
        if !presenting {
            view.alpha = message.id == index.chatMessageID ? 1 : 0
        }
    }

    func transitionDidEnd(presenting: Bool, with index: MediaIndex, success: Bool) {
        if !presenting, message.id != index.chatMessageID, success {
            dismiss(animated: false)
        }
    }

    func scrollToTransitionView(at index: MediaIndex) {
        if message.id == index.chatMessageID {
            collectionView.scrollToItem(at: IndexPath(row: index.index, section: 0), at: .centeredVertically, animated: false)
        } else {
            animatorDelegate?.scrollToTransitionView(at: index)
        }
    }

    func getTransitionView(at index: MediaIndex) -> UIView? {
        if message.id == index.chatMessageID {
            guard let cell = collectionView.cellForItem(at: IndexPath(row: index.index, section: 0)) as? MediaCell else { return nil }
            return cell.imageView
        } else {
            return animatorDelegate?.getTransitionView(at: index)
        }
    }
}

fileprivate class MediaCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: MediaCell.self)
    }

    var DefaultHeight: CGFloat { return 400 }

    private(set) lazy var imageView: MediaImageView = {
        let imageView = MediaImageView(configuration: .mediaList)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.masksToBounds = true
        imageView.layer.cornerRadius = 10

        return imageView
    }()

    private lazy var imageViewHeightConstraint: NSLayoutConstraint = {
        imageView.heightAnchor.constraint(equalToConstant: DefaultHeight)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageView)

        let imageViewBottomConstraint = imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        imageViewBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageViewBottomConstraint,
            imageViewHeightConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with media: CommonMedia) {
        let scale = contentView.bounds.width / CGFloat(media.width)
        imageViewHeightConstraint.constant = scale * CGFloat(media.height)

        imageView.configure(with: media)
    }
}
