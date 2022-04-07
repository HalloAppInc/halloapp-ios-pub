//
//  PostViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import Foundation
import Photos
import UIKit

class PostViewController: UIViewController, UserMenuHandler {

    private let post: FeedPostDisplayable

    private lazy var backBtn: UIView = {
        let background = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.1)
        background.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.masksToBounds = true
        background.layer.cornerRadius = 22

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(backAction), for: [.touchUpInside, .touchUpOutside])
        button.setImage(UIImage(named: "NavbarBack")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(background)
        container.addSubview(button)

        container.widthAnchor.constraint(equalToConstant: 44).isActive = true
        container.heightAnchor.constraint(equalToConstant: 44).isActive = true
        background.constrain(to: container)
        button.constrain(to: container)

        return container
    }()

    private lazy var backgroundView: UIView = {
        let view = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 0.1)
        view.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
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
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addGestureRecognizer(closingTapRecognizer)
        scrollView.delegate = self

        return scrollView
    }()

    init(post: FeedPostDisplayable) {
        self.post = post
        
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        view.backgroundColor = .clear
        view.addSubview(backgroundView)
        backgroundView.constrain(to: view)

        view.addSubview(backBtn)
        backBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2).isActive = true
        backBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true

        setupPostActions()

        scrollView.addSubview(postView)
        view.addSubview(scrollView)

        scrollView.contentInset = UIEdgeInsets(top: 52, left: 0, bottom: 0, right: 0)
        scrollView.constrain(to: view)

        postView.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        NSLayoutConstraint.activate([
            postView.widthAnchor.constraint(equalTo: view.widthAnchor),
            postView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            postView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            postView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 48),
            postView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

        let contentWidth = view.frame.width - view.layoutMargins.left - view.layoutMargins.right
        let gutterWidth = (1 - FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio) * view.layoutMargins.left
        postView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth, showGroupName: true, showArchivedDate: true)
        postView.isShowingFooter = false

        postView.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let post = post as? ExternalSharePost {
            post.downloadMedia()
        }
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

            if self.post.hasSaveablePostMedia && self.post.canSaveMedia {
                let saveMediaTitle = self.post.mediaCount > 1 ? Localizations.saveAllButton : Localizations.saveAllButtonSingular

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

            if self.post.canDeletePost {
                alert.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
                    self.deletePost()
                })
            }

            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil))

            self.present(alert, animated: true)
        }
        
        postView.contextAction = { [weak self] action in
            self?.handle(action: action)
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
        let media = post.feedMedia

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
        if scrollView.contentOffset.y < -100 {
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
