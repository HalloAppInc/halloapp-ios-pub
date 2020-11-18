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

    func feedPostCollectionViewCellDidRequestReloadHeight(_ cell: FeedPostCollectionViewCell, animations animationBlock: @escaping () -> Void)
}

class FeedPostCollectionViewCellBase: UICollectionViewCell {

    static var metricsCache: [String: CGFloat] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Layout

    struct LayoutConstants {
        static let backgroundCornerRadius: CGFloat = 15
        /**
         Content view (vertical stack takes standard table view content width: tableView.width - tableView.layoutMargins.left - tableView.layoutMargins.right
         Background "card" horizontal insets are 1/2 of the layout margin.
         */
        static let backgroundPanelViewOutsetV: CGFloat = 8
        /**
         The background panel's width is defined as a ratio of the table view's layout margins. Because it is 0.5,
         the edge of the card lies halfway between the edge of the cell's content and the edge of the screen.
         */
        static let backgroundPanelHMarginRatio: CGFloat = 0.5
    }

    private(set) var backgroundPanelView: FeedTableViewCellBackgroundPanelView!

    private var maxWidthConstraint: NSLayoutConstraint!
    var maxWidth: CGFloat = 0 {
        didSet {
            guard maxWidth != oldValue else {
                return
            }
            maxWidthConstraint.constant = maxWidth
            maxWidthConstraint.isActive = true
        }
    }

    private static var subscribedToContentSizeCategoryChangeNotification = false

    private func commonInit() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        maxWidthConstraint = widthAnchor.constraint(equalToConstant: maxWidth)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.constrain([ .leading, .top, .trailing ], to: self)

        // Background
        backgroundPanelView = FeedTableViewCellBackgroundPanelView()
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        let backgroundView = UIView()
        backgroundView.preservesSuperviewLayoutMargins = true
        backgroundView.addSubview(backgroundPanelView)
        self.backgroundView = backgroundView
        updateBackgroundPanelShadow()

        if !FeedPostCollectionViewCellBase.subscribedToContentSizeCategoryChangeNotification {
            NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { (notification) in
                FeedPostCollectionViewCellBase.metricsCache.removeAll()
            }
            FeedPostCollectionViewCellBase.subscribedToContentSizeCategoryChangeNotification = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundView = backgroundView {
            let panelInsets = UIEdgeInsets(
                top: 0,
                left: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.left,
                bottom: 0,
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

    // MARK: FeedPostCollectionViewCellBase

    var showUserAction: ((UserID) -> ())?

    var postId: FeedPostID? = nil

    class var reuseIdentifier: String {
        fatalError("Subclasses must implement")
    }

    final class func cellClass(forPost post: FeedPost) -> FeedPostCollectionViewCellBase.Type {
        return post.isPostRetracted ? DeletedPostCollectionViewCell.self : FeedPostCollectionViewCell.self
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        DDLogVerbose("FeedPostCollectionViewCell/configure [\(post.id)]")

        postId = post.id
    }

    final class func height(forPost post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) -> CGFloat {
        let cellClass = FeedPostCollectionViewCellBase.cellClass(forPost: post)
        let headerHeight = cellClass.headerHeight(forPost: post, contentWidth: contentWidth)
        let contentHeight = cellClass.contentHeight(forPost: post, contentWidth: contentWidth)
        let footerHeight = cellClass.footerHeight(forPost: post, contentWidth: contentWidth)
        return headerHeight + contentHeight + footerHeight + 2 * LayoutConstants.backgroundPanelViewOutsetV
    }

    private static let cacheKey = "\(FeedPostCollectionViewCellBase.self).header"

    fileprivate class func headerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        if let cachedHeaderHeight = FeedPostCollectionViewCellBase.metricsCache[cacheKey] {
            return cachedHeaderHeight
        }
        let headerView = FeedItemHeaderView()
        headerView.configure(with: post)
        let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let headerSize = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        FeedPostCollectionViewCellBase.metricsCache[cacheKey] = headerSize.height
        return headerSize.height
    }

    fileprivate class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        return 0
    }

    fileprivate class func footerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        return 0
    }

}

class FeedPostCollectionViewCell: FeedPostCollectionViewCellBase {

    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
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

    // MARK: Layout

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
        let footerViewBottomConstraint = footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -LayoutConstants.backgroundPanelViewOutsetV)
        footerViewBottomConstraint.priority = .defaultHigh

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelViewOutsetV),
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

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
        itemContentView.prepareForReuse()
        footerView.prepareForReuse()
    }

    // MARK: FeedPostCollectionViewCell

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        headerView.configure(with: feedPost)
    }

    // MARK: FeedPostCollectionViewCellBase

    override class var reuseIdentifier: String {
        "active-post"
    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)
        footerView.configure(with: post, contentWidth: contentWidth)
    }

    override class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        let contentHeight = FeedItemContentView.preferredHeight(forPost: post, contentWidth: contentWidth)
        return contentHeight
    }

    private static let cacheKey = "\(FeedPostCollectionViewCell.self).footer"

    override class func footerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        // It is possible to cache footer height because all footers look the same.
        if let cachedFooterHeight = FeedPostCollectionViewCellBase.metricsCache[cacheKey] {
            return cachedFooterHeight
        }
        let footerView = FeedItemFooterView()
        let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let footerSize = footerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        FeedPostCollectionViewCellBase.metricsCache[cacheKey] = footerSize.height
        return footerSize.height
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
                self.itemContentView.textLabel.numberOfLines = 0
            }
        }
    }
}

final class DeletedPostCollectionViewCell: FeedPostCollectionViewCellBase {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Layout

    private class ContentView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        private func commonInit() {
            layoutMargins.top = 20
            layoutMargins.bottom = 12
            translatesAutoresizingMaskIntoConstraints = false

            let textLabel = UILabel()
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            textLabel.textAlignment = .center
            textLabel.textColor = .secondaryLabel
            textLabel.text = NSLocalizedString("post.has.been.deleted", value: "This post has been deleted", comment: "Displayed in place of a deleted feed post.")
            textLabel.font = UIFont.preferredFont(forTextStyle: .body)
            textLabel.adjustsFontForContentSizeCategory = true
            addSubview(textLabel)
            textLabel.constrainMargins(to: self)
        }
    }

    private var headerView: FeedItemHeaderView!

    private func commonInit() {
        headerView = FeedItemHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        let view = ContentView()
        contentView.addSubview(view)

        // Lower constraint priority to avoid unsatisfiable constraints situation when UITableViewCell's height is 44 during early table view layout passes.
        let viewBottomConstraint = view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -LayoutConstants.backgroundPanelViewOutsetV)
        viewBottomConstraint.priority = .required - 10

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelViewOutsetV),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // TEXT
            view.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            viewBottomConstraint
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
    }

    // MARK: FeedPostCollectionViewCellBase

    override class var reuseIdentifier: String {
        "deleted-post"
    }

    override func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat) {
        super.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth)

        headerView.configure(with: post)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
    }

    private static let cacheKey = "\(DeletedPostCollectionViewCell.self).content"

    override class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        // It is possible to cache content height because all deleted posts look the same.
        if let cachedContentHeight = FeedPostCollectionViewCellBase.metricsCache[cacheKey] {
            return cachedContentHeight
        }
        let contentView = ContentView()
        let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let contentSize = contentView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        FeedPostCollectionViewCellBase.metricsCache[cacheKey] = contentSize.height
        return contentSize.height
    }
}
