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
        let controller = MediaExplorerController(media: message.orderedMedia, index: indexPath.row)
        controller.animatorDelegate = self

        present(controller, animated: true)
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
        guard let indexPath = collectionView.indexPathsForVisibleItems.min() else { return nil }

        let media = message.orderedMedia[indexPath.row]
        guard let url = media.mediaURL else { return nil }

        let index = MediaIndex(index: indexPath.row, chatMessageID: message.id)
        let animator = MediaListAnimator(presenting: false, media: url, with: media.type, and: media.size, at: index)
        animator.fromDelegate = self
        animator.toDelegate = animatorDelegate

        return animator
    }
}

// MARK: MediaListAnimatorDelegate
extension ChatMediaListViewController: MediaListAnimatorDelegate {

    func transitionDidBegin(presenting: Bool, with index: MediaIndex) {
        if !presenting {
            view.alpha = message.id == index.chatMessageID ? 1 : 0
        }
    }

    func transitionDidEnd(presenting: Bool, with index: MediaIndex) {
        if !presenting, message.id != index.chatMessageID {
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

    private static let mediaLoadingQueue = DispatchQueue(label: "com.halloapp.media-loading", qos: .userInitiated)

    var DefaultHeight: CGFloat { return 400 }

    private var mediaID: String = ""
    private var mediaType: CommonMediaType = .image
    private var cancellables: Set<AnyCancellable> = []

    private(set) lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.masksToBounds = true
        imageView.layer.cornerRadius = 10

        return imageView
    }()

    private lazy var videoIndicatorView: UIView = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 32)
        let image = UIImage(systemName: "play.fill", withConfiguration: imageConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        let indicatorView = UIImageView(image: image)
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.contentMode = .center
        indicatorView.isUserInteractionEnabled = false

        indicatorView.layer.shadowColor = UIColor.black.cgColor
        indicatorView.layer.shadowOffset = CGSize(width: 0, height: 1)
        indicatorView.layer.shadowOpacity = 0.3
        indicatorView.layer.shadowRadius = 4
        indicatorView.layer.shadowPath = UIBezierPath(ovalIn: indicatorView.bounds).cgPath

        indicatorView.isHidden = true

        return indicatorView
    }()

    private lazy var placeholderView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "photo")
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        imageView.contentMode = .center
        imageView.tintColor = .systemGray3

        imageView.isHidden = true

        return imageView
    }()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.barWidth = 2
        progressView.trackTintColor = .systemGray3

        progressView.isHidden = true

        return progressView
    }()

    private lazy var imageViewHeightConstraint: NSLayoutConstraint = {
        imageView.heightAnchor.constraint(equalToConstant: DefaultHeight)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageView)
        contentView.addSubview(videoIndicatorView)
        contentView.addSubview(placeholderView)
        contentView.addSubview(progressView)

        let imageViewBottomConstraint = imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        imageViewBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageViewBottomConstraint,
            imageViewHeightConstraint,
            videoIndicatorView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videoIndicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 72),
            progressView.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with media: CommonMedia) {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        mediaID = media.id
        mediaType = media.type

        let scale = contentView.bounds.width / CGFloat(media.width)
        imageViewHeightConstraint.constant = scale * CGFloat(media.height)

        if let url = media.mediaURL {
            load(url: url)
        } else {
            videoIndicatorView.isHidden = true
            progressView.isHidden = false
            placeholderView.isHidden = false
            imageView.image = nil
        }

        listenForDownloadProgress()
    }

    private func listenForDownloadProgress() {
        FeedDownloadManager.downloadProgress.receive(on: DispatchQueue.main).sink { [weak self] (id, progress) in
            guard let self = self else { return }
            guard id == self.mediaID else { return }

            self.progressView.progress = progress
        }.store(in: &cancellables)

        FeedDownloadManager.mediaDidBecomeAvailable.receive(on: DispatchQueue.main).sink { [weak self] (id, url) in
            guard let self = self else { return }
            guard id == self.mediaID else { return }

            self.load(url: url)
        }.store(in: &cancellables)
    }

    private func load(url: URL) {
        let id = mediaID
        let type = mediaType

        MediaCell.mediaLoadingQueue.async {
            let image: UIImage?
            switch type {
            case .image:
                image = UIImage(contentsOfFile: url.path)
            case .video:
                image = VideoUtils.videoPreviewImage(url: url)
            case .audio:
                return // only images and videos
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard id == self.mediaID else { return }

                self.progressView.isHidden = true
                self.placeholderView.isHidden = true
                self.videoIndicatorView.isHidden = type != .video
                self.imageView.image = image
            }
        }
    }
}
