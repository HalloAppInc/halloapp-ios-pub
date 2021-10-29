//
//  FeedPostView.swift
//  HalloApp
//
//  Created by Matt Geimer on 8/5/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import UIKit

protocol FeedPostViewDelegate: AnyObject {
    func feedPostView(_ cell: FeedPostView, didRequestOpen url: URL)
    func feedPostView(_ cell: FeedPostView, didChangeMediaIndex index: Int)
    func feedPostViewDidRequestTextExpansion(_ cell: FeedPostView, animations animationBlock: @escaping () -> Void)
}

class FeedPostView: UIView {

    var postId: FeedPostID? = nil

    var showUserAction: ((UserID) -> ())?
    var showGroupFeedAction: ((GroupID) -> ())?
    var showMoreAction: ((UserID) -> ())?
    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var cancelSendingAction: (() -> ())?
    var retrySendingAction: (() -> ())?
    var deleteAction: (() -> ())?

    weak var delegate: FeedPostViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: Layout

    static var metricsCache: [String: CGFloat] = [:]

    struct LayoutConstants {
        static let interCardSpacing: CGFloat = 50
        static let backgroundCornerRadius: CGFloat = 20
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

    private let backgroundPanelView = FeedItemBackgroundPanelView()
    private let headerView = FeedItemHeaderView()
    private let itemContentView = FeedItemContentView()
    
    var contentViewDelegate: FeedItemContentViewDelegate? {
        didSet {
            itemContentView.delegate = contentViewDelegate
        }
    }
    
    private let footerView = FeedItemFooterView()
    private var backgroundView: UIView?
    
    private var contentTopConstraint: NSLayoutConstraint? = nil
    private var footerViewBottomConstraint: NSLayoutConstraint? = nil

    private func commonInit() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        translatesAutoresizingMaskIntoConstraints = false

        // Background
        let solidBackgroundPanelView = FeedItemBackgroundPanelView()
        solidBackgroundPanelView.translatesAutoresizingMaskIntoConstraints = false
        solidBackgroundPanelView.backgroundColor = .feedBackground
        solidBackgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        backgroundView = UIView()
        backgroundView?.translatesAutoresizingMaskIntoConstraints = false
        backgroundView?.preservesSuperviewLayoutMargins = true
        backgroundView?.addSubview(solidBackgroundPanelView)
        backgroundView?.addSubview(backgroundPanelView)
        solidBackgroundPanelView.constrain(to: backgroundPanelView)
        if let backgroundView = backgroundView {
            addSubview(backgroundView)
        }
        backgroundView?.constrain(to: self)
        updateBackgroundPanelShadow()

        if !Self.subscribedToContentSizeCategoryChangeNotification {
            NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { (notification) in
                Self.metricsCache.removeAll()
            }
            Self.subscribedToContentSizeCategoryChangeNotification = true
        }

        headerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(headerView)

        itemContentView.translatesAutoresizingMaskIntoConstraints = false
        itemContentView.textLabel.delegate = self
        self.addSubview(itemContentView)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(footerView)

        footerViewBottomConstraint = footerView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -LayoutConstants.backgroundPanelViewOutsetV - LayoutConstants.interCardSpacing / 2)
        footerViewBottomConstraint?.isActive = true

        contentTopConstraint = itemContentView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 5)
        contentTopConstraint?.isActive = true

        self.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: self.topAnchor, constant: LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing / 2),
            headerView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),

            // CONTENT
            itemContentView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            itemContentView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),

            // FOOTER
            footerView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            footerView.topAnchor.constraint(equalTo: itemContentView.bottomAnchor),
            footerView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
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
        footerView.deleteAction = { [weak self] in
            self?.deleteAction?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let backgroundView = backgroundView {
            let panelInsets = UIEdgeInsets(
                top: LayoutConstants.interCardSpacing / 2,
                left: LayoutConstants.backgroundPanelHMarginRatio * backgroundView.layoutMargins.left,
                bottom: LayoutConstants.interCardSpacing / 2,
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

    private lazy var maxWidthConstraint: NSLayoutConstraint = {
        widthAnchor.constraint(equalToConstant: maxWidth)
    }()
    
    var isShowingFooter: Bool = true {
        didSet {
            if isShowingFooter {
                footerView.isHidden = false
                footerView.constraints.forEach { constraint in
                    constraint.isActive = true
                }
            } else {
                footerView.isHidden = true
                footerView.constraints.forEach { constraint in
                    constraint.isActive = false
                }
            }
        }
    }

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

    // MARK: FeedPostCollectionViewCell

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        headerView.configure(with: feedPost)
    }

    func refreshFooter(using feedPost: FeedPost, contentWidth: CGFloat) {
        footerView.configure(with: feedPost, contentWidth: contentWidth)
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, showGroupName: Bool, showArchivedDate: Bool, displayData: FeedPostDisplayData? = nil) {
        DDLogVerbose("FeedPostCollectionViewCell/configure [\(post.id)]-[\(post.media?.count ?? 0)]")

        postId = post.id

        headerView.configure(with: post, showArchivedDate: showArchivedDate)
        if showGroupName {
            configureGroupLabel(with: post.groupId, contentWidth: contentWidth, gutterWidth: gutterWidth)
        }
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        headerView.showGroupFeedAction = { [weak self] in
            guard let groupID = post.groupId else { return }
            self?.showGroupFeedAction?(groupID)
        }
        headerView.showMoreAction = { [weak self] in
            guard let self = self, let showMoreAction = self.showMoreAction else { return }
            showMoreAction(post.userId)
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: displayData)
        itemContentView.didChangeMediaIndex = { [weak self] index in
            guard let self = self else { return }
            self.delegate?.feedPostView(self, didChangeMediaIndex: index)
        }
        
        if post.media?.count ?? 0 > 0 {
            contentTopConstraint?.constant = 5
        } else {
            contentTopConstraint?.constant = 0
        }
        
        footerView.configure(with: post, contentWidth: contentWidth)
    }
    
    func configureGroupLabel(with groupID: String?, contentWidth: CGFloat, gutterWidth: CGFloat) {
        headerView.configureGroupLabel(with: groupID, contentWidth: contentWidth, gutterWidth: gutterWidth)
    }

    // MARK: Height computation

    class func height(forPost post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, displayData: FeedPostDisplayData?, showingFooter: Bool = true) -> CGFloat {
        let headerHeight = Self.headerHeight(forPost: post, contentWidth: contentWidth)
        let contentHeight = Self.contentHeight(forPost: post, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: displayData)
        let footerHeight = showingFooter ? Self.footerHeight(forPost: post, contentWidth: contentWidth) : 0
        
        return headerHeight + contentHeight + footerHeight + 2 * LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing
    }
    
    func setHeaderHeight(forPost post: FeedPost, contentWidth: CGFloat) {
        headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight(forPost: post, contentWidth: contentWidth)).isActive = true
    }

    private static let headerCacheKey = "height.header"
    private class func headerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        if let cachedHeaderHeight = Self.metricsCache[headerCacheKey] {
            return cachedHeaderHeight
        }
        let headerView = FeedItemHeaderView()
        headerView.configure(with: post)
        let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let headerSize = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        Self.metricsCache[headerCacheKey] = headerSize.height
        return headerSize.height
    }

    private static let footerCacheKey = "height.footer"
    private class func footerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        // It is possible to cache footer height because all footers look the same.
        if let cachedFooterHeight = Self.metricsCache[footerCacheKey] {
            return cachedFooterHeight
        }
        let footerView = FeedItemFooterView()
        let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
        let footerSize = footerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        Self.metricsCache[footerCacheKey] = footerSize.height
        return footerSize.height
    }

    private class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, displayData: FeedPostDisplayData?) -> CGFloat {
        let contentHeight = FeedItemContentView.preferredHeight(forPost: post, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: displayData)
        return contentHeight
    }

    // MARK: Button actions

    @objc(showComments)
    private func showComments() {
        commentAction?()
    }

    @objc(messageContact)
    private func messageContact() {
        messageAction?()
    }

    @objc(showSeenBy)
    private func showSeenBy() {
        showSeenByAction?()
    }
}

extension FeedPostView: TextLabelDelegate {

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url, let delegate = delegate {
                guard MainAppContext.shared.chatData.proceedIfNotGroupInviteLink(url) else { break }
                delegate.feedPostView(self, didRequestOpen: url)
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
        delegate?.feedPostViewDidRequestTextExpansion(self) {
            self.itemContentView.textLabel.numberOfLines = 0
        }
    }
}

final class FeedEventView: UIView {

    enum EventType {
        case event
        case deletedPost
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func configure(with text: String, type: EventType, isThemed: Bool = false) {
        textLabel.text = text

        switch type {
        case .deletedPost:
            bubble.backgroundColor = UIColor.feedPostEventDeletedBg
            textLabel.textColor = .secondaryLabel
        case .event:
            bubble.backgroundColor = isThemed ? UIColor.feedPostEventThemedBg : UIColor.feedPostEventDefaultBg
            textLabel.textColor = isThemed ? UIColor.feedPostEventText : UIColor.black.withAlphaComponent(0.6)
        }
    }

    private static let cacheKey = "\(FeedEventCollectionViewCell.self).content"
    private static let sizingLabel = makeLabel(alignment: .natural, isMultiLine: true)
    private static let directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 50, bottom: 8, trailing: 50)
    private static let bubbleMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    private let textLabel = makeLabel(alignment: .center, isMultiLine: true)
    private let bubble = makeBubble()

    private func commonInit() {
        self.directionalLayoutMargins = Self.directionalLayoutMargins

        bubble.addSubview(textLabel)
        self.addSubview(bubble)

        textLabel.constrainMargins(to: bubble)

        bubble.constrainMargins([.top, .bottom, .centerX], to: self)
        bubble.leadingAnchor.constraint(greaterThanOrEqualTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        bubble.trailingAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.trailingAnchor).isActive = true

        self.widthAnchor.constraint(equalToConstant: bounds.width).isActive = true
    }

    static func makeLabel(alignment: NSTextAlignment, isMultiLine: Bool) -> UILabel {
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textAlignment = alignment
        textLabel.numberOfLines = isMultiLine ? 0 : 1
        if !isMultiLine {
            textLabel.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        }
        textLabel.backgroundColor = .clear
        textLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        textLabel.adjustsFontForContentSizeCategory = true
        return textLabel
    }

    static func makeBubble() -> UIView {
        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = 15
        bubble.directionalLayoutMargins = Self.bubbleMargins
        return bubble
    }
}

extension FeedEventView {
    static func height(for text: String, width: CGFloat) -> CGFloat {
        sizingLabel.text = text
        let availableWidth = width - directionalLayoutMargins.leading - directionalLayoutMargins.trailing - bubbleMargins.leading - bubbleMargins.trailing
        let size = sizingLabel.sizeThatFits(CGSize(width: availableWidth, height: 0))
        return size.height + directionalLayoutMargins.bottom + directionalLayoutMargins.top + bubbleMargins.bottom + bubbleMargins.top
    }
}
