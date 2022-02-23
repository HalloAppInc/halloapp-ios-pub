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
            // when animating, align contents to top so that initial resize puts more content below the fold.
            textLabel.contentMode = .top
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

    private var audioView: PostAudioView?
    private var mediaView: MediaCarouselView?
    private var postLinkPreviewView: PostLinkPreviewView?
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

        let media = MainAppContext.shared.feedData.media(for: post)
        let imageAndVideoMedia = media.filter { [.image, .video].contains($0.type) }
        let showMediaCarousel = !imageAndVideoMedia.isEmpty

        // Media

        if showMediaCarousel {
            let mediaViewHeight = MediaCarouselView.preferredHeight(for: imageAndVideoMedia, width: contentWidth)
            let index = displayData?.currentMediaIndex ?? 0
            DDLogInfo("FeedItemContentView/media-view-height post=[\(post.id)] height=[\(mediaViewHeight)]")

            if let mediaView = mediaView, mediaView.configuration.gutterWidth == gutterWidth {
                mediaViewHeightConstraint?.constant = mediaViewHeight
                mediaView.refreshData(media: imageAndVideoMedia, index: index, animated: false)
            } else {
                mediaView?.removeFromSuperview()
                var config = MediaCarouselViewConfiguration.default
                config.gutterWidth = gutterWidth
                let mediaView = MediaCarouselView(media: imageAndVideoMedia, initialIndex: index, configuration: config)
                mediaView.delegate = self
                mediaViewHeightConstraint = mediaView.heightAnchor.constraint(equalToConstant: mediaViewHeight)
                mediaViewHeightConstraint?.isActive = true
                self.mediaView = mediaView
            }
            if let mediaView = mediaView {
                vStack.insertArrangedSubview(mediaView, at: 0)
            } else {
                DDLogError("FeedItemContentView/unexpected nil media view")
            }
        } else {
            mediaView?.removeFromSuperview()
        }

        // Audio

        if let audioMedia = media.first(where: { $0.type == .audio }) {
            let audioView = audioView ?? PostAudioView(configuration: .feed)
            self.audioView = audioView
            audioView.delegate = self
            let isOwnPost = post.userId == MainAppContext.shared.userData.userId
            audioView.isSeen = post.status == .seen || isOwnPost
            audioView.feedMedia = audioMedia

            let layoutMargins: NSDirectionalEdgeInsets
            if let mediaView = mediaView, !mediaView.isHidden {
                // Use the same top margin if the media carousel's page control is not displayed
                layoutMargins = NSDirectionalEdgeInsets(top: imageAndVideoMedia.count > 1 ? 8 : 20,
                                                        leading: 0,
                                                        bottom: 20 - LayoutConstants.bottomMarginWithSeparator,
                                                        trailing: 0)
            } else {
                layoutMargins = NSDirectionalEdgeInsets(top: 21 - LayoutConstants.topMargin,
                                                        leading: 0,
                                                        bottom: 26 - LayoutConstants.bottomMarginWithSeparator,
                                                        trailing: 0)
            }
            audioView.directionalLayoutMargins = layoutMargins

            vStack.insertArrangedSubview(audioView, at: vStack.arrangedSubviews.count)
        } else {
            audioView?.removeFromSuperview()
        }

        // Text

        let cryptoResultString: String = FeedItemContentView.obtainCryptoResultString(for: post.id)
        let postTextWithCryptoResult = (post.text ?? "") + cryptoResultString
        let postContainsText = !(postTextWithCryptoResult).isEmpty
        let showTextContentView: Bool
        if post.isPostUnsupported  {
            let text = NSMutableAttributedString(string: "⚠️ " + Localizations.feedPostUnsupported + cryptoResultString)

            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                text.append(NSAttributedString(string: " "))
                text.append(link)
            }

            let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable
            showTextContentView = true
            textLabel.attributedText = text.with(font: font, color: .label)
            textLabel.numberOfLines = 0
        } else if post.isWaiting  {
            let text = NSMutableAttributedString(string: "🕓 " + Localizations.feedPostWaiting)
            let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable
            showTextContentView = true
            textLabel.attributedText = text.with(font: font, color: .label)
            textLabel.numberOfLines = 0
        } else if postContainsText {
            showTextContentView = true
            let defaultNumberOfLines = media.isEmpty ? 10 : 3
            let numberOfLinesToShow = displayData?.textNumberOfLines ?? defaultNumberOfLines

            let postText = MainAppContext.shared.contactStore.textWithMentions(
                postTextWithCryptoResult,
                mentions: post.orderedMentions)
            // With media or > 180 chars long: System 16 pt (Body - 1)
            // Text-only under 180 chars long: System 20 pt (Body + 3)
            let postFont: UIFont = {
                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let fontSizeDiff: CGFloat = media.isEmpty && (postText?.string ?? "").count <= 180 ? 3 : -1
                return UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize + fontSizeDiff)
            }()
            let mentionNameFont = UIFont(descriptor: postFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)

            if let attrText = postText?.with(font: postFont, color: .label) {
                let ham = HAMarkdown(font: postFont, color: .label)
                textLabel.attributedText = ham.parse(attrText).applyingFontForMentions(mentionNameFont)
            }

            textLabel.numberOfLines = numberOfLinesToShow
            // Adjust vertical margins around text.
            textContentView.layoutMargins.top = media.isEmpty ? 9 : 11
        } else {
            showTextContentView = false
        }

        if showTextContentView {
            vStack.insertArrangedSubview(textContentView, at: vStack.arrangedSubviews.count)
        } else {
            textContentView.removeFromSuperview()
        }

        // Link preview

        if let feedLinkPreview = post.linkPreviews?.first, media.isEmpty {
            MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
            let postLinkPreviewView = postLinkPreviewView ?? PostLinkPreviewView()
            self.postLinkPreviewView = postLinkPreviewView
            postLinkPreviewView.configure(feedLinkPreview: feedLinkPreview)
            vStack.insertArrangedSubview(postLinkPreviewView, at: vStack.arrangedSubviews.count)
        } else {
            postLinkPreviewView?.removeFromSuperview()
        }

        // Remove extra spacing
        layoutMargins.bottom = post.hideFooterSeparator ? LayoutConstants.bottomMarginNoSeparator : LayoutConstants.bottomMarginWithSeparator

        postId = post.id
    }

    public static func obtainCryptoResultString(for contentID: String) -> String {
        let cryptoResultString: String
        if ServerProperties.isInternalUser {
            switch AppContext.shared.cryptoData.cryptoResult(for: contentID) {
            case .success:
                cryptoResultString = " ✅"
            case .failure:
                cryptoResultString = " ❌"
            case .none:
                cryptoResultString = ""
            }
        } else {
            cryptoResultString = ""
        }
        return cryptoResultString
    }

    func stopPlayback() {
        if let mediaView = mediaView {
            mediaView.stopPlayback()
        }
        audioView?.pause()
    }

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        didChangeMediaIndex?(newIndex)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(postID: postId) else { return }

        presentMedia(media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(postID: postId) else { return }
        guard media[index].type == .video else { return }

        presentMedia(media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
        guard let postId = postId else { return }
        guard let media = MainAppContext.shared.feedData.media(postID: postId) else { return }
        guard media[index].type == .video else { return }
        guard scale > scaleThreshold else { return }

        presentMedia(media, index: index, delegate: view)
    }

    private func presentMedia(_ media: [FeedMedia], index: Int, delegate transitionDelegate: MediaExplorerTransitionDelegate? = nil) {
        guard let post = feedPost else { return }

        let explorerController = MediaExplorerController(media: media, index: index, canSaveMedia: post.canSaveMedia)
        explorerController.delegate = transitionDelegate

        if let controller = findController() {
            controller.present(explorerController, animated: true)
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

extension FeedItemContentView: PostAudioViewDelegate {

    func postAudioView(_ postAudioView: PostAudioView, didUpdateIsPlayingTo isPlaying: Bool) {
        guard isPlaying, let feedPost = feedPost else {
            return
        }
        MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
        postAudioView.isSeen = true
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

    let avatarButtonSize: CGFloat = 36
    private let avatarButtonSpacing: CGFloat = 8
    private let moreButtonPadding: CGFloat = 20 // padding used to increase the tapping area of button
    private let moreButtonWidth: CGFloat = 18
    private let moreButtonSpacing: CGFloat = 2

    private lazy var avatarViewButton: AvatarViewButton = {
        let avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        avatarViewButton.addTarget(self, action: #selector(showUser), for: .touchUpInside)

        avatarViewButton.widthAnchor.constraint(equalToConstant: avatarButtonSize).isActive = true
        avatarViewButton.heightAnchor.constraint(equalToConstant: avatarButtonSize).isActive = true
        return avatarViewButton
    }()

    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ userAndGroupNameRow, secondLineGroupNameLabel, timestampLabel ])
        view.axis = .vertical
        view.spacing = 3
        view.alignment = .leading
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var groupIndicatorLabel: UILabel = {
        let label = Self.makeLabel()
        label.isHidden = true

        let groupIndicatorImage: UIImage? = UIImage(named: "GroupNameArrow")?.withRenderingMode(.alwaysTemplate).imageFlippedForRightToLeftLayoutDirection()
        let groupIndicatorColor = UIColor(named: "GroupNameArrow") ?? .label

        if let groupIndicator = groupIndicatorImage, let font = label.font {
            let iconAttachment = NSTextAttachment(image: groupIndicator)
            let attrText = NSMutableAttributedString(attachment: iconAttachment)
            attrText.addAttributes([.font: font, .foregroundColor: groupIndicatorColor], range: NSRange(location: 0, length: attrText.length))
            label.attributedText = attrText
        }
        return label
    }()
    
    private lazy var userAndGroupNameRow: UIView = {
        let view = UIView()
        view.addSubview(nameLabel)
        view.addSubview(groupIndicatorLabel)
        view.addSubview(groupNameLabel)

        nameLabel.constrain([.leading, .top, .bottom], to: view)
        groupIndicatorLabel.constrain([.top, .bottom], to: view)
        groupNameLabel.constrain([.top, .bottom, .trailing], to: view)

        groupIndicatorLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4).isActive = true
        groupNameLabel.leadingAnchor.constraint(equalTo: groupIndicatorLabel.trailingAnchor, constant: 4).isActive = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var secondLineGroupNameLabel: UILabel = {
        let label = Self.makeLabel()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        return label
    }()
    
    // Gotham Medium, 15 pt (Subhead)
    private lazy var nameLabel: UILabel = {
        let label = Self.makeLabel()
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUser)))
        return label
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = Self.makeLabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showGroupFeed)))
        return label
    }()

    private static func makeLabel() -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.gothamFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

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
            button.widthAnchor.constraint(equalToConstant: image.size.width + moreButtonPadding).isActive = true
        }

        let wrapperView = UIView()
        wrapperView.addSubview(button)
        wrapperView.translatesAutoresizingMaskIntoConstraints = false

        button.constrain([.top, .bottom, .trailing], to: wrapperView)
        button.heightAnchor.constraint(equalToConstant: 18 + moreButtonPadding).isActive = true

        button.contentHorizontalAlignment = .trailing
        button.imageEdgeInsets = UIEdgeInsets(top: -5, left: 0, bottom: 5, right: 0)

        wrapperView.widthAnchor.constraint(equalToConstant: moreButtonWidth + moreButtonPadding).isActive = true

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
        hStack.spacing = moreButtonSpacing
        hStack.alignment = .leading
        hStack.translatesAutoresizingMaskIntoConstraints = false
 
        addSubview(hStack)

        avatarViewButton.constrain([.top, .leading], to: self)
        avatarViewButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true

        hStack.leadingAnchor.constraint(equalTo: avatarViewButton.trailingAnchor, constant: avatarButtonSpacing).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.constrain(anchor: .centerY, to: avatarViewButton, priority: .defaultLow)

        hStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        hStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true

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

    func refreshTimestamp(with post: FeedPost) {
        timestampLabel.text = post.timestamp.feedTimestamp()
    }

    func configure(with post: FeedPost, contentWidth: CGFloat, showGroupName: Bool, showArchivedDate: Bool = false) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: post.userId)
        if showArchivedDate {
            let archivedDate = post.timestamp.addingTimeInterval(Date.days(30))
            timestampLabel.text = (timestampLabel.text ?? "") + " • " + Localizations.feedPostArchivedTimestamp(time: archivedDate.shortDateFormat())
        }

        avatarViewButton.avatarView.configure(with: post.userId, using: MainAppContext.shared.avatarStore)
        
        moreButton.isHidden = !(post.hasSaveablePostMedia && post.canSaveMedia) && post.userId != MainAppContext.shared.userData.userId
        configureGroupLabel(with: post.groupId, contentWidth: contentWidth, showGroupName: showGroupName)
        refreshTimestamp(with: post)
    }

    func configureGroupLabel(with groupID: String?, contentWidth: CGFloat, showGroupName: Bool) {
        guard let groupID = groupID, let groupChat = MainAppContext.shared.chatData.chatGroup(groupId: groupID), showGroupName else {
            groupNameLabel.isHidden = true
            secondLineGroupNameLabel.isHidden = true
            groupIndicatorLabel.isHidden = true
            return
        }

        groupNameLabel.text = groupChat.name
        secondLineGroupNameLabel.text = groupChat.name

        let shouldShowTwoLines = isRowTruncated(contentWidth: contentWidth)
        groupNameLabel.isHidden = shouldShowTwoLines
        secondLineGroupNameLabel.isHidden = !shouldShowTwoLines
        groupIndicatorLabel.isHidden = false
    }
    
    func prepareForReuse() {
        avatarViewButton.avatarView.prepareForReuse()
        groupNameLabel.text = nil
        groupNameLabel.isHidden = true
        groupIndicatorLabel.isHidden = true
        secondLineGroupNameLabel.text = nil
        secondLineGroupNameLabel.isHidden = true
    }

    @objc func showUser() {
        showUserAction?()
    }
    
    @objc func showGroupFeed() {
        showGroupFeedAction?()
    }

    private func isRowTruncated(contentWidth: CGFloat) -> Bool {
        var requiredWidth = userAndGroupNameRow.systemLayoutSizeFitting(CGSize(width: contentWidth, height: 20)).width
        requiredWidth += moreButton.isHidden ? 0 : (moreButtonWidth + moreButtonPadding + moreButtonSpacing)
        requiredWidth += avatarButtonSize + avatarButtonSpacing

        return requiredWidth > contentWidth
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
        let isLTR = self.effectiveUserInterfaceLayoutDirection == .leftToRight
        let spacing: CGFloat = isLTR ? 4 : -4
        let stringComment = NSLocalizedString("feedpost.button.comment", value: "Comment", comment: "Button under someone's post. Verb.")
        let button = ButtonWithBadge(type: .system)
        button.setTitle(stringComment, for: .normal)
        button.setImage(UIImage(named: "FeedPostComment"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .footnote, weight: .medium, maximumPointSize: 18)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        if isLTR {
            button.contentEdgeInsets.left = 20
        } else {
            button.contentEdgeInsets.right = 20
        }
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        button.contentHorizontalAlignment = .leading
        return button
    }()

    // Gotham Medium, 15 pt (Subhead)
    lazy var messageButton: UIButton = {
        let isLTR = self.effectiveUserInterfaceLayoutDirection == .leftToRight
        let spacing: CGFloat = isLTR ? 6 : -6
        let stringMessage = NSLocalizedString("feedpost.button.reply", value: "Reply Privately", comment: "Button under someoneelse's post. Verb.")
        let button = UIButton(type: .system)
        button.setTitle(stringMessage, for: .normal)
        button.setImage(UIImage(named: "FeedPostReply"), for: .normal)
        button.titleLabel?.font = UIFont.gothamFont(forTextStyle: .footnote, weight: .medium, maximumPointSize: 18)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets.top = 15
        button.contentEdgeInsets.bottom = 9
        if isLTR {
            button.contentEdgeInsets.right = 20
        } else {
            button.contentEdgeInsets.left = 20
        }
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing/2, bottom: 0, right: -spacing/2)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing/2, bottom: 0, right: spacing/2)
        button.contentHorizontalAlignment = .trailing
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
            showProgressView(post)
            hideErrorView()

            if let count = post.media?.count, count > 0 {
                let postId = post.id
                let mediaUploader = MainAppContext.shared.feedData.mediaUploader

                progressView.isIndeterminate = false

                processingProgressCancellable = ImageServer.shared.progress.receive(on: DispatchQueue.main).sink { [weak self] id in
                    guard let self = self else { return }
                    guard postId == id else { return }
                    self.updateSendingProgress(for: post)
                }

                uploadProgressCancellable = mediaUploader.uploadProgressDidChange.receive(on: DispatchQueue.main).sink { [weak self] groupId in
                    guard let self = self else { return }
                    guard postId == groupId else { return }
                    self.updateSendingProgress(for: post)
                }

                updateSendingProgress(for: post)
            } else {
                progressView.progress = 0.5
            }
        case .error:
            showSendErrorView()
            hideProgressView()
        }
    }

    private func updateSendingProgress(for post: FeedPost) {
        guard let count = post.media?.count, count > 0 else { return }

        var (processingCount, processingProgress) = ImageServer.shared.progress(for: post.id)
        var (uploadCount, uploadProgress) = MainAppContext.shared.feedData.mediaUploader.uploadProgress(forGroupId: post.id)

        processingProgress = processingProgress * Float(processingCount) / Float(count)
        uploadProgress = uploadProgress * Float(uploadCount) / Float(count)

        progressView.progress = (processingProgress + uploadProgress) / 2
    }

    func prepareForReuse() {
        uploadProgressCancellable?.cancel()
        uploadProgressCancellable = nil

        facePileView.prepareForReuse()
    }

    // MARK: Upload Progress

    static private let progressViewTag = 1

    private var processingProgressCancellable: AnyCancellable?
    private var uploadProgressCancellable: AnyCancellable?

    private lazy var progressView: PostingProgressView = {
        let view = PostingProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)
        view.tag = Self.progressViewTag
        view.cancelButton.addTarget(self, action: #selector(cancelButtonAction), for: .touchUpInside)
        return view
    }()

    private func showProgressView(_ post: FeedPost) {
        if progressView.superview == nil {
            addSubview(progressView)
            progressView.constrain(to: buttonStack)
        }
        
        progressView.configure(with: post)
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
        deleteButton.widthAnchor.constraint(equalTo: deleteButton.heightAnchor).isActive = true
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
    
    /**
    Used to display the appropriate progress indicator when making a post.
         
    For posts that consist of *only* text, there will be no progress bar.
    */
    func configure(with post: FeedPost) {
        let media = post.media
        let isTextPost = media?.isEmpty ?? true

        isIndeterminate = isTextPost

        switch post.status {
        case .retracting:
            textLabel.text = Localizations.feedDeleting
        default:
            textLabel.text = Localizations.feedPosting
        }
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
    static var feedPostWaiting: String {
        NSLocalizedString("feed.post.waiting", value: "Waiting for this post. This may take a while.", comment: "Text shown in place of a received post we are not able to decrypt yet.")
    }
    static var feedCommentWaiting: String {
        NSLocalizedString("feed.comment.waiting", value: "Waiting for this comment. This may take a while.", comment: "Text shown in place of a received post we are not able to decrypt yet.")
    }
    static func feedPostArchivedTimestamp(time: String) -> String {
        let formatString = NSLocalizedString("feed.post.archived.timestamp", value: "Archived %@", comment: "Archived date timestamp")
        return String(format: formatString, time)
    }
}
