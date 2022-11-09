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

class PostViewController: UIViewController, ShareMenuPresenter, UIViewControllerMediaSaving {

    private let post: FeedPost
    private let showFooter: Bool
    private var currentMediaIndex = 0

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
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.backgroundColor = .label.withAlphaComponent(0.3)
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
        scrollView.alwaysBounceVertical = true
        scrollView.addGestureRecognizer(closingTapRecognizer)
        scrollView.delegate = self

        return scrollView
    }()

    class func viewController(for post: FeedPost, showFooter: Bool = false) -> UIViewController {
        let navigationController = UINavigationController(rootViewController: PostViewController(post: post, showFooter: showFooter))
        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.modalTransitionStyle = .crossDissolve
        return navigationController
    }

    private init(post: FeedPost, showFooter: Bool = false) {
        self.post = post
        self.showFooter = showFooter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        view.backgroundColor = .clear
        view.addSubview(backgroundView)
        backgroundView.constrain(to: view)

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.compactAppearance = .transparentAppearance
        navigationItem.scrollEdgeAppearance = .transparentAppearance

        view.addSubview(scrollView)
        scrollView.constrain(to: view)

        if post.isMoment {
            let momentContainer = UIView()
            momentContainer.translatesAutoresizingMaskIntoConstraints = false

            let momentHeader = FeedItemHeaderView()
            momentHeader.configure(with: post, contentWidth: view.bounds.width, showGroupName: false)
            momentHeader.translatesAutoresizingMaskIntoConstraints = false
            let userID = post.userID
            momentHeader.showUserAction = { [weak self] in
                self?.navigationController?.pushViewController(UserFeedViewController(userId: userID), animated: true)
            }
            momentHeader.moreMenuContent = { [weak self] in
                self?.momentMoreMenu() ?? []
            }
            momentContainer.addSubview(momentHeader)

            let momentView = MomentView(configuration: .fullscreen)
            momentView.configure(with: post)
            momentView.translatesAutoresizingMaskIntoConstraints = false
            momentContainer.addSubview(momentView)

            let momentFacePile = FacePileView()
            momentFacePile.translatesAutoresizingMaskIntoConstraints = false
            momentFacePile.avatarViews.forEach { $0.borderColor = view.backgroundColor }
            momentFacePile.addTarget(self, action: #selector(openPostDashboard), for: .touchUpInside)
            momentContainer.addSubview(momentFacePile)

            let hideUtilityViews = post.userID != MainAppContext.shared.userData.userId
            momentFacePile.isHidden = hideUtilityViews
            momentHeader.moreButton.isHidden = hideUtilityViews

            scrollView.addSubview(momentContainer)
            momentContainer.constrain(to: scrollView.contentLayoutGuide)

            NSLayoutConstraint.activate([
                momentHeader.topAnchor.constraint(equalTo: momentContainer.topAnchor, constant: 8),
                momentHeader.leadingAnchor.constraint(equalTo: momentView.leadingAnchor, constant: 10),
                momentHeader.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -10),

                momentView.leadingAnchor.constraint(equalTo: momentContainer.leadingAnchor),
                momentView.trailingAnchor.constraint(equalTo: momentContainer.trailingAnchor),
                momentView.topAnchor.constraint(equalTo: momentHeader.bottomAnchor, constant: 8),

                momentFacePile.topAnchor.constraint(equalTo: momentView.bottomAnchor, constant: 15),
                momentFacePile.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -15),
                momentFacePile.leadingAnchor.constraint(greaterThanOrEqualTo: momentView.leadingAnchor),
                momentFacePile.bottomAnchor.constraint(equalTo: momentContainer.bottomAnchor),

                momentContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            ])
        } else {
            setupPostActions()

            postView.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
            scrollView.addSubview(postView)
            postView.constrain(to: scrollView.contentLayoutGuide)
            postView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).isActive = true

            let contentWidth = view.frame.width - view.layoutMargins.left - view.layoutMargins.right
            let gutterWidth = (1 - FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio) * view.layoutMargins.left
            postView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth, showGroupName: true, showArchivedDate: true)
            postView.isShowingFooter = showFooter

            postView.delegate = self
        }

        view.addSubview(backBtn)
        NSLayoutConstraint.activate([
            backBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            backBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Load downloaded images into memory.
        MainAppContext.shared.feedData.loadImages(postID: post.id)
        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [post])

        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Do not show the nav bar if we are being dismissed
        if !(navigationController?.isBeingDismissed ?? false) {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Vertically center post in scrollview
        guard let contentView = scrollView.subviews.first else {
            return
        }

        let scrollViewHeight = scrollView.frame.height
        let postHeight = contentView.bounds.height
        let safeAreaInsets = view.safeAreaInsets
        scrollView.contentInset.top = max(backBtn.frame.maxY, (scrollViewHeight - postHeight) * 0.5) - safeAreaInsets.top
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
extension PostViewController: UserActionHandler {
    @HAMenuContentBuilder
    private func moreMenu() -> HAMenu.Content {
        if post.hasSaveablePostMedia && post.canSaveMedia {
            let saveMediaTitle = post.mediaCount > 1 ? Localizations.saveAllButton : Localizations.saveAllButtonSingular
            HAMenuButton(title: saveMediaTitle) { [weak self] in
                self?.savePostMedia()
            }
        }

        if post.canDeletePost {
            HAMenuButton(title: Localizations.deletePostButtonTitle) { [weak self] in
                self?.deletePost()
            }.destructive()
        }
    }
    
    private func setupPostActions() {
        postView.showUserAction = { [weak self] userId in
            self?.navigationController?.pushViewController(UserFeedViewController(userId: userId), animated: true)
        }

        postView.moreMenuContent = { [weak self] in
            return self?.moreMenu() ?? []
        }
        
        postView.contextAction = { [weak self] action in
            self?.handle(action: action)
        }

        postView.shareAction = { [weak self] in
            guard let self = self else {
                return
            }
            self.presentShareMenu(for: self.post)
        }

        postView.commentAction = { [weak self] in
            guard let self = self else {
                return
            }
            self.navigationController?.pushViewController(FlatCommentsViewController(feedPostId: self.post.id), animated: true)
        }

        postView.showSeenByAction = { [weak self] in
            self?.openPostDashboard()
        }

        postView.messageAction = { [weak self] in
            guard let self = self else {
                return
            }
            if ServerProperties.newChatUI {
                let chatViewController = ChatViewControllerNew(for: self.post.userId,
                                                               with: self.post.id,
                                                               at: Int32(self.currentMediaIndex))
                self.navigationController?.pushViewController(chatViewController, animated: true)
            } else {
                let chatViewController = ChatViewController(for: self.post.userId,
                                                            with: self.post.id,
                                                            at: Int32(self.currentMediaIndex))
                self.navigationController?.pushViewController(chatViewController, animated: true)
            }
            
        }

        postView.showGroupFeedAction = { [weak self] groupID in
            guard let self = self, let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) else {
                return
            }
            self.navigationController?.pushViewController(GroupFeedViewController(group: group), animated: true)
        }

        let postID = post.id

        postView.retrySendingAction = {
            MainAppContext.shared.feedData.retryPosting(postId: postID)
        }

        postView.cancelSendingAction = {
            MainAppContext.shared.feedData.cancelMediaUpload(postId: postID)
        }

        postView.deleteAction = {
            MainAppContext.shared.feedData.deleteUnsentPost(postID: postID)
        }
    }

    @HAMenuContentBuilder
    private func momentMoreMenu() -> HAMenu.Content {
        HAMenu {
            if ServerProperties.enableMomentExternalShare, post.userID == MainAppContext.shared.userData.userId {
                HAMenuButton(title: Localizations.buttonShare, image: UIImage(systemName: "square.and.arrow.up")) { [weak self] in
                    guard let self = self else {
                        return
                    }
                    self.presentShareMenu(for: self.post)
                }
            }
            if post.hasSaveablePostMedia, post.canSaveMedia {
                HAMenuButton(title: Localizations.buttonSave, image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] in
                    self?.savePostMedia()
                }
            }
        }
        .displayInline()

        HAMenu {
            if post.canDeletePost {
                HAMenuButton(title: Localizations.deleteMomentButtonTitle, image: UIImage(systemName: "trash")) { [weak self] in
                    self?.deletePost()
                }
                .destructive()
            }
        }
        .displayInline()
    }

    private func deletePost() {
        let deleteButtonTitle =  post.isMoment ? Localizations.deleteMomentButtonTitle : Localizations.deletePostButtonTitle
        let alertMessage = post.isMoment ? Localizations.deleteMomentConfirmationPrompt : Localizations.deletePostConfirmationPrompt

        let alert = UIAlertController(title: nil, message: alertMessage,  preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: deleteButtonTitle, style: .destructive) { [weak self] _ in
            guard let post = self?.post else {
                return
            }
            // If the post is expired, delete it, otherwise, retract it
            if let expiration = post.expiration, expiration < Date() {
                MainAppContext.shared.feedData.deletePosts(with: [post.id])
            } else {
                MainAppContext.shared.feedData.retract(post: post)
            }
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))

        self.present(alert, animated: true)
    }

    private func savePostMedia() {
        Task {
            await saveMedia(source: .post(post.id)) { [weak self] in
                // Get media from cache if available
                guard let media = self?.post.feedMedia else {
                    return []
                }
                
                guard !media.contains(where: { !$0.isMediaAvailable || $0.fileURL == nil }) else {
                    DDLogError("PostViewController/saveMedia/error: Missing media")
                    return []
                }
                
                return media.compactMap { (item: FeedMedia) -> (type: CommonMediaType, url: URL)? in
                    guard let url = item.fileURL else { return nil }
                    return (item.type, url)
                }
            }
        }
    }

    @objc private func openPostDashboard() {
        let viewController = PostDashboardViewController(feedPost: post)
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

// MARK: UIScrollViewDelegate
extension PostViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < -scrollView.adjustedContentInset.top - 100 {
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

    func feedPostView(_ cell: FeedPostView, didChangeMediaIndex index: Int) {
        currentMediaIndex = index
    }

    func feedPostViewDidRequestTextExpansion(_ cell: FeedPostView, animations animationBlock: @escaping () -> Void) {
        UIView.animate(withDuration: 0.35) {
            animationBlock()
        }
    }
}

// MARK: PostDashboardViewControllerDelegate

extension PostViewController: PostDashboardViewControllerDelegate {

    func postDashboardViewController(didRequestPerformAction action: PostDashboardViewController.UserAction) {
        let actionToPerformOnDashboardDismiss: () -> ()
        switch action {
        case .profile(let userId):
            actionToPerformOnDashboardDismiss = {
                self.navigationController?.pushViewController(UserFeedViewController(userId: userId), animated: true)
            }

        case .message(let userId, let postId):
            actionToPerformOnDashboardDismiss = {
                if ServerProperties.newChatUI {
                    self.navigationController?.pushViewController(ChatViewControllerNew(for: userId, with: postId), animated: true)
                } else {
                    self.navigationController?.pushViewController(ChatViewController(for: userId, with: postId), animated: true)
                }
            }

        case .blacklist(let userId):
            actionToPerformOnDashboardDismiss = {
                MainAppContext.shared.privacySettings.hidePostsFrom(userId: userId)
            }
        }
        dismiss(animated: true, completion: actionToPerformOnDashboardDismiss)
    }
}
