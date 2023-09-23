//
//  FeedPostCollectionViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/12/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

struct FeedPostDisplayData: Equatable {
    var currentMediaIndex: Int?
    var textNumberOfLines: Int?
}

protocol FeedPostCollectionViewCellDelegate: AnyObject {
    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL)
    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didChangeMediaIndex index: Int)
    func feedPostCollectionViewCellDidRequestTextExpansion(_ cell: FeedPostCollectionViewCell, for textView: ExpandableTextView)
}

class FeedPostCollectionViewCell: UICollectionViewCell {

    var postId: FeedPostID? = nil

    var showUserAction: ((UserID) -> ())?
    var showGroupFeedAction: ((GroupID) -> ())?
    var moreMenuContent: () -> HAMenu.Content = { [] }
    var showPrivacyAction: (() -> ())?
    var commentAction: (() -> ())?
    var messageAction: (() -> ())?
    var showSeenByAction: (() -> ())?
    var cancelSendingAction: (() -> ())?
    var retrySendingAction: (() -> ())?
    var deleteAction: (() -> ())?
    var contextAction: ((UserAction) -> ())?
    var shareAction: (() -> ())?
    var reactAction: ((String?) -> ())?

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

    struct LayoutConstants {
        static let interCardSpacing: CGFloat = 20
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
    private lazy var footerView: FeedItemFooterProtocol = {
        if ServerProperties.postReactions {
            return FeedItemFooterReactionView()
        } else {
            return FeedItemFooterView()
        }
    }()
    private let reactionView = ReactionPicker()
    
    private var contentTopConstraint: NSLayoutConstraint? = nil
    private var backgroundPanelLeadingConstraint: NSLayoutConstraint?
    private var backgroundPanelTrailingConstraint: NSLayoutConstraint?

    private func commonInit() {

        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        // Background
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        backgroundPanelView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundPanelView)
        updateBackgroundPanelShadow()

        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)

        itemContentView.translatesAutoresizingMaskIntoConstraints = false
        itemContentView.textView.delegate = self
        contentView.addSubview(itemContentView)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footerView)
        
        reactionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(reactionView)
        reactionView.isUserInteractionEnabled = true
        reactionView.isHidden = false

        let contentTopConstraint = itemContentView.topAnchor.constraint(equalTo: headerView.bottomAnchor)
        self.contentTopConstraint = contentTopConstraint

        let verticalContentPadding = LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing / 2
        let footerBottomConstraint = footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                                        constant: -verticalContentPadding)
        // On initial cell sizing, our height is set to the estimatedItemHeight, which causes
        // constraint violations. Allow overflow at the bottom to prevent this.
        footerBottomConstraint.priority = UILayoutPriority(999)

        let backgroundPanelLeadingConstraint = backgroundPanelView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                                                            constant: layoutMargins.left * LayoutConstants.backgroundPanelHMarginRatio)
        self.backgroundPanelLeadingConstraint = backgroundPanelLeadingConstraint
        let backgroundPanelTrailingConstraint = backgroundPanelView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                                                              constant: -layoutMargins.right * LayoutConstants.backgroundPanelHMarginRatio)
        self.backgroundPanelTrailingConstraint = backgroundPanelTrailingConstraint

        NSLayoutConstraint.activate([
            // HEADER
            headerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalContentPadding),
            headerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // CONTENT
            itemContentView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            contentTopConstraint,
            itemContentView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            // FOOTER
            footerView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            footerView.topAnchor.constraint(equalTo: itemContentView.bottomAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            footerBottomConstraint,

            // BACKGROUND
            backgroundPanelView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.interCardSpacing / 2),
            backgroundPanelView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -LayoutConstants.interCardSpacing / 2),
            backgroundPanelLeadingConstraint,
            backgroundPanelTrailingConstraint,


            // Separator in the footer view needs to be extended past view bounds to be the same width as background "card".
            footerView.separator.leadingAnchor.constraint(equalTo: backgroundPanelView.leadingAnchor),
            footerView.separator.trailingAnchor.constraint(equalTo: backgroundPanelView.trailingAnchor),
            
            // Reaction picker
            reactionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            reactionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            reactionView.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: 12),
            reactionView.heightAnchor.constraint(equalToConstant: 59),

        ])

        // Connect actions of footer view buttons
        footerView.messageButton.addTarget(self, action: #selector(messageContact), for: .touchUpInside)
        footerView.reactAction = { [weak self] in
            self?.toggleEmojiPicker()
        }
        footerView.commentAction = { [weak self] in
            self?.commentAction?()
        }
        footerView.cancelAction = { [weak self] in
            self?.cancelSendingAction?()
        }
        footerView.retryAction = { [weak self] in
            self?.retrySendingAction?()
        }
        footerView.deleteAction = { [weak self] in
            self?.deleteAction?()
        }
        footerView.shareAction = { [weak self] in
            self?.shareAction?()
        }
        footerView.seenByAction = { [weak self] in
            self?.showSeenByAction?()
        }
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        backgroundPanelLeadingConstraint?.constant = layoutMargins.left * LayoutConstants.backgroundPanelHMarginRatio
        backgroundPanelTrailingConstraint?.constant = -layoutMargins.right * LayoutConstants.backgroundPanelHMarginRatio
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        postId = nil
        headerView.prepareForReuse()
        footerView.prepareForReuse()
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

    // MARK: FeedPostCollectionViewCell

    func stopPlayback() {
        itemContentView.stopPlayback()
    }

    func refreshTimestamp(using feedPost: FeedPost) {
        headerView.refreshTimestamp(with: feedPost)
    }

    func refreshFooter(using feedPost: FeedPost, contentWidth: CGFloat) {
        footerView.configure(with: feedPost, contentWidth: contentWidth)
    }

    class var reuseIdentifier: String {
        "active-post"
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, showGroupName: Bool, displayData: FeedPostDisplayData?) {
        DDLogVerbose("FeedPostCollectionViewCell/configure [\(post.id)] - [\(post.media?.count ?? 0)]")

        postId = post.id

        headerView.configure(with: post, contentWidth: contentWidth, showGroupName: showGroupName)
        headerView.showUserAction = { [weak self] in
            self?.showUserAction?(post.userId)
        }
        headerView.showGroupFeedAction = { [weak self] in
            guard let groupID = post.groupId else { return }
            self?.showGroupFeedAction?(groupID)
        }
        headerView.moreMenuContent = { [weak self] in
            self?.moreMenuContent() ?? []
        }
        headerView.showPrivacyAction = { [weak self] in
            self?.showPrivacyAction?()
        }
        itemContentView.configure(with: post, contentWidth: contentWidth, gutterWidth: gutterWidth, displayData: displayData)
        itemContentView.didChangeMediaIndex = { [weak self] index in
            guard let self = self else { return }
            self.delegate?.feedPostCollectionViewCell(self, didChangeMediaIndex: index)
        }

        contentTopConstraint?.constant = Self.contentTopSpacing(forPost: post)

        footerView.configure(with: post, contentWidth: contentWidth)

        reactionView.isHidden = true
    }

    static func contentTopSpacing(forPost post: FeedPost) -> CGFloat {
        return post.media?.isEmpty ?? true ? 0 : 5
    }
  
    // MARK: Button actions

    @objc(messageContact)
    private func messageContact() {
        messageAction?()
    }
    
    @objc(toggleEmojiPicker)
    private func toggleEmojiPicker() {
        if reactionView.isHidden {
            reactionView.arrowXPosition = footerView.convert(footerView.reactButtonLocation ?? .zero, to: reactionView).x
            reactionView.delegate = self
            reactionView.currentReaction = {
                guard let feedData = MainAppContext.shared.feedData,
                      let postID = postId,
                      let post = feedData.feedPost(with: postID, in: feedData.viewContext) else
                {
                    return nil
                }
                return post.reactions?.first(where: { $0.fromUserID == MainAppContext.shared.userData.userId })?.emoji
            }()
        }
        reactionView.isHidden = !reactionView.isHidden
    }
}

extension FeedPostCollectionViewCell: ReactionPickerDelegate {
    func reactionPicker(_ reactionPicker: ReactionPicker, didSelectReaction reaction: String?) {
        reactAction?(reaction)
        toggleEmojiPicker()
    }
}

extension FeedPostCollectionViewCell: ExpandableTextViewDelegate {
    func textViewDidRequestToExpand(_ textView: ExpandableTextView) {
        delegate?.feedPostCollectionViewCellDidRequestTextExpansion(self, for: textView)
    }
    
    func textView(_ textView: ExpandableTextView, didRequestHandleMention userID: UserID) {
        showUserAction?(userID)
    }
    
    func textView(_ textView: ExpandableTextView, didSelectAction action: UserAction) {
        contextAction?(action)
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return !URLRouter.shared.handle(url: URL)
    }
}

final class FeedEventCollectionViewCell: UICollectionViewCell {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    class var reuseIdentifier: String {
        "feed-event"
    }

    func configure(with feedEvent: FeedEvent, isThemed: Bool, onTap: (() -> Void)?) {
        textLabel.text = feedEvent.description

        switch feedEvent {
        case .groupEvent, .collapsedGroupEvents:
            bubble.backgroundColor = isThemed ? UIColor.feedPostEventThemedBg : UIColor.feedPostEventDefaultBg
            textLabel.textColor = isThemed ? UIColor.feedPostEventText : UIColor.primaryBlackWhite.withAlphaComponent(0.6)
        case .deletedPost, .collapsedDeletedPosts:
            bubble.backgroundColor = UIColor.feedPostEventDeletedBg
            textLabel.textColor = .secondaryLabel
        }
        self.onTap = onTap
    }
    
    @objc func tapAction() {
        onTap?()
    }
    
    private static let sizingLabel = makeLabel(alignment: .natural, isMultiLine: true)
    private static let directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 50, bottom: 8, trailing: 50)
    private static let bubbleMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    let textLabel = makeLabel(alignment: .center, isMultiLine: true)
    var onTap: (() -> Void)?
    private let bubble = makeBubble()

    private func commonInit() {
        contentView.directionalLayoutMargins = Self.directionalLayoutMargins

        bubble.addSubview(textLabel)
        contentView.addSubview(bubble)

        textLabel.isUserInteractionEnabled = true
        textLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAction)))
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

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributes.size.height = Self.height(for: textLabel.text ?? "", width: layoutAttributes.size.width)
        return layoutAttributes
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
            return  NSLocalizedString("post.has.been.deleted.by.you",
                                      value: "You deleted your post",
                                      comment: "Displayed in place of a deleted feed post.")
        } else {
            let name = UserProfile.findOrCreate(with: userID, in: MainAppContext.shared.mainDataStore.viewContext).displayName
            if name.isEmpty {
                return deletedPostGeneric
            } else {
                let format = NSLocalizedString("post.has.been.deleted.by.author",
                                               value: "%@ deleted their post",
                                               comment: "Displayed in place of a deleted feed post.")
                return String(format: format, name)
            }

            let format = NSLocalizedString("post.has.been.deleted.by.author", value: "%@ deleted their post", comment: "Displayed in place of a deleted feed post.")
            return String(format: format, name)
        }
    }

    static var deletedPostGeneric: String {
        return NSLocalizedString("post.has.been.deleted", value: "This post has been deleted", comment: "Displayed in place of a deleted feed post.")
    }
}
