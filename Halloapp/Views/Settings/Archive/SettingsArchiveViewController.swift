//
//  SettingsArchiveViewController.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/29/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import Combine

class SettingsArchiveViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    var feedDataSource = FeedDataSource(fetchRequest: FeedDataSource.archiveFeedRequest())
    
    var feedItems: [FeedPost] = []
    
    var collectionView: UICollectionView!
    
    var postFocusView = PostFocusView()
    
    private lazy var mosaicLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 2
        layout.minimumInteritemSpacing = 2
        let cellWidth = (UIScreen.main.bounds.width - 4) / 3.0
        layout.itemSize = CGSize(width: cellWidth, height: cellWidth)
        return layout
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .primaryBg
        
        title = Localizations.archiveNavigationTitle
        
        self.feedDataSource.itemsDidChange = { [weak self] items in
            DispatchQueue.main.async {
                self?.update(with: items.compactMap({ $0.post }))
            }
        }
        
        postFocusView.navigationController = navigationController
        
        view.addSubview(emptyPlaceholderView)
        emptyPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        emptyPlaceholderView.constrain(to: view)
        emptyPlaceholderView.isHidden = true
        
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: mosaicLayout)
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.constrain(to: view)
        collectionView.backgroundColor = .primaryBg
        collectionView.isHidden = true
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PostCollectionViewCell.self, forCellWithReuseIdentifier: PostCollectionViewCell.identifer)
        
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
    
    private lazy var emptyPlaceholderView: UIView = {
        let containerView = UIView()
        
        let imageView = UIImageView(image: UIImage(named: "archivePlaceholder")!)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .tertiarySystemFill
        
        let textLabel = UILabel()
        textLabel.text = NSLocalizedString("archive.empty.placeholder", value: "Your archived posts will appear here", comment: "Placeholder text for when the archive is empty")
        textLabel.textAlignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .tertiaryLabel
        
        containerView.addSubview(imageView)
        containerView.addSubview(textLabel)
        
        imageView.widthAnchor.constraint(equalToConstant: 55).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 55).isActive = true
        imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor).isActive = true
        
        textLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16).isActive = true
        textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
        
        return containerView
    }()
    
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
        
        postFocusView.removePostView()
        postFocusView.show(post: post)
    }
}

private class PostCollectionViewCell: UICollectionViewCell {
    static let mediaLoadingQueue = DispatchQueue(label: "archive.media.loading")
    static let identifer = "PostCollectionViewCell"

    var imageView = UIImageView()
    var labelView = UILabel()
    var feedPost: FeedPost?
    
    private var mediaLoadingCancellable: AnyCancellable?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.autoresizesSubviews = true
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        imageView.constrain(to: self)
        
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.clipsToBounds = true
        labelView.font = .systemFont(ofSize: 10)
        labelView.numberOfLines = 0
        addSubview(labelView)
        layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        labelView.constrain(to: self.layoutMarginsGuide)
        
        imageView.isHidden = true
        labelView.isHidden = true
        
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
        
        feedPost = nil
        mediaLoadingCancellable?.cancel()
    }
    
    func updateCell() {
        if let feedPost = feedPost {
            let media = MainAppContext.shared.feedData.media(for: feedPost)
            if let mediaToDisplay = media.first {
                if mediaToDisplay.isMediaAvailable, let imagePath = mediaToDisplay.fileURL {
                    if mediaToDisplay.type == .image {
                        let image = UIImage(contentsOfFile: imagePath.path)
                        imageView.image = image
                    } else if mediaToDisplay.type == .video {
                        let thumbnail = VideoUtils.videoPreviewImage(url: imagePath)
                        imageView.image = thumbnail
                    }
                } else {
                    if mediaToDisplay.type == .image {
                        mediaLoadingCancellable = mediaToDisplay.imageDidBecomeAvailable.sink(receiveValue: { image in
                            self.imageView.image = image
                        })
                        mediaToDisplay.loadImage()
                    }
                }
                
                imageView.isHidden = false
            } else {
                labelView.text = feedPost.text
                labelView.isHidden = false
            }
            
            Self.mediaLoadingQueue.async {
                for media in media {
                    media.loadImage()
                }
            }
        }
    }
}

private extension Localizations {
    static var archiveNavigationTitle: String {
        NSLocalizedString("archive.title.label", value: "Archive", comment: "Archive navigation label")
    }
}
