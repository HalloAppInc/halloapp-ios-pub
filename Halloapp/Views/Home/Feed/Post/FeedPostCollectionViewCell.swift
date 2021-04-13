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

    func feedPostCollectionViewCellDidRequestTextExpansion(_ cell: FeedPostCollectionViewCell, animations animationBlock: @escaping () -> Void)
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
        static let interCardSpacing: CGFloat = 50
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

    private(set) var backgroundPanelView: FeedItemBackgroundPanelView!

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
        contentView.constrain(to: self)

        // Background
        backgroundPanelView = FeedItemBackgroundPanelView()
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

    // MARK: FeedPostCollectionViewCellBase

    var showUserAction: ((UserID) -> ())?

    var postId: FeedPostID? = nil

    class var reuseIdentifier: String {
        fatalError("Subclasses must implement")
    }

    final class func height(forPost post: FeedPost, contentWidth: CGFloat, isTextExpanded: Bool) -> CGFloat {
        let headerHeight = Self.headerHeight(forPost: post, contentWidth: contentWidth)
        let contentHeight = Self.contentHeight(forPost: post, contentWidth: contentWidth, isTextExpanded: isTextExpanded)
        let footerHeight = Self.footerHeight(forPost: post, contentWidth: contentWidth)
        return headerHeight + contentHeight + footerHeight + 2 * LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing
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

    fileprivate class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat, isTextExpanded: Bool) -> CGFloat {
        return 0
    }

    fileprivate class func footerHeight(forPost post: FeedPost, contentWidth: CGFloat) -> CGFloat {
        return 0
    }

}

class FeedPostCollectionViewCell: FeedPostCollectionViewCellBase {

    var showGroupFeedAction: ((GroupID) -> ())?
    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var cancelSendingAction: (() -> ())?
    var retrySendingAction: (() -> ())?
    var deleteAction: (() -> ())?

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
        let footerViewBottomConstraint = footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -LayoutConstants.backgroundPanelViewOutsetV - LayoutConstants.interCardSpacing / 2)
        footerViewBottomConstraint.priority = .defaultHigh

        contentView.addConstraints([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing / 2),
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
        footerView.deleteAction = { [weak self] in
            self?.deleteAction?()
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

    func refreshFooter(using feedPost: FeedPost, contentWidth: CGFloat) {
        footerView.configure(with: feedPost, contentWidth: contentWidth)
    }

    // MARK: FeedPostCollectionViewCellBase

    override class var reuseIdentifier: String {
        "active-post"
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, showGroupName: Bool, isTextExpanded: Bool) {
        DDLogVerbose("FeedPostCollectionViewCell/configure [\(post.id)]")

        postId = post.id

        headerView.configure(with: post)
        if showGroupName {
            headerView.configureGroupLabel(with: post)
        }
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        headerView.showGroupFeedAction = { [weak self] in
            guard let groupID = post.groupId else { return }
            self?.showGroupFeedAction?(groupID)
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth, isTextExpanded: isTextExpanded)
        footerView.configure(with: post, contentWidth: contentWidth)
    }

    override class func contentHeight(forPost post: FeedPost, contentWidth: CGFloat, isTextExpanded: Bool) -> CGFloat {
        let contentHeight = FeedItemContentView.preferredHeight(forPost: post, contentWidth: contentWidth, isTextExpanded: isTextExpanded)
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
            delegate.feedPostCollectionViewCellDidRequestTextExpansion(self) {
                self.itemContentView.textLabel.numberOfLines = 0
            }
        }
    }
}

final class FeedEventCollectionViewCell: UICollectionViewCell {

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

    override func prepareForReuse() {
        textLabel.text = nil
    }

    class var reuseIdentifier: String {
        "feed-event"
    }

    func configure(with text: String, type: EventType) {
        textLabel.text = text
        switch type {
        case .deletedPost:
            bubble.backgroundColor = UIColor.label.withAlphaComponent(0.1)
            textLabel.textColor = .secondaryLabel
        case .event:
            bubble.backgroundColor = .init(red: 205.0/255, green: 227.0/255, blue: 255.0/255, alpha: 1)
            textLabel.textColor = .black
        }
    }

    private static let cacheKey = "\(FeedEventCollectionViewCell.self).content"
    private static let sizingLabel = makeLabel(alignment: .natural, isMultiLine: true)
    private static let directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 50, bottom: 8, trailing: 50)
    private static let bubbleMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    private let textLabel = makeLabel(alignment: .center, isMultiLine: true)
    private let bubble = makeBubble()

    private func commonInit() {
        contentView.directionalLayoutMargins = Self.directionalLayoutMargins

        bubble.addSubview(textLabel)
        contentView.addSubview(bubble)

        textLabel.constrainMargins(to: bubble)

        bubble.constrainMargins([.top, .bottom, .centerX], to: contentView)
        bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true

        contentView.widthAnchor.constraint(equalToConstant: bounds.width).isActive = true
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

extension FeedEventCollectionViewCell {
    static func height(for text: String, width: CGFloat) -> CGFloat {
        sizingLabel.text = text
        let availableWidth = width - directionalLayoutMargins.leading - directionalLayoutMargins.trailing - bubbleMargins.leading - bubbleMargins.trailing
        let size = sizingLabel.sizeThatFits(CGSize(width: availableWidth, height: 0))
        return size.height + directionalLayoutMargins.bottom + directionalLayoutMargins.top + bubbleMargins.bottom + bubbleMargins.top
    }
}

extension Localizations {
    static func deletedPost(from userID: UserID) -> String {
        if userID == MainAppContext.shared.userData.userId {
            return  NSLocalizedString("post.has.been.deleted.by.you", value: "You deleted your post", comment: "Displayed in place of a deleted feed post.")
        } else if let name = MainAppContext.shared.contactStore.fullNameIfAvailable(for: userID) {
            let format = NSLocalizedString("post.has.been.deleted.by.author", value: "%@ deleted their post", comment: "Displayed in place of a deleted feed post.")
            return String(format: format, name)
        } else {
            return NSLocalizedString("post.has.been.deleted", value: "This post has been deleted", comment: "Displayed in place of a deleted feed post.")
        }
    }
}

extension NSTextAlignment {
    static var unnatural: NSTextAlignment {
        UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft ? .left : .right
    }
}
