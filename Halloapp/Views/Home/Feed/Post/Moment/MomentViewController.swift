//
//  SecretPostViewController.swift
//  HalloApp
//
//  Created by Tanveer on 5/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

class MomentViewController: UIViewController {

    let post: FeedPost
    let unlockingPost: FeedPost?
    
    private(set) lazy var momentView: MomentView = {
        let view = MomentView()
        view.configure(with: post)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var unlockingMomentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [unlockingMomentView, unlockingPostProgressLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 5
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }()
    
    private lazy var unlockingMomentView: MomentView = {
        let view = MomentView(style: .minimal)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }()
    
    private lazy var unlockingPostProgressLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.text = Localizations.momentUploadingProgress
        return label
    }()
    
    private lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post, contentWidth: view.bounds.width, showGroupName: false)
        view.showMoreAction = showMoreMenu
        return view
    }()
    
    private lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post)
        view.isHidden = post.userID != MainAppContext.shared.userData.userId
        view.addTarget(self, action: #selector(seenByPushed), for: .touchUpInside)
        return view
    }()
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(post: FeedPost, unlockingPost: FeedPost? = nil) {
        self.post = post
        self.unlockingPost = unlockingPost
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("SecretPostViewController coder init not implemented...")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        view.addSubview(headerView)
        view.addSubview(momentView)
        view.addSubview(facePileView)
        
        let centerYConstraint = momentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        // post will be off-center if there's an uploading post in the top corner
        centerYConstraint.priority = .defaultLow
        
        let spacing: CGFloat = 10
        NSLayoutConstraint.activate([
            centerYConstraint,
            momentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            momentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: momentView.topAnchor, constant: -spacing),
            facePileView.leadingAnchor.constraint(greaterThanOrEqualTo: momentView.leadingAnchor),
            facePileView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            facePileView.topAnchor.constraint(equalTo: momentView.bottomAnchor, constant: spacing),
        ])
        
        installDismissButton()
        installUnlockingPost()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        post.feedMedia.first?.$isMediaAvailable.sink { [weak self] _ in
            self?.expireMomentIfReady()
        }.store(in: &cancellables)
    }
    
    private func installUnlockingPost() {
        guard let unlockingPost = unlockingPost else {
            momentView.setState(.unlocked)
            return
        }

        view.addSubview(unlockingMomentStack)
        unlockingMomentView.configure(with: unlockingPost)
        momentView.setState(unlockingPost.status == .sent ? .unlocked : .indeterminate)
        
        for media in unlockingPost.feedMedia where !media.isMediaAvailable {
            media.loadImage()
        }
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: unlockingMomentStack.bottomAnchor, constant: 25),
            unlockingMomentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            unlockingMomentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            unlockingMomentStack.widthAnchor.constraint(equalToConstant: 85),
        ])
        
        unlockingPost.publisher(for: \.statusValue).sink { [weak self] _ in
            self?.updateUploadState()
        }.store(in: &cancellables)
        
        updateUploadState()
    }
    
    private func installDismissButton() {
        let config = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: config)
        
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
        ])
    }

    @objc
    private func seenByPushed(_ sender: AnyObject) {
        let viewController = PostDashboardViewController(feedPost: post)
        //viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
    
    private func showMoreMenu() {
        let menu = FeedPostMenuViewController.Menu {
            if post.canDeletePost {
                FeedPostMenuViewController.Section {
                    FeedPostMenuViewController.Item(style: .destructive,
                                                     icon: UIImage(systemName: "trash"),
                                                    title: Localizations.deletePostButtonTitle) { [weak self, post] _ in
                        self?.handleDeletePostTapped(postID: post.id)
                    }
                }
            }
        }
        
        present(FeedPostMenuViewController(menu: menu), animated: true)
    }
    
    private func handleDeletePostTapped(postID: FeedPostID) {
        let actionSheet = UIAlertController(title: nil,
                                          message: Localizations.deletePostConfirmationPrompt,
                                   preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
            self.reallyRetractPost(postID: postID)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        actionSheet.view.tintColor = .systemBlue
        
        present(actionSheet, animated: true)
    }

    private func reallyRetractPost(postID: FeedPostID) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID) else {
            dismiss(animated: true)
            return
        }
        
        MainAppContext.shared.feedData.retract(post: feedPost) { [weak self] result in
            switch result {
            case .failure(_):
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Localizations.deletePostError, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                    self?.present(alert, animated: true, completion: nil)
                }
            default:
                break
            }
        }
        
        dismiss(animated: true)
    }

    private func updateUploadState() {
        guard let unlockingPost = unlockingPost else {
            return
        }
        
        switch unlockingPost.status {
        case .sent:
            unlockingPostProgressLabel.text = Localizations.momentUploadingSuccess
            momentView.setState(.unlocked, animated: true)
            expireMomentIfReady()
        case .sending:
            unlockingPostProgressLabel.text = Localizations.momentUploadingProgress
        case .sendError:
            unlockingPostProgressLabel.text = Localizations.momentUploadingFailed
        default:
            break
        }
    }

    private func expireMomentIfReady() {
        guard
            post.userId != MainAppContext.shared.userData.userId,
            post.feedMedia.first?.isMediaAvailable ?? true,
            case .unlocked = momentView.state,
            case .sent = unlockingPost?.status ?? .sent
        else {
            return
        }

        MainAppContext.shared.feedData.momentWasViewed(post)
    }
}

// MARK: - localization

extension Localizations {
    static var momentUploadingProgress: String {
        NSLocalizedString("moment.uploading.progress",
                   value: "Uploading...",
                 comment: "For indicating that a post is uploading.")
    }
    
    static var momentUploadingSuccess: String {
        NSLocalizedString("moment.uploading.success",
                   value: "Shared!",
                 comment: "For indicating that a post has been successfully uploaded and shared.")
    }
    
    static var momentUploadingFailed: String {
        NSLocalizedString("moment.uploading.failure",
                   value: "Error",
                 comment: "For indicating that there was an error while uploading the post.")
    }
}
