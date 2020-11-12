//
//  FeedPostCollectionViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/12/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import UIKit


fileprivate extension FeedPost {
    var hideFooterSeparator: Bool {
        !orderedMedia.isEmpty && text?.isEmpty ?? true
    }
}


protocol FeedPostCollectionViewCellDelegate: AnyObject {

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL)

    func feedPostCollectionViewCellDidRequestReloadHeight(_ cell: FeedPostCollectionViewCell, animations animationBlock: () -> Void)
}


class FeedPostCollectionViewCellBase: UICollectionViewCell {

    struct LayoutConstants {
        static let backgroundCornerRadius: CGFloat = 15
        /**
         Content view (vertical stack takes standard table view content width: tableView.width - tableView.layoutMargins.left - tableView.layoutMargins.right
         Background "card" horizontal insets are 1/2 of the layout margin.
         */
        static let backgroundPanelViewOutsetV: CGFloat = 8
        /**
         In contrast with horizontal margins, vertical margins are defined relative to cell's top and bottom edges.
         Background "card" has 25 pt margins on top and bottom (so that space between cards is 50 pt).
         Content is further inset 8 points relative to the card's top and bottom edges.
         */
        static let backgroundPanelVMargin: CGFloat = 0//25
        /**
         The background panel's width is defined as a ratio of the table view's layout margins. Because it is 0.5,
         the edge of the card lies halfway between the edge of the cell's content and the edge of the screen.
         */
        static let backgroundPanelHMarginRatio: CGFloat = 0.5
    }

    var postId: FeedPostID? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private(set) var backgroundPanelView: FeedTableViewCellBackgroundPanelView!

    private func commonInit() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        // Background
        backgroundPanelView = FeedTableViewCellBackgroundPanelView()
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        let backgroundView = UIView()
        backgroundView.preservesSuperviewLayoutMargins = true
        backgroundView.addSubview(backgroundPanelView)
        self.backgroundView = backgroundView
        updateBackgroundPanelShadow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundView = backgroundView {
            let panelInsets = UIEdgeInsets(
                top: LayoutConstants.backgroundPanelVMargin,
                left: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.left,
                bottom: LayoutConstants.backgroundPanelVMargin,
                right: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.right)
            backgroundPanelView.frame = backgroundView.bounds.inset(by: panelInsets)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != self.traitCollection.userInterfaceStyle {
            // Shadow color needs to be updated when user interface style changes between dark and light.
            updateBackgroundPanelShadow()
        }
    }

    private func updateBackgroundPanelShadow() {
        backgroundPanelView.isShadowHidden = traitCollection.userInterfaceStyle == .dark
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        DDLogVerbose("FeedPostCollectionViewCell/configure [\(post.id)]")

        postId = post.id
    }

}

class FeedPostCollectionViewCell: FeedPostCollectionViewCellBase {

    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var showUserAction: ((UserID) -> ())?
    var cancelSendingAction: (() -> ())?
    var retrySendingAction: (() -> ())?

    weak var delegate: FeedPostCollectionViewCellDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var headerView: FeedItemHeaderView!
    private var itemContentView: FeedItemContentView!
    private var footerView: FeedItemFooterView!

    private func commonInit() {
        headerView = FeedItemHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        itemContentView = FeedItemContentView()
        itemContentView.translatesAutoresizingMaskIntoConstraints = false
        itemContentView.textLabel.delegate = self
        contentView.addSubview(itemContentView)

        footerView = FeedItemFooterView()
        footerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerView)

        // Lower constraint priority to avoid unsatisfiable constraints situation when UITableViewCell's height is 44 during early table view layout passes.
        let footerViewBottomConstraint = footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV))
        footerViewBottomConstraint.priority = .required - 10

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // CONTENT
            itemContentView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            itemContentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            itemContentView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // FOOTER
            footerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            footerView.topAnchor.constraint(equalTo: itemContentView.bottomAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            footerViewBottomConstraint
        ])

        // Separator in the footer view needs to be extended past view bounds to be the same width as background "card".
        addConstraints([
            footerView.separator.leadingAnchor.constraint(equalTo: backgroundPanelView.leadingAnchor),
            footerView.separator.trailingAnchor.constraint(equalTo: backgroundPanelView.trailingAnchor)
        ])

        // Connect actions of footer view buttons
        footerView.commentButton.addTarget(self, action: #selector(showComments), for: .touchUpInside)
        footerView.messageButton.addTarget(self, action: #selector(messageContact), for: .touchUpInside)
        footerView.facePileView.addTarget(self, action: #selector(showSeenBy), for: .touchUpInside)
        footerView.cancelAction = { [weak self] in
            self?.cancelSendingAction?()
        }
        footerView.retryAction = { [weak self] in
            self?.retrySendingAction?()
        }
    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)
        footerView.configure(with: post, contentWidth: contentWidth)


        headerView.backgroundColor = UIColor(red: CGFloat.random(in: 0...1), green: CGFloat.random(in: 0...1), blue: CGFloat.random(in: 0...1), alpha: 1)
        itemContentView.backgroundColor = UIColor(red: CGFloat.random(in: 0...1), green: CGFloat.random(in: 0...1), blue: CGFloat.random(in: 0...1), alpha: 1)
        footerView.backgroundColor = UIColor(red: CGFloat.random(in: 0...1), green: CGFloat.random(in: 0...1), blue: CGFloat.random(in: 0...1), alpha: 1)

    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
        itemContentView.prepareForReuse()
        footerView.prepareForReuse()
    }

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        headerView.configure(with: feedPost)
    }

    // MARK: Button actions

    @objc(showComments)
    private func showComments() {
        if let action = commentAction {
            action()
        }
    }

    @objc(messageContact)
    private func messageContact() {
        if let action = messageAction {
            action()
        }
    }

    @objc(showSeenBy)
    private func showSeenBy() {
        if let action = showSeenByAction {
            action()
        }
    }
}

extension FeedPostCollectionViewCell: TextLabelDelegate {

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url, let delegate = delegate {
                delegate.feedPostCollectionViewCell(self, didRequestOpen: url)
            }

        case .userMention:
            if let userId = link.userID {
                showUserAction?(userId)
            }

        default:
            break
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        if let delegate = delegate {
            delegate.feedPostCollectionViewCellDidRequestReloadHeight(self) {
                itemContentView.textLabel.numberOfLines = 0
            }
        }
    }
}

final class DeletedPostCollectionViewCell: FeedPostCollectionViewCellBase {

    var showUserAction: ((UserID) -> ())?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var headerView: FeedItemHeaderView!

    private func commonInit() {
        headerView = FeedItemHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textAlignment = .center
        textLabel.textColor = .secondaryLabel
        textLabel.text = NSLocalizedString("post.has.been.deleted", value: "This post has been deleted", comment: "Displayed in place of a deleted feed post.")
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        let view = UIView()
        view.backgroundColor = .clear
        view.layoutMargins.top = 20
        view.layoutMargins.bottom = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textLabel)
        textLabel.constrainMargins(to: view)
        contentView.addSubview(view)

        // Lower constraint priority to avoid unsatisfiable constraints situation when UITableViewCell's height is 44 during early table view layout passes.
        let viewBottomConstraint = view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -(LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV))
        viewBottomConstraint.priority = .required - 10

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelVMargin + LayoutConstants.backgroundPanelViewOutsetV),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // TEXT
            view.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            viewBottomConstraint
        ])
    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
    }
}
