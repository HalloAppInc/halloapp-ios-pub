//
//  FeedPostViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

protocol FeedPostViewControllerDelegate: AnyObject {
    func feedPostViewController(_ viewController: FeedPostViewController, didRequestShowProfileFor userId: UserID)
    func feedPostViewController(_ viewController: FeedPostViewController, didRequestShowCommentsFor postId: FeedPostID)
    func feedPostViewController(_ viewController: FeedPostViewController, didRequestMessagePublisherOf postId: FeedPostID)
}

class FeedPostViewController: UIViewController {

    private let feedPostId: FeedPostID
    weak var delegate: FeedPostViewControllerDelegate?

    init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var cardView: UIView!
    private var backgroundPanelView: FeedTableViewCellBackgroundPanelView!
    private var headerView: FeedItemHeaderView!
    private var itemContentView: FeedItemContentView!
    private var footerView: FeedItemFooterView!

    override func loadView() {
        view = UIView(frame: UIScreen.main.bounds)

        // Full-screen blur background.
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        blurView.constrain(to: view)

        // Tap on blurred background to dismiss view controller.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapToDismiss(gesture:)))
        blurView.addGestureRecognizer(tapGestureRecognizer)

        // Card view: centered vertically, full-width.
        let screenWidth = UIScreen.main.bounds.width
        cardView = UIView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenWidth))
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.preservesSuperviewLayoutMargins = true
        view.addSubview(cardView)
        cardView.constrain([ .leading, .centerY, .trailing ], to: view)

        // White card background.
        backgroundPanelView = FeedTableViewCellBackgroundPanelView(frame: cardView.bounds)
        backgroundPanelView.cornerRadius = FeedPostTableViewCellBase.LayoutConstants.backgroundCornerRadius
        cardView.addSubview(backgroundPanelView)
        updateBackgroundViewFrame()

        // Post content: header, content, footer.
        headerView = FeedItemHeaderView()
        headerView.preservesSuperviewLayoutMargins = true

        itemContentView = FeedItemContentView()
        itemContentView.textLabel.delegate = self

        footerView = FeedItemFooterView()
        footerView.preservesSuperviewLayoutMargins = true
        footerView.commentButton.addTarget(self, action: #selector(showComments), for: .touchUpInside)
        footerView.messageButton.addTarget(self, action: #selector(messagePostPublisher), for: .touchUpInside)
        footerView.facePileView.addTarget(self, action: #selector(showPostSeenBy), for: .touchUpInside)

        let vStack = UIStackView(arrangedSubviews: [ headerView, itemContentView, footerView ] )
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(vStack)
        vStack.constrainMargins(to: cardView)

        // Separator in the footer view needs to be extended past view bounds to be the same width as background "card".
        cardView.addConstraints([
            footerView.separator.leadingAnchor.constraint(equalTo: backgroundPanelView.leadingAnchor),
            footerView.separator.trailingAnchor.constraint(equalTo: backgroundPanelView.trailingAnchor)
        ])

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            let contentWidth = view.frame.width - view.layoutMargins.left - view.layoutMargins.right
            let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * view.layoutMargins.left
            let postAuthorId = feedPost.userId
            headerView.configure(with: feedPost)
            headerView.showUserAction = { [weak self] in
                guard let self = self else { return }
                self.showUserProfile(userId: postAuthorId)
            }
            itemContentView.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)
            footerView.configure(with: feedPost, contentWidth: contentWidth)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBackgroundViewFrame()
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateBackgroundViewFrame()
    }

    private func updateBackgroundViewFrame() {
        let panelInsets = UIEdgeInsets(top: 0, left: 0.5 * cardView.layoutMargins.left, bottom: 0, right: 0.5 * cardView.layoutMargins.right)
        backgroundPanelView.frame = cardView.bounds.inset(by: panelInsets)
    }

    @objc private func tapToDismiss(gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            dismiss(animated: true)
        }
    }

    private func showUserProfile(userId: UserID) {
        guard let delegate = delegate else { return }
        dismiss(animated: true) {
            delegate.feedPostViewController(self, didRequestShowProfileFor: userId)
        }
    }

    @objc private func showComments() {
        guard let delegate = delegate else { return }
        dismiss(animated: true) {
            delegate.feedPostViewController(self, didRequestShowCommentsFor: self.feedPostId)
        }
    }

    @objc private func messagePostPublisher() {
        guard let delegate = delegate else { return }
        dismiss(animated: true) {
            delegate.feedPostViewController(self, didRequestMessagePublisherOf: self.feedPostId)
        }
    }

    @objc private func showPostSeenBy() {
        let seenByViewController = FeedPostSeenByViewController(feedPostId: feedPostId)
        present(UINavigationController(rootViewController: seenByViewController), animated: true)
    }

}

extension FeedPostViewController: TextLabelDelegate {

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        case .userMention:
            if let userID = link.userID {
                showUserProfile(userId: userID)
            }
        default:
            break
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        UIView.animate(withDuration: 0.3) {
            self.itemContentView.textLabel.numberOfLines = 0
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

}
