//
//  SettingsArchiveViewController.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/29/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon
import Combine

class ArchiveViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    private var feedDataSource = FeedDataSource(
        fetchRequest: FeedDataSource.archiveFeedRequest(
            userID: MainAppContext.shared.userData.userId))
    private var feedItems: [FeedPost] = []

    private lazy var collectionView: UICollectionView = {
        let cellWidth = (UIScreen.main.bounds.width - 4) / 3.0

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 2
        layout.minimumInteritemSpacing = 2
        layout.itemSize = CGSize(width: cellWidth, height: cellWidth)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.isHidden = true
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PostCollectionViewCell.self, forCellWithReuseIdentifier: PostCollectionViewCell.identifer)

        return collectionView
    }()

    private lazy var emptyPlaceholderView: UIStackView = {
        let imageView = UIImageView(image: UIImage(named: "archivePlaceholder"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiarySystemFill
        
        let label = UILabel()
        label.text = Localizations.emptyStatePlaceholder
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .tertiaryLabel
        
        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 55),
            imageView.heightAnchor.constraint(equalToConstant: 55),
        ])
        
        return stack
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .primaryBg
        
        title = Localizations.archiveNavigationTitle
        
        feedDataSource.delegate = self
        feedDataSource.setup()
        
        view.addSubview(emptyPlaceholderView)
        emptyPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyPlaceholderView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            emptyPlaceholderView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyPlaceholderView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        view.addSubview(collectionView)
        collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        update(with: feedDataSource.displayItems.compactMap({ $0.post }))
    }
    
    private func update(with items: [FeedPost]) {
        guard items.count > 0 else {
            emptyPlaceholderView.isHidden = false
            collectionView.isHidden = true
            feedItems = items
            return
        }
        
        emptyPlaceholderView.isHidden = true
        collectionView.isHidden = false
        feedItems = items.filter({ post in
            if post.isPostRetracted {
                return false
            }
            
            return true
        })
        
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PostCollectionViewCell.identifer, for: indexPath) as? PostCollectionViewCell
            else { preconditionFailure("Failed to load collection view cell") }
        
        cell.feedPost = feedItems[indexPath.row]
        cell.updateCell()
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return feedItems.count
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? PostCollectionViewCell else { return }
        guard let post = cell.feedPost else { return }

        for media in MainAppContext.shared.feedData.media(for: post) {
            media.loadImage()
        }

        present(PostViewController.viewController(for: post), animated: true)
    }
}

// MARK: - FeedDataSourceDelegate methods

extension ArchiveViewController: FeedDataSourceDelegate {
    func itemsDidChange(_ items: [FeedDisplayItem]) {
        self.update(with: items.compactMap({ $0.post }))
    }
}

private class PostCollectionViewCell: UICollectionViewCell {
    static let mediaLoadingQueue = DispatchQueue(label: "archive.media.loading")
    static let identifer = "PostCollectionViewCell"

    var feedPost: FeedPost?
    private var imageView = UIImageView()
    private var labelView = UILabel()
    private lazy var multipleMediaIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 16)
        let image = UIImage(systemName: "square.fill.on.square.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let icon = UIImageView(image: image)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.transform = CGAffineTransform(rotationAngle: .pi)
        icon.layer.shadowColor = UIColor.black.cgColor
        icon.layer.shadowOpacity = 0.3

        return icon
    }()
    
    private var mediaLoadingCancellable: AnyCancellable?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.constrain(to: contentView)
        
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.clipsToBounds = true
        labelView.font = .systemFont(ofSize: 10)
        labelView.numberOfLines = 0
        contentView.addSubview(labelView)
        layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        labelView.constrain(to: contentView.layoutMarginsGuide)

        contentView.addSubview(multipleMediaIcon)
        multipleMediaIcon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5).isActive = true
        multipleMediaIcon.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -5).isActive = true
        
        imageView.isHidden = true
        labelView.isHidden = true
        multipleMediaIcon.isHidden = true
        
        backgroundColor = .archiveCellBackgroundPlaceholder
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()

        imageView.image = nil
        labelView.text = nil
        
        imageView.isHidden = true
        labelView.isHidden = true
        multipleMediaIcon.isHidden = true
        
        feedPost = nil
        mediaLoadingCancellable?.cancel()
    }

    private lazy var thumbnailWidth: CGFloat = {
        2 * ((UIScreen.main.bounds.width - 4) / 3.0)
    }()
    private lazy var thumbnailSize: CGSize = {
        CGSize(width: thumbnailWidth, height: thumbnailWidth)
    }()

    func updateCell() {
        guard let post = feedPost else { return }
        let media = MainAppContext.shared.feedData.media(for: post)

        if media.count > 0 {
            loadThumbnail(for: post, withMedia: media)
            imageView.isHidden = false
            multipleMediaIcon.isHidden = media.count < 2
        } else {
            labelView.text = post.rawText
            labelView.isHidden = false
        }
    }

    private func loadThumbnail(for post: FeedPost, withMedia media: [FeedMedia]) {
        guard let item = media.first else { return }
        guard let url = item.fileURL else { return }

        Self.mediaLoadingQueue.async { [weak self] in
            guard let self = self else { return }

            let thumbnail: UIImage?
            switch item.type {
            case .image:
                thumbnail = UIImage.thumbnail(contentsOf: url, maxPixelSize: self.thumbnailWidth)
            case .video:
                thumbnail = VideoUtils.videoPreviewImage(url: url, size: self.thumbnailSize)
            case .audio, .document:
                return
            }

            DispatchQueue.main.async {
                guard post.id == self.feedPost?.id else { return }
                self.imageView.image = thumbnail
            }
        }
    }
}

private extension Localizations {
    static var archiveNavigationTitle: String {
        NSLocalizedString("archive.title.label", value: "Archive", comment: "Archive navigation label")
    }

    static var emptyStatePlaceholder: String {
        NSLocalizedString("archive.empty.placeholder", value: "Your posts will be archived here after 30 days", comment: "Placeholder text for when the archive is empty")
    }
}
