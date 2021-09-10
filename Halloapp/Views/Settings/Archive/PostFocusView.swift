//
//  PostFocusView.swift
//  HalloApp
//
//  Created by Matt Geimer on 8/6/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Photos
import Core
import CocoaLumberjackSwift

class PostFocusView {
    weak var navigationController: UINavigationController?
    
    func show(post: FeedPost) {
        let postView = FeedPostView()
        
        let contentWidth = UIScreen.main.bounds.width - 16
        postView.configure(with: post, contentWidth: contentWidth, gutterWidth: 8, showGroupName: false, displayData: nil)
        
        postView.translatesAutoresizingMaskIntoConstraints = false
        postView.delegate = self
        scrollView.addSubview(postView)
        scrollView.touchesShouldCancel(in: scrollView)
        scrollView.canCancelContentTouches = true
        
        postView.topAnchor.constraint(equalTo: scrollView.topAnchor).isActive = true
        postView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor).isActive = true
        postView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8).isActive = true
        postView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8).isActive = true
        postView.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width - 16).isActive = true
        
        postView.setHeaderHeight(forPost: post, contentWidth: contentWidth)
        
        postView.isShowingFooter = false
        
        self.postView = postView
        postView.contentViewDelegate = self
        configurePostButtonActions()
        
        shadowBox.isHidden = false
    }
    
    @objc func removePostView() {
        postView?.removeFromSuperview()
        shadowBox.isHidden = true
    }
    
    func removeShadowBox() {
        shadowBox.removeFromSuperview()
    }
    
    private var postView: UIView?
    
    private lazy var shadowBox: UIView = {
        let shadowBoxView = UIView()
        shadowBoxView.translatesAutoresizingMaskIntoConstraints = false

        let backgroundView = UIView()
        backgroundView.backgroundColor = .black
        backgroundView.alpha = 0.8
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        shadowBoxView.addSubview(backgroundView)
        backgroundView.constrain(to: shadowBoxView)
        
        scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(PostFocusView.removePostView)))
        
        shadowBoxView.addSubview(scrollView)
        scrollView.leadingAnchor.constraint(equalTo: shadowBoxView.leadingAnchor).isActive = true
        scrollView.trailingAnchor.constraint(equalTo: shadowBoxView.trailingAnchor).isActive = true
        scrollView.topAnchor.constraint(equalTo: shadowBoxView.topAnchor).isActive = true
        scrollView.bottomAnchor.constraint(equalTo: shadowBoxView.bottomAnchor).isActive = true
        scrollView.contentInset.top = 100
        scrollView.contentInset.bottom = 100
        
        if let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            keyWindow.addSubview(shadowBoxView)
            keyWindow.bringSubviewToFront(shadowBoxView)
            shadowBoxView.constrain(to: keyWindow)
        }
        
        return shadowBoxView
    }()
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isDirectionalLockEnabled = true
        return scrollView
    }()
    
    private func configurePostButtonActions() {
        guard let postView = postView as? FeedPostView,
              let postId = postView.postId,
              let post = MainAppContext.shared.feedData.feedPost(with: postId, archived: true)
        else { return }
        
        postView.showUserAction = { [weak self] userID in
            let userViewController = UserFeedViewController(userId: userID)
            self?.navigationController?.pushViewController(userViewController, animated: true)
        }
        
        postView.showMoreAction = { [weak self] userId in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            
            if post.canSaveMedia {
                let saveMediaTitle = post.media?.count ?? 0 > 1 ? Localizations.saveAllButton : Localizations.saveAllButtonSingular
                alert.addAction(UIAlertAction(title: saveMediaTitle, style: .default, handler:  { [weak self] _ in
                    PHPhotoLibrary.requestAuthorization { status in
                        // `.limited` was introduced in iOS 14, and only gives us partial access to the photo album. In this case we can still save to the camera roll
                        if #available(iOS 14, *) {
                            guard status == .authorized || status == .limited else {
                                DispatchQueue.main.async {
                                    self?.handleMediaAuthorizationFailure()
                                }
                                return
                            }
                        } else {
                            guard status == .authorized else {
                                DispatchQueue.main.async {
                                    self?.handleMediaAuthorizationFailure()
                                }
                                return
                            }
                        }
                        
                        guard let expectedMedia = post.media, let self = self else { return } // Get the media data to determine how many should be downloaded
                        let media = self.getMedia(feedPost: post) // Get the media from memory
                        
                        // Make sure the media in memory is the correct number or items
                        guard expectedMedia.count == media.count else {
                            DDLogError("FeedCollectionViewController/saveAllButton/error: Downloaded media not same size as expected")
                            return
                        }
                        
                        self.saveMedia(media: media)
                    }
                }))
            }
            
            if post.userId == MainAppContext.shared.userData.userId {
                let action = UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { [weak self] _ in
                    self?.handleDeletePostTapped(postId: postId)
                }
                alert.addAction(action)
            }
            
            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil))
            alert.view.tintColor = .systemBlue
            self.navigationController?.present(alert, animated: true)
        }
    }
    
    private func handleMediaAuthorizationFailure() {
        let alert = UIAlertController(title: Localizations.mediaPermissionsError, message: Localizations.mediaPermissionsErrorDescription, preferredStyle: .alert)
        
        DDLogInfo("FeedCollectionViewController/shareAllButtonPressed: User denied photos permissions")
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
        
        self.navigationController?.present(alert, animated: true)
    }
    
    private func getMedia(feedPost: FeedPost) -> [(type: FeedMediaType, url: URL)] {
        let feedMedia = MainAppContext.shared.feedData.media(for: feedPost)

        var mediaItems: [(type: FeedMediaType, url: URL)] = []
        
        for media in feedMedia {
            if media.isMediaAvailable, let url = media.fileURL {
                mediaItems.append((type: media.type, url: url))
            }
        }
        
        return mediaItems
    }
    
    private func saveMedia(media: [(type: FeedMediaType, url: URL)]) {
        PHPhotoLibrary.shared().performChanges({ [weak self] in
            for media in media {
                if media.type == .image {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: media.url)
                } else if media.type == .video {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: media.url)
                }
            }
            
            DispatchQueue.main.async {
                self?.mediaSaved()
            }
        }, completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                if !success {
                    self?.handleMediaSaveError(error: error)
                }
            }
        })
    }
    
    private func mediaSaved() {
        let savedLabel = UILabel()
        
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = UIImage(named: "CheckmarkLong")?.withTintColor(.white)

        let fullString = NSMutableAttributedString()
        fullString.append(NSAttributedString(attachment: imageAttachment))
        fullString.append(NSAttributedString(string: " ")) // Space between localized string for saved and checkmark
        fullString.append(NSAttributedString(string: Localizations.saveSuccessfulLabel))
        savedLabel.attributedText = fullString
        
        savedLabel.layer.cornerRadius = 13
        savedLabel.clipsToBounds = true
        savedLabel.textColor = .white
        savedLabel.backgroundColor = .primaryBlue
        savedLabel.textAlignment = .center
        
        shadowBox.addSubview(savedLabel)
        
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        savedLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        savedLabel.leadingAnchor.constraint(equalTo: shadowBox.leadingAnchor, constant: 22.5).isActive = true
        savedLabel.trailingAnchor.constraint(equalTo: shadowBox.trailingAnchor, constant: -22.5).isActive = true
        savedLabel.bottomAnchor.constraint(equalTo: shadowBox.bottomAnchor, constant: -100).isActive = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            savedLabel.removeFromSuperview()
        }
    }
    
    private func handleMediaSaveError(error: Error?) {
        let alert = UIAlertController(title: Localizations.mediaSaveError, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
        navigationController?.present(alert, animated: true)
    }
    
    private func handleDeletePostTapped(postId: FeedPostID) {
        let actionSheet = UIAlertController(title: nil, message: Localizations.deletePostConfirmationPrompt, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
            self.deletePost(postID: postId)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        actionSheet.view.tintColor = .systemBlue
        navigationController?.present(actionSheet, animated: true)
    }

    private func deletePost(postID: FeedPostID) {
        MainAppContext.shared.feedData.deletePosts(with: [postID])
        self.removePostView()
    }
}

extension PostFocusView: FeedPostViewDelegate {
    func feedPostView(_ cell: FeedPostView, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }
    
    func feedPostView(_ cell: FeedPostView, didChangeMediaIndex index: Int) {}
    
    func feedPostViewDidRequestTextExpansion(_ cell: FeedPostView, animations animationBlock: @escaping () -> Void) {
        UIView.animate(withDuration: 0.35) {
            animationBlock()
        }
    }
}

extension PostFocusView: FeedItemContentViewDelegate {
    func playMedia(media: [FeedMedia], index: Int?, delegate transitionDelegate: MediaExplorerTransitionDelegate?, canSaveMedia: Bool) {
        let explorerController = MediaExplorerController(media: media, index: index ?? 0, canSaveMedia: canSaveMedia)
        explorerController.delegate = transitionDelegate
        navigationController?.present(explorerController.withNavigationController(), animated: true)
    }
}
