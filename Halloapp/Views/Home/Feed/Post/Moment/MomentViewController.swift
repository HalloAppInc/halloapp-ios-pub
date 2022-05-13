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

protocol MomentViewControllerDelegate: PostDashboardViewControllerDelegate {

}

class MomentViewController: UIViewController {

    let post: FeedPost
    let unlockingPost: FeedPost?
    weak var delegate: MomentViewControllerDelegate?

    private var backgroundColor: UIColor {
        UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return .black.withAlphaComponent(0.8)
            default:
                return .feedBackground
            }
        }
    }
    
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
        view.showUserAction = showUser
        return view
    }()
    
    private lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post)
        view.isHidden = post.userID != MainAppContext.shared.userData.userId
        view.avatarViews.forEach { $0.borderColor = backgroundColor }
        view.addTarget(self, action: #selector(seenByPushed), for: .touchUpInside)
        return view
    }()
    
    private var cancellables: Set<AnyCancellable> = []

    private lazy var contentInputView: ContentInputView = {
        let view = ContentInputView(style: .minimal, options: [])
        view.autoresizingMask = [.flexibleHeight]
        view.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .feedBackground }
        view.blurView.isHidden = true
        view.delegate = self
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID)
        view.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)

        return view
    }()

    override var canBecomeFirstResponder: Bool {
        true
    }

    private var showAccessoryView = false
    override var inputAccessoryView: UIView? {
        showAccessoryView ? contentInputView : nil
    }

    private var toast: Toast?
    private var replyCancellable: AnyCancellable?

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

        // With the modal presentation, the system adjusts a black background, causing it to
        // mismatch with the input accessory view
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = backgroundColor
        view.addSubview(backgroundView)

        view.addSubview(headerView)
        view.addSubview(momentView)
        view.addSubview(facePileView)
        
        let centerYConstraint = momentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        // post will be off-center if there's an uploading post in the top corner
        centerYConstraint.priority = .defaultLow

        let spacing: CGFloat = 10
        NSLayoutConstraint.activate([
            centerYConstraint,
            momentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            momentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: momentView.topAnchor, constant: -spacing),
            facePileView.leadingAnchor.constraint(greaterThanOrEqualTo: momentView.leadingAnchor),
            facePileView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            facePileView.topAnchor.constraint(equalTo: momentView.bottomAnchor, constant: spacing),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        installDismissButton()
        installUnlockingPost()

        post.feedMedia.first?.$isMediaAvailable.sink { [weak self] isAvailable in
            DispatchQueue.main.async {
                self?.refreshAccessoryView(show: true)
            }
        }.store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        toast?.show()
        refreshAccessoryView(show: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        toast?.hide()
        refreshAccessoryView(show: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        post.feedMedia.first?.$isMediaAvailable.sink { [weak self] _ in
            self?.expireMomentIfReady()
        }.store(in: &cancellables)
    }

    private func refreshAccessoryView(show: Bool) {
        guard
            post.userID != MainAppContext.shared.userData.userId,
            showAccessoryView != show,
            post.feedMedia.first?.isMediaAvailable ?? false,
            case .unlocked = momentView.state
        else {
            // we want to show the accessory view when:
            // 1. post isn't locked (not blurred)
            // 2. media is available
            // 3. someone else's post
            return
        }

        showAccessoryView = show
        reloadInputViews()
    }
    
    private func installUnlockingPost() {
        guard let unlockingPost = unlockingPost else {
            momentView.setState(.unlocked)
            return
        }

        view.addSubview(unlockingMomentStack)
        unlockingMomentView.configure(with: unlockingPost)
        momentView.setState(unlockingPost.status == .sent ? .unlocked : .indeterminate)
        
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
        button.addTarget(self, action: #selector(dismissPushed), for: .touchUpInside)
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
        ])
    }

    @objc
    private func seenByPushed(_ sender: AnyObject) {
        let viewController = PostDashboardViewController(feedPost: post)
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }

    @objc
    private func dismissPushed(_ sender: UIButton) {
        dismiss(animated: true)
    }

    private func showUser() {
        delegate?.postDashboardViewController(didRequestPerformAction: .profile(post.userId))
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
            refreshAccessoryView(show: true)
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

    private func showToast() {
        toast = Toast(type: .activityIndicator, text: Localizations.sending)
        toast?.show(viewController: self, shouldAutodismiss: false)
    }

    private func finalizeToast(success: Bool) {
        let icon = success ? UIImage(systemName: "checkmark") : UIImage(systemName: "xmark")
        let text = success ? Localizations.sent : Localizations.failedToSend

        toast?.update(type: .icon(icon), text: text, shouldAutodismiss: true)
        toast = nil
    }

    private func beginObserving(message: ChatMessage) {
        replyCancellable?.cancel()
        replyCancellable = message.publisher(for: \.outgoingStatusValue).sink { [weak self] _ in
            let success: Bool?
            switch message.outgoingStatus {
            case .sentOut, .delivered, .seen, .played:
                success = true
            case .error, .retracted:
                success = false
            case .none, .pending, .retracting:
                success = nil
            }

            if let success = success {
                self?.finalizeToast(success: success)
                self?.replyCancellable?.cancel()
                self?.replyCancellable = nil
            }
        }
    }
}

// MARK: - PostDashboardViewController delegate methods

extension MomentViewController: PostDashboardViewControllerDelegate {
    func postDashboardViewController(didRequestPerformAction action: PostDashboardViewController.UserAction) {
        delegate?.postDashboardViewController(didRequestPerformAction: action)
    }
}

// MARK: - ContentInputView delegate methods

extension MomentViewController: ContentInputDelegate {
    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        contentInputView.textView.resignFirstResponder()
        let text = content.mentionText.trimmed().collapsedText
        showToast()

        Task {
            guard let message = await MainAppContext.shared.chatData.sendMomentReply(to: post.userID, postID: post.id, text: text) else {
                finalizeToast(success: false)
                return
            }

            beginObserving(message: message)
        }
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

    static var privateReplyPlaceholder: String {
        NSLocalizedString("private.reply.placeholder",
                   value: "Reply to %@",
                 comment: "Placeholder text for the text field for private replies. The argument is the first name of the contact.")
    }

    static var sending: String {
        NSLocalizedString("sending.title",
                   value: "Sending",
                 comment: "Indicates that an item is in the process of being sent.")
    }

    static var sent: String {
        NSLocalizedString("sent.title",
                   value: "Sent",
                 comment: "Indicates that an item has successfully been sent.")
    }

    static var failedToSend: String {
        NSLocalizedString("failed.to.send",
                   value: "Failed to send",
                 comment: "Indicates that an item has failed to be sent.")
    }
}
