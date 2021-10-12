//
//  PostViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Foundation
import Photos
import UIKit

class PostViewController: UIViewController {

    private let post: FeedPost

    private lazy var backBtn: UIView = {
        let backBtn = UIButton(type: .custom)
        backBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)
        backBtn.addTarget(self, action: #selector(backAction), for: [.touchUpInside, .touchUpOutside])
        backBtn.setImage(UIImage(named: "NavbarBack")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        let container = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.1)
        container.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.masksToBounds = true
        container.layer.cornerRadius = 22

        container.widthAnchor.constraint(equalToConstant: 44).isActive = true
        container.heightAnchor.constraint(equalToConstant: 44).isActive = true

        container.contentView.addSubview(backBtn)
        backBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        backBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        backBtn.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        backBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true

        let wrapper = UIView()
        wrapper.widthAnchor.constraint(equalToConstant: 44).isActive = true
        wrapper.heightAnchor.constraint(equalToConstant: 44).isActive = true

        wrapper.addSubview(container)
        container.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor).isActive = true
        container.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor, constant: -18).isActive = true

        return wrapper
    }()

    private lazy var postView: FeedPostView = {
        let postView = FeedPostView()
        postView.translatesAutoresizingMaskIntoConstraints = false

        return postView
    }()

    private lazy var scrollView: UIScrollView = {
        let closingTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(backAction))
        closingTapRecognizer.delegate = self

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addGestureRecognizer(closingTapRecognizer)
        scrollView.delegate = self

        return scrollView
    }()

    init(post: FeedPost) {
        self.post = post
        
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func withNavigationController() -> UIViewController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .overFullScreen

        return controller
    }

    override func viewDidLoad() {
        view.backgroundColor = .black.withAlphaComponent(0.6)
        setupNavigation()
        setupPostActions()

        scrollView.addSubview(postView)
        view.addSubview(scrollView)

        scrollView.constrain(to: view)
        scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true
        scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: postView.heightAnchor, constant: 48).isActive = true
        scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor).isActive = true
        scrollView.contentLayoutGuide.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor).isActive = true

        let contentWidth = UIScreen.main.bounds.width - 16
        postView.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        postView.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor).isActive = true
        postView.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor).isActive = true

        postView.configure(with: post, contentWidth: contentWidth, gutterWidth: 8, showGroupName: true, displayData: nil)
        postView.setHeaderHeight(forPost: post, contentWidth: contentWidth)
        postView.isShowingFooter = false
        postView.delegate = self
    }

    private func setupNavigation() {
        navigationController?.navigationBar.standardAppearance = .transparentAppearance
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.backgroundColor = .clear

        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
    }

    @objc private func backAction() {
        dismiss(animated: true)
    }
}

// MARK: UIGestureRecognizerDelegate
extension PostViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // register the tap event only on itself but not on the subviews
        return touch.view == gestureRecognizer.view
    }
}

// MARK: Post Actions
extension PostViewController {
    private func setupPostActions() {
        postView.showUserAction = { [weak self] userId in
            guard let self = self else { return }
            self.present(UserFeedViewController(userId: userId), animated: true)
        }

        postView.showMoreAction = { [weak self] userId in
            guard let self = self else { return }

            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            if self.post.hasPostMedia && self.post.canSaveMedia {
                let saveMediaTitle = self.post.media?.count ?? 0 > 1 ? Localizations.saveAllButton : Localizations.saveAllButtonSingular

                alert.addAction(UIAlertAction(title: saveMediaTitle, style: .default, handler:  { _ in
                    PHPhotoLibrary.requestAuthorization { status in
                        switch status {
                        case .authorized, .limited:
                            self.saveMedia()
                        default:
                            self.mediaAuthorizationFailed()
                        }
                    }
                }))
            }

            if self.post.userId == MainAppContext.shared.userData.userId {
                alert.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
                    self.deletePost()
                })
            }

            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil))

            self.present(alert, animated: true)
        }
    }

    private func mediaAuthorizationFailed() {
        DispatchQueue.main.async {
            DDLogInfo("PostViewController/save-media: User denied photos permissions")

            let alert = UIAlertController(title: Localizations.mediaPermissionsError, message: Localizations.mediaPermissionsErrorDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))

            self.present(alert, animated: true)
        }
    }

    private func deletePost() {
        let alert = UIAlertController(title: nil, message: Localizations.deletePostConfirmationPrompt, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
            MainAppContext.shared.feedData.deletePosts(with: [self.post.id])
            self.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))

        self.present(alert, animated: true)
    }

    private func saveMedia() {
        // Get media from cache if available
        let media = MainAppContext.shared.feedData.media(for: post)

        guard media.first(where: { !$0.isMediaAvailable || $0.fileURL == nil }) == nil else {
            DDLogError("PostViewController/saveMedia/error: Missing media")
            return
        }

        PHPhotoLibrary.shared().performChanges({
            for item in media {
                guard let url = item.fileURL else { continue }

                if item.type == .image {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                } else if item.type == .video {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            }
        }, completionHandler: { [weak self] success, error in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if success {
                    self.mediaSaved()
                } else if let error = error {
                    DDLogError("PostViewController/saveMedia/error: Unable to save media [\(error)]")
                    self.mediaSaveFailed()
                }
            }
        })
    }

    private func mediaSaveFailed() {
        let alert = UIAlertController(title: Localizations.mediaSaveError, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))

        present(alert, animated: true)
    }

    private func mediaSaved() {
        let savedLabel = UILabel()
        savedLabel.translatesAutoresizingMaskIntoConstraints = false

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

        view.addSubview(savedLabel)
        savedLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        savedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22.5).isActive = true
        savedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22.5).isActive = true
        savedLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            savedLabel.removeFromSuperview()
        }
    }
}

// MARK: UIScrollViewDelegate
extension PostViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < -200 {
            dismiss(animated: true)
        }
    }
}

// MARK: FeedPostViewDelegate
extension PostViewController: FeedPostViewDelegate {
    func feedPostView(_ cell: FeedPostView, didRequestOpen url: URL) {
        DispatchQueue.main.async {
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
