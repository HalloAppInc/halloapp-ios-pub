//
//  FeedItemContentView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import UIKit

fileprivate extension FeedPost {
    var hideFooterSeparator: Bool {
        !orderedMedia.isEmpty && text?.isEmpty ?? true
    }
}

final class FeedItemBackgroundPanelView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.backgroundColor = UIColor.feedPostBackground
        self.layer.shadowRadius = 8
        self.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.layer.shadowColor = UIColor.feedPostShadow.cgColor
        self.updateShadowPath()
    }

    override var bounds: CGRect {
        didSet { updateShadowPath() }
    }

    override var frame: CGRect {
        didSet { updateShadowPath() }
    }

    var isShadowHidden: Bool = false {
        didSet { self.layer.shadowOpacity = isShadowHidden ? 0 : 1.0 }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { self.layer.cornerRadius = cornerRadius }
    }

    private func updateShadowPath() {
        // Explicitly set shadow's path for better performance.
        self.layer.shadowPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: cornerRadius).cgPath
    }
}

final class FeedItemContentView: UIView, MediaCarouselViewDelegate {

    private let scaleThreshold: CGFloat = 1.3
    private var postId: FeedPostID? = nil
    private var feedPost: FeedPost?

    private enum LayoutConstants {
        static let topMargin: CGFloat = 5
        static let bottomMarginWithSeparator: CGFloat = 8
        static let bottomMarginNoSeparator: CGFloat = 2
    }

    private class TextContentView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        let textLabel = TextLabel()

        private func commonInit() {
            textLabel.textColor = .label
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textLabel)
            textLabel.constrainMargins(to: self)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private var vStack: UIStackView!

    private var textContentView: TextContentView!

    var textLabel: TextLabel! {
        textContentView.textLabel
    }

    private var mediaView: MediaCarouselView?
    private var mediaViewHeightConstraint: NSLayoutConstraint?

    var didChangeMediaIndex: ((Int) -> Void)?

    private func setupView() {
        isUserInteractionEnabled = true
        layoutMargins = UIEdgeInsets(top: LayoutConstants.topMargin, left: 0, bottom: LayoutConstants.bottomMarginWithSeparator, right: 0)

        textContentView = TextContentView()
        textContentView.translatesAutoresizingMaskIntoConstraints = false

        vStack = UIStackView(arrangedSubviews: [ textContentView ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        addSubview(vStack)
        vStack.constrainMargins(to: self)
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, displayData: FeedPostDisplayData?) {
        feedPost = post

        // TODO: Make media view reusable (it hurts scroll performance to reinitialize for each post)
        if let mediaView = mediaView {
            let keepMediaView = postId == post.id && mediaView.configuration.gutterWidth == gutterWidth
            if !keepMediaView {
                vStack.removeArrangedSubview(mediaView)
                mediaView.removeFromSuperview()
                self.mediaView = nil
            } else {
                DDLogInfo("FeedItemContentView/reuse-media-view post=[\(post.id)]")
            }
        }

        let media = MainAppContext.shared.feedData.media(for: post)
        if !media.isEmpty {
            let mediaViewHeight = MediaCarouselView.preferredHeight(for: media, width: contentWidth)
            DDLogInfo("FeedItemContentView/media-view-height post=[\(post.id)] height=[\(mediaViewHeight)]")
            if mediaView == nil {
                // Create new media view
                var mediaViewConfiguration = MediaCarouselViewConfiguration.default
                mediaViewConfiguration.gutterWidth = gutterWidth
                let mediaView = MediaCarouselView(media: media, initialIndex: displayData?.currentMediaIndex, configuration: mediaViewConfiguration)
                mediaView.delegate = self
                mediaViewHeightConstraint = {
                    let constraint = mediaView.heightAnchor.constraint(equalToConstant: mediaViewHeight)
                    constraint.priority = .required - 10
                    return constraint
                }()
                mediaViewHeightConstraint?.isActive = true
                vStack.insertArrangedSubview(mediaView, at: 0)
                self.mediaView = mediaView
            } else {
                // Update height on existing media view
                mediaViewHeightConstraint?.constant = mediaViewHeight
            }
        }

        let postContainsText = !(post.text ?? "").isEmpty
        if post.isPostUnsupported  {
            let text = NSMutableAttributedString(string: "⚠️ " + Localizations.feedPostUnsupported)

            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                text.append(NSAttributedString(string: " "))
                text.append(link)
            }

            let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable

            textContentView.isHidden = false
            textLabel.attributedText = text.with(font: font, color: .label)
            textLabel.numberOfLines = 0
        } else if postContainsText {
            textContentView.isHidden = false
            let isTextExpanded = displayData?.isTextExpanded ?? false

            let postText = MainAppContext.shared.contactStore.textWithMentions(
                post.text,
                mentions: post.orderedMentions)
            // With media or > 180 chars long: System 16 pt (Body - 1)
            // Text-only under 180 chars long: System 20 pt (Body + 3)
            let postFont: UIFont = {
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let fontSizeDiff: CGFloat = media.isEmpty && (postText?.string ?? "").count <= 180 ? 3 : -1
                return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
            }()
            let mentionNameFont = UIFont(descriptor: postFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
            textLabel.attributedText = postText?.with(font: postFont, color: .label).applyingFontForMentions(mentionNameFont)
            textLabel.numberOfLines = isTextExpanded ? 0 : media.isEmpty ? 10 : 3
            // Adjust vertical margins around text.
            textContentView.layoutMargins.top = media.isEmpty ? 9 : 11
        } else {
            textContentView.isHidden = true
        }

        // Remove extra spacing
        layoutMargins.bottom = post.hideFooterSeparator ? LayoutConstants.bottomMarginNoSeparator : LayoutConstants.bottomMarginWithSeparator

        postId = post.id
    }

    private static var textContentViewForSizing = { TextContentView() }()

    // TODO: Optimize the `configure` function so we can just measure a view instead of duplicating all the layout logic.
    class func preferredHeight(forPost post: FeedPost, contentWidth: CGFloat, gutterWidth: CGFloat, displayData: FeedPostDisplayData?) -> CGFloat {
        var contentHeight = LayoutConstants.topMargin

        let media = MainAppContext.shared.feedData.media(for: post)
        if !media.isEmpty {
            contentHeight += MediaCarouselView.preferredHeight(for: media, width: contentWidth)
        }

        let textContentView: TextContentView? = {
            let postContainsText = !(post.text ?? "").isEmpty
            if post.isPostUnsupported  {
                let text = NSMutableAttributedString(string: "⚠️ " + Localizations.feedPostUnsupported)

                if let url = AppContext.appStoreURL {
                    let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                    link.addAttribute(.link, value: url, range: link.utf16Extent)
                    text.append(NSAttributedString(string: " "))
                    text.append(link)
                }

                let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable

                let textContentView = textContentViewForSizing
                textContentView.textLabel.attributedText = text.with(font: font, color: .label)
                textContentView.textLabel.numberOfLines = 0
                textContentView.layoutMargins.top = 8

                return textContentView
            } else if postContainsText {
                let isTextExpanded = displayData?.isTextExpanded ?? false
                let postText = MainAppContext.shared.contactStore.textWithMentions(
                    post.text,
                    mentions: post.orderedMentions)
                let postFont: UIFont = {
                    let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                    let fontSizeDiff: CGFloat = media.isEmpty && (postText?.string ?? "").count <= 180 ? 3 : -1
                    return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
                }()

                let textContentView = textContentViewForSizing
                textContentView.textLabel.attributedText = postText?.with(font: postFont, color: .label)
                textContentView.textLabel.numberOfLines = isTextExpanded ? 0 : media.isEmpty ? 10 : 3
                // Adjust vertical margins around text.
                textContentView.layoutMargins.top = media.isEmpty ? 9 : 11

                return textContentView
            } else {
                return nil
            }
        }()

        if let textContentView = textContentView {
            let targetSize = CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height)
            let textContentViewSize = textContentView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)

            contentHeight += textContentViewSize.height
        }

        contentHeight += post.hideFooterSeparator ? LayoutConstants.bottomMarginNoSeparator : LayoutConstants.bottomMarginWithSeparator
        return contentHeight
    }

    func prepareForReuse() { }

    func stopPlayback() {
        if let mediaView = mediaView {
            mediaView.stopPlayback()
        }
    }

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        didChangeMediaIndex?(newIndex)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(for: postId) else { return }

        presentExplorer(media: media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(for: postId) else { return }
        guard media[index].type == .video else { return }

        presentExplorer(media: media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(for: postId) else { return }
        guard media[index].type == .video else { return }
        guard scale > scaleThreshold else { return }

        presentExplorer(media: media, index: index, delegate: view)
    }

    private func presentExplorer(media: [FeedMedia], index: Int, delegate: MediaExplorerTransitionDelegate? = nil) {
        guard let post = feedPost else { return }
        let explorerController = MediaExplorerController(media: media, index: index, canSaveMedia: post.canSaveMedia)
        explorerController.delegate = delegate

        if let controller = findController() {
            controller.present(explorerController.withNavigationController(), animated: true)
        }
    }

    private func findController() -> UIViewController? {
        var current: UIResponder? = self

        while current != nil && !(current is UIViewController) {
            current = current?.next
        }

        return current as? UIViewController
    }
}


final class FeedItemHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    var showUserAction: (() -> ())? = nil
    var showGroupFeedAction: (() -> ())? = nil
    var showMoreAction: (() -> ())? = nil

    private var contentSizeCategoryDidChangeCancellable: AnyCancellable!

    private lazy var avatarViewButton: AvatarViewButton = {
        let avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        avatarViewButton.addTarget(self, action: #selector(showUser), for: .touchUpInside)
        return avatarViewButton
    }()

    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ userAndGroupNameRow, secondLineGroupNameLabel, timestampLabel ])
        view.axis = .vertical
        view.spacing = 3
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var userAndGroupNameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, groupNameLabel ])
        view.axis = .horizontal
        view.spacing = 4
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var secondLineGroupNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 20, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        label.isHidden = true
        return label
    }()
    
    // Gotham Medium, 15 pt (Subhead)
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUser)))
        return label
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow - 20, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        label.isHidden = true
        return label
    }()

    // Gotham Medium, 13 pt
    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(forTextStyle: .footnote, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(named: "TimestampLabel")
        label.textAlignment = .natural
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal) // higher than contact name
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var moreButton: UIView = {
        let image = UIImage(systemName: "ellipsis")
        let button = UIButton()
        button.setImage(image, for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(showMoreTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        if let image = image {
            button.widthAnchor.constraint(equalToConstant: image.size.width).isActive = true
        }
        
        let wrapperView = UIView()
        wrapperView.addSubview(button)
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        
        button.topAnchor.constraint(equalTo: wrapperView.topAnchor).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        
        wrapperView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        
        return wrapperView
    }()
    
    @objc private func showMoreTapped() {
        if let action = showMoreAction {
            action()
        }
    }

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(avatarViewButton)

        let hStack = UIStackView(arrangedSubviews: [ nameColumn, moreButton ])
        hStack.axis = .horizontal
        hStack.spacing = 4
        hStack.translatesAutoresizingMaskIntoConstraints = false
 
        addSubview(hStack)

        avatarViewButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        avatarViewButton.heightAnchor.constraint(equalTo: avatarViewButton.widthAnchor).isActive = true
        avatarViewButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        avatarViewButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalToSystemSpacingAfter: avatarViewButton.trailingAnchor, multiplier: 1).isActive = true
        hStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        hStack.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        moreButton.topAnchor.constraint(equalTo: hStack.topAnchor).isActive = true

        contentSizeCategoryDidChangeCancellable = NotificationCenter.default
            .publisher(for: UIContentSizeCategory.didChangeNotification)
            .compactMap { $0.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? UIContentSizeCategory }
            .sink { [weak self] category in
                guard let self = self else { return }
                self.configure(stackView: hStack, forVerticalLayout: category.isAccessibilityCategory)
        }
    }

    private func configure(stackView: UIStackView, forVerticalLayout verticalLayout: Bool) {
        if verticalLayout {
            stackView.axis = .vertical
            stackView.alignment = .fill
        } else {
            stackView.axis = .horizontal
            stackView.alignment = .center
        }
    }

    func configure(with post: FeedPost) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: post.userId)
        timestampLabel.text = post.timestamp.feedTimestamp()
        avatarViewButton.avatarView.configure(with: post.userId, using: MainAppContext.shared.avatarStore)
        
        moreButton.isHidden = !post.canSaveMedia && post.userId != MainAppContext.shared.userData.userId
    }
    
    func configureGroupLabel(with groupID: String?) {
        if let groupID = groupID, let groupChat = MainAppContext.shared.chatData.chatGroup(groupId: groupID) {
            
            let attrText = NSMutableAttributedString(string: "")
            let groupNameColor = UIColor.label
            let groupIndicatorImage: UIImage? = UIImage(named: "GroupNameArrow")?.withRenderingMode(.alwaysTemplate)
            let groupIndicatorColor = UIColor(named: "GroupNameArrow") ?? groupNameColor

            if let groupIndicator = groupIndicatorImage, let font = groupNameLabel.font {
                let iconAttachment = NSTextAttachment(image: groupIndicator)
                attrText.append(NSAttributedString(attachment: iconAttachment))

                attrText.addAttributes([.font: font, .foregroundColor: groupIndicatorColor], range: NSRange(location: 0, length: attrText.length))

                let groupNameAttributes = [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: groupNameColor]
                let groupNameAttributedStr = NSAttributedString(string: " \(groupChat.name)", attributes: groupNameAttributes)
                attrText.append(groupNameAttributedStr)
            }

            groupNameLabel.attributedText = attrText

            if isRowTruncated() {
                let shortAttrText = attrText.mutableCopy() as! NSMutableAttributedString
                let range = (shortAttrText.string as NSString).range(of: " \(groupChat.name)")
                shortAttrText.deleteCharacters(in: range)
                groupNameLabel.attributedText = shortAttrText

                let secondLineGroupNameAttributedStr = NSAttributedString(string: "\(groupChat.name)")
                secondLineGroupNameLabel.attributedText = secondLineGroupNameAttributedStr
                secondLineGroupNameLabel.isHidden = false
            } else {
                secondLineGroupNameLabel.isHidden = true
            }
            groupNameLabel.isHidden = false
        }
    }
    
    func prepareForReuse() {
        avatarViewButton.avatarView.prepareForReuse()
        groupNameLabel.attributedText = nil
        groupNameLabel.textColor = .label
        groupNameLabel.isHidden = true
        secondLineGroupNameLabel.attributedText = nil
        secondLineGroupNameLabel.isHidden = true
    }

    @objc func showUser() {
        showUserAction?()
    }
    
    @objc func showGroupFeed() {
        showGroupFeedAction?()
    }

    private func isRowTruncated() -> Bool {
        var totalTextWidth = getLabelTextWidth(nameLabel)
        totalTextWidth += getLabelTextWidth(groupNameLabel)
        
        if !moreButton.isHidden {
            totalTextWidth += moreButton.frame.width
        }
        
        totalTextWidth += avatarViewButton.frame.width + 65 // rough estimate of avatar, margins, paddings, etc.
        
        if totalTextWidth > UIScreen.main.bounds.size.width {
            return true
        } else {
            return false
        }
    }
    
    private func getLabelTextWidth(_ label: UILabel) -> CGFloat {
        let text = NSString(string: label.text ?? "")
        let attr = [NSAttributedString.Key.font: label.font]
        let size = text.size(withAttributes: attr as [NSAttributedString.Key : Any])
        return size.width
    }
}

final class FeedItemFooterView: UIView {

    class ButtonWithBadge: UIButton {

        enum BadgeState {
            case hidden
            case unread
            case read
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.setupView()
        }

        var badge: BadgeState = .hidden {
            didSet {
                switch self.badge {
                case .hidden:
                    self.badgeView.isHidden = true

                case .unread:
                    self.badgeView.isHidden = false
                    self.badgeView.fillColor = UIColor.commentIndicatorUnread
                    self.badgeView.alpha = 1.0

                case .read:
                    self.badgeView.isHidden = false
                    self.badgeView.fillColor = .systemGray4
                    self.badgeView.alpha = 1.0
                }
            }
        }

        private let badgeView = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: 7, height: 7)))

        private func setupView() {
            self.addSubview(badgeView)
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            guard let titleLabel = self.titleLabel else { return }

            let spacing: CGFloat = 6
            let spacingToCenter = spacing + badgeView.bounds.width/2
            let badgeCenterX: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? titleLabel.frame.maxX + spacingToCenter : titleLabel.frame.minX - spacingToCenter
            self.badgeView.center = self.badgeView.alignedCenter(from: CGPoint(x: badgeCenterX, y: titleLabel.frame.midY))
        }

    }

    private enum SenderCategory {
        case ownPost
        case contact
        case nonContact
    }

    private enum State: Equatable {
        case normal(SenderCategory)
        case sending
        case retracting
        case error
    }

    var deleteAction: (() -> ())?
    var cancelAction: (() -> ())?
    var retryAction: (() -> ())?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // Gotham Medium, 15 pt (Subhead)
    lazy var commentButton: ButtonWithBadge = {
        let spacing: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? 6 : -6
        let stringComment = NSLocalizedString("feedpost.button.comment", value: "Comment", comment: "Button under someone's post. Verb.")
        let button = ButtonWithBadge(type: .system)
        button.setTitle(stringComment, for: .normal)
        button.setImage(UIImage(named: "FeedPostComment"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium, maximumPointSize: 18)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        return button
    }()

    // Gotham Medium, 15 pt (Subhead)
    lazy var messageButton: UIButton = {
        let spacing: CGFloat = self.effectiveUserInterfaceLayoutDirection == .leftToRight ? 8 : -8
        let stringMessage = NSLocalizedString("feedpost.button.reply", value: "Reply", comment: "Button under someoneelse's post. Verb.")
        let button = UIButton(type: .system)
        button.setTitle(stringMessage, for: .normal)
        button.setImage(UIImage(named: "FeedPostReply"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium, maximumPointSize: 18)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        return button
    }()

    lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()

    lazy var separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }()

    var buttonStack: UIStackView!

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(separator)

        separator.topAnchor.constraint(equalTo: topAnchor).isActive = true
        // Horizontal size / position constraints will be installed by the cell.

        buttonStack = UIStackView(arrangedSubviews: [ commentButton, messageButton ])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 24
        addSubview(buttonStack)
        buttonStack.constrain(to: self)

        addSubview(facePileView)
        facePileView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        facePileView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4).isActive = true
    }

    private class func senderCategory(for post: FeedPost) -> SenderCategory {
        if post.userId == MainAppContext.shared.userData.userId {
            return .ownPost
        }
        if MainAppContext.shared.contactStore.isContactInAddressBook(userId: post.userId) {
            return .contact
        }
        return .nonContact
    }

    private class func state(for post: FeedPost) -> State {
        switch post.status {
        case .sending: return .sending
        case .sendError: return .error
        case .retracting: return .retracting
        default: return .normal(senderCategory(for: post))
        }
    }

    func configure(with post: FeedPost, contentWidth: CGFloat) {
        let state = Self.state(for: post)

        buttonStack.isHidden = state == .sending || state == .error || state == .retracting
        facePileView.isHidden = true
        separator.isHidden = post.hideFooterSeparator

        switch state {
        case .normal(let sender):
            hideProgressView()
            hideErrorView()

            commentButton.badge = (post.comments ?? []).isEmpty ? .hidden : (post.unreadCount > 0 ? .unread : .read)
            messageButton.alpha = sender == .contact ? 1 : 0
            if sender == .ownPost {
                facePileView.isHidden = false
                facePileView.configure(with: post)
            }
        case .sending, .retracting:
            showProgressView()
            hideErrorView()

            let postId = post.id
            let mediaUploader = MainAppContext.shared.feedData.mediaUploader

            if mediaUploader.hasTasks(forGroupId: postId) {
                progressView.isIndeterminate = false

                if uploadProgressCancellable == nil {
                    uploadProgressCancellable = mediaUploader.uploadProgressDidChange.sink { [weak self] (groupId, progress) in
                        guard let self = self else { return }
                        if postId == groupId {
                            self.progressView.progress = progress
                        }
                    }
                    progressView.progress = mediaUploader.uploadProgress(forGroupId: postId)
                }
            } else {
                progressView.isIndeterminate = true
                progressView.indeterminateProgressText = state == .sending ? Localizations.feedPosting : Localizations.feedDeleting
            }
        case .error:
            showSendErrorView()
            hideProgressView()
        }
    }

    func prepareForReuse() {
        uploadProgressCancellable?.cancel()
        uploadProgressCancellable = nil

        facePileView.prepareForReuse()
    }

    // MARK: Upload Progress

    static private let progressViewTag = 1

    private var uploadProgressCancellable: AnyCancellable?

    private lazy var progressView: PostingProgressView = {
        let view = PostingProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)
        view.tag = Self.progressViewTag
        view.cancelButton.addTarget(self, action: #selector(cancelButtonAction), for: .touchUpInside)
        return view
    }()

    private func showProgressView() {
        if progressView.superview == nil {
            addSubview(progressView)
            progressView.constrain(to: buttonStack)
        }
        progressView.isHidden = false
    }

    private func hideProgressView() {
        uploadProgressCancellable?.cancel()
        uploadProgressCancellable = nil

        subviews.first(where: { $0.tag == Self.progressViewTag })?.isHidden = true
    }

    @objc private func cancelButtonAction() {
        cancelAction?()
    }

    // MARK: Error / retry View

    static private let errorViewTag = 2

    private lazy var errorView: UIView = {
        let errorText = UILabel()
        errorText.translatesAutoresizingMaskIntoConstraints = false
        errorText.font = .preferredFont(forTextStyle: .subheadline)
        errorText.numberOfLines = 0
        errorText.textColor = .systemRed
        errorText.text = Localizations.feedPostFailed

        let deleteButton = UIButton(type: .system)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setImage(UIImage(systemName: "trash.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline)), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteButtonAction), for: .touchUpInside)

        let retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setImage(UIImage(systemName: "arrow.counterclockwise.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
        retryButton.addTarget(self, action: #selector(retryButtonAction), for: .touchUpInside)

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)
        view.tag = Self.errorViewTag
        view.addSubview(errorText)
        view.addSubview(deleteButton)
        view.addSubview(retryButton)

        errorText.constrainMargins([ .leading, .top, .bottom ], to: view)

        deleteButton.constrainMargins([ .top, .bottom ], to: view)
        deleteButton.widthAnchor.constraint(equalTo: retryButton.heightAnchor).isActive = true
        deleteButton.leadingAnchor.constraint(equalToSystemSpacingAfter: errorText.trailingAnchor, multiplier: 1).isActive = true

        retryButton.constrainMargins([ .trailing, .top, .bottom ], to: view)
        retryButton.widthAnchor.constraint(equalTo: retryButton.heightAnchor).isActive = true
        retryButton.leadingAnchor.constraint(equalToSystemSpacingAfter: deleteButton.trailingAnchor, multiplier: 1).isActive = true

        return view
    }()

    private func showSendErrorView() {
        if errorView.superview == nil {
            addSubview(errorView)
            errorView.constrain(to: buttonStack)
        }
        errorView.isHidden = false
    }

    private func hideErrorView() {
        subviews.first(where: { $0.tag == Self.errorViewTag })?.isHidden = true
    }

    @objc private func retryButtonAction() {
        retryAction?()
    }

    @objc private func deleteButtonAction() {
        deleteAction?()
    }
}

class PostingProgressView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    var isIndeterminate = false {
        didSet {
            progressView.isHidden = isIndeterminate
            cancelButton.isHidden = isIndeterminate
            textLabel.isHidden = !isIndeterminate
            if isIndeterminate {
                activityIndicatorView.startAnimating()
            } else {
                activityIndicatorView.stopAnimating()
            }
        }
    }

    var progress: Float {
        get { progressView.progress }
        set { progressView.progress = newValue }
    }

    var indeterminateProgressText: String? {
        get { textLabel.text }
        set { textLabel.text = newValue }
    }

    lazy private var progressView = UIProgressView(progressViewStyle: .default)
    lazy private var textLabel: UILabel = {
        let label = UILabel()
        label.text = Localizations.feedPosting
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }()
    lazy private var activityIndicatorView = UIActivityIndicatorView()
    lazy private(set) var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline)), for: .normal)
        return button
    }()

    private func commonInit() {
        addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.constrainMargin(anchor: .leading, to: self)
        progressView.centerYAnchor.constraint(equalTo: self.layoutMarginsGuide.centerYAnchor).isActive = true

        addSubview(textLabel)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.constrain([ .leading, .trailing ], to: progressView)
        textLabel.constrainMargins([ .top, .bottom ], to: self)

        addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.constrainMargins([ .trailing, .top, .bottom ], to: self)
        cancelButton.widthAnchor.constraint(equalTo: cancelButton.heightAnchor).isActive = true
        cancelButton.leadingAnchor.constraint(equalToSystemSpacingAfter: progressView.trailingAnchor, multiplier: 2).isActive = true

        addSubview(activityIndicatorView)
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.centerXAnchor.constraint(equalTo: cancelButton.centerXAnchor).isActive = true
        activityIndicatorView.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor).isActive = true
    }
}

extension Localizations {
    static var feedPosting: String {
        NSLocalizedString("feed.posting", value: "Posting...", comment: "Shown while content is being posted to feed")
    }
    static var feedDeleting: String {
        NSLocalizedString("feed.deleting", value: "Deleting...", comment: "Shown while content is being retracted from feed")
    }
    static var feedPostFailed: String {
        NSLocalizedString("feed.post.failed", value: "Failed to post.", comment: "Shown when post fails or is canceled.")
    }
    static var feedPostUnsupported: String {
        NSLocalizedString("feed.post.unsupported", value: "Your version of HalloApp does not support this type of post.", comment: "Shown when receiving a new (unsupported) type of post.")
    }
}
