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
import CoreCommon
import UIKit
import CoreGraphics

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
    private var linkPreviewURL: URL?
    private let mediaCarouselViewConfiguration: MediaCarouselViewConfiguration
    private let maxMediaHeight: CGFloat?

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

        let textView = ExpandableTextView()

        private func commonInit() {
            // when animating, align contents to top so that initial resize puts more content below the fold.
            textView.contentMode = .top
            textView.textColor = .label
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            textView.constrainMargins(to: self)
        }
    }

    init(mediaCarouselViewConfiguration: MediaCarouselViewConfiguration = .default, maxMediaHeight: CGFloat? = nil) {
        self.mediaCarouselViewConfiguration = mediaCarouselViewConfiguration
        self.maxMediaHeight = maxMediaHeight
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        mediaCarouselViewConfiguration = .default
        maxMediaHeight = nil
        super.init(coder: coder)
        setupView()
    }

    private var vStack: UIStackView!

    private var textContentView: TextContentView!

    var textView: ExpandableTextView! {
        textContentView.textView
    }

    private var audioView: PostAudioView?
    private var mediaView: MediaCarouselView?
    private var postLinkPreviewView: PostLinkPreviewView?
    private var mediaViewHeightConstraint: NSLayoutConstraint?

    private var canSaveMedia = false

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

    func configure(with post: FeedPostDisplayable, contentWidth: CGFloat, gutterWidth: CGFloat, displayData: FeedPostDisplayData?) {
        let media = post.feedMedia
        let imageAndVideoMedia = media.filter { [.image, .video].contains($0.type) }
        let showMediaCarousel = !imageAndVideoMedia.isEmpty

        // Media

        if showMediaCarousel {
            let mediaViewHeight = MediaCarouselView.preferredHeight(for: imageAndVideoMedia, width: contentWidth, maxHeight: maxMediaHeight)
            let index = displayData?.currentMediaIndex ?? 0
            DDLogInfo("FeedItemContentView/media-view-height post=[\(post.id)] height=[\(mediaViewHeight)]")

            if let mediaView = mediaView, mediaView.configuration.gutterWidth == gutterWidth {
                mediaViewHeightConstraint?.constant = mediaViewHeight
                mediaView.refreshData(media: imageAndVideoMedia, index: index, animated: false)
            } else {
                mediaView?.removeFromSuperview()
                var config = mediaCarouselViewConfiguration
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
        let postTextWithCryptoResult = (post.rawText ?? "") + cryptoResultString
        let postContainsText = !(postTextWithCryptoResult).isEmpty
        let showTextContentView: Bool
        if post.isUnsupported  {
            let text = NSMutableAttributedString(string: "⚠️ " + Localizations.feedPostUnsupported + cryptoResultString)

            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                text.append(NSAttributedString(string: " "))
                text.append(link)
            }

            let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable
            showTextContentView = true
            textView.attributedText = text.with(font: font, color: .label)
            textView.numberOfLines = 0
        } else if post.isWaiting  {
            let waitingString = "🕓 " + Localizations.feedPostWaiting
            let attributedString = Localizations.appendLearnMoreLabel(to: waitingString)
            let font = UIFont.preferredFont(forTextStyle: .body).withItalicsIfAvailable
            showTextContentView = true
            textView.attributedText = attributedString.with(font: font, color: .label)
            textView.numberOfLines = 0
        } else if postContainsText {
            showTextContentView = true
            let defaultNumberOfLines = media.isEmpty ? 10 : 3
            let numberOfLinesToShow = displayData?.textNumberOfLines ?? defaultNumberOfLines
            let postText = UserProfile.text(with: post.orderedMentions,
                                            collapsedText: postTextWithCryptoResult,
                                            in: MainAppContext.shared.mainDataStore.viewContext)
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

                textView.attributedText = ham.parse(attrText).applyingFontForMentions(mentionNameFont)
                textView.textAlignment = postText?.string.naturalAlignment ?? .natural
            } else {
                
            }

            textView.numberOfLines = numberOfLinesToShow
            // Adjust vertical margins around text.
            textContentView.layoutMargins.top = media.isEmpty ? 9 : 11
            textContentView.textView.backgroundColor = nil
        } else {
            showTextContentView = false
        }

        if showTextContentView {
            vStack.insertArrangedSubview(textContentView, at: vStack.arrangedSubviews.count)
        } else {
            textContentView.removeFromSuperview()
        }

        // Link preview

        if let feedLinkPreview = post.linkPreview, media.isEmpty {
            MainAppContext.shared.feedData.loadImages(feedLinkPreviewID: feedLinkPreview.id)
            let postLinkPreviewView = postLinkPreviewView ?? PostLinkPreviewView()
            self.postLinkPreviewView = postLinkPreviewView
            postLinkPreviewView.configure(feedLinkPreview: feedLinkPreview)
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapped(sender:)))
            postLinkPreviewView.addGestureRecognizer(tapGestureRecognizer)
            postLinkPreviewView.isUserInteractionEnabled = true
            linkPreviewURL = feedLinkPreview.url
            vStack.insertArrangedSubview(postLinkPreviewView, at: vStack.arrangedSubviews.count)
        } else {
            postLinkPreviewView?.removeFromSuperview()
        }

        // Remove extra spacing
        layoutMargins.bottom = post.hideFooterSeparator ? LayoutConstants.bottomMarginNoSeparator : LayoutConstants.bottomMarginWithSeparator

        postId = post.id
        canSaveMedia = post.canSaveMedia
    }

    @objc private func previewTapped(sender: UITapGestureRecognizer) {
         if let linkPreviewURL = linkPreviewURL {
             URLRouter.shared.handleOrOpen(url: linkPreviewURL)
         }
    }

    public static func obtainCryptoResultString(for contentID: String) -> String {
        let cryptoResultString: String
        if ServerProperties.isInternalUser && DeveloperSetting.showDecryptionResults {
            switch AppContext.shared.cryptoData.cryptoResult(for: contentID, in: AppContext.shared.cryptoData.viewContext) {
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
        presentMedia(view.media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
        let media = view.media
        guard media[index].type == .video else { return }

        presentMedia(media, index: index, delegate: view)
    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
        let media = view.media
        guard media[index].type == .video else { return }
        guard scale > scaleThreshold else { return }

        presentMedia(media, index: index, delegate: view)
    }

    private func presentMedia(_ media: [FeedMedia], index: Int, delegate transitionDelegate: MediaListAnimatorDelegate? = nil) {
        guard let id = postId else {
            return
        }

        let explorerController = MediaExplorerController(media: media, index: index, canSaveMedia: canSaveMedia, source: .post(id))
        explorerController.animatorDelegate = transitionDelegate

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
        let viewContext = MainAppContext.shared.feedData.viewContext
        guard isPlaying, let postId = postId, let feedPost = MainAppContext.shared.feedData.feedPost(with: postId, in: viewContext) else {
            return
        }
        AppContext.shared.coreFeedData.sendSeenReceiptIfNecessary(for: feedPost)
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
    var showPrivacyAction: (() -> ())? = nil

    var moreMenuContent: () -> HAMenu.Content = { [] } {
        didSet {
            moreButton.configureWithMenu {
                HAMenu.lazy { [weak self] in
                    self?.moreMenuContent()
                }
            }
        }
    }

    private var contentSizeCategoryDidChangeCancellable: AnyCancellable!

    let avatarButtonSize: CGFloat = 45
    private let avatarButtonSpacing: CGFloat = 8
    private let moreButtonPadding: CGFloat = 20
    private let moreButtonWidth: CGFloat = 18
    private let moreButtonSpacing: CGFloat = 2

    private(set) lazy var avatarViewButton: AvatarViewButton = {
        let avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        avatarViewButton.addTarget(self, action: #selector(showUser), for: .touchUpInside)

        avatarViewButton.widthAnchor.constraint(equalToConstant: avatarButtonSize).isActive = true
        avatarViewButton.heightAnchor.constraint(equalToConstant: avatarButtonSize).isActive = true
        return avatarViewButton
    }()

    private lazy var nameColumn: UIStackView = {
        let timeRow = UIStackView(arrangedSubviews: [timestampLabel, expiryOrArchivedLabel])
        timeRow.axis = .horizontal

        let view = UIStackView(arrangedSubviews: [ userAndGroupNameRow, secondLineGroupNameLabel, timeRow ])
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
        let groupIndicatorColor = UIColor.groupNameArrowTint

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
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showUser)))
        return label
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = Self.makeLabel()
        label.setContentCompressionResistancePriority(UILayoutPriority(UILayoutPriority.defaultLow.rawValue - 1), for: .horizontal)
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
        label.textColor = .timestampLabel
        label.textAlignment = .natural
        label.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal) // higher than contact name
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Same font / color as timestampLabel
    private lazy var expiryOrArchivedLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(forTextStyle: .footnote, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .timestampLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private(set) lazy var moreButton: LargeHitButton = {
        let config = UIImage.SymbolConfiguration(pointSize: moreButtonWidth, weight: .regular, scale: .small)
        let image = UIImage(systemName: "ellipsis", withConfiguration: config)
        let button = LargeHitButton(type: .system)

        button.targetIncrease = 15
        button.setImage(image, for: .normal)
        button.tintColor = .label
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.translatesAutoresizingMaskIntoConstraints = false

        return button
    }()
    
    private lazy var privacyIndicatorButtonView: UIView = {
        let privacyIndicatorButton = UIButton()
        privacyIndicatorButton.addTarget(self, action: #selector(showPrivacyIndicatorTapped), for: .touchUpInside)
        privacyIndicatorButton.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(named: "PrivacySettingFavoritesWithBackground")
        privacyIndicatorButton.setImage(image, for: .normal)
        privacyIndicatorButton.backgroundColor = .favoritesBg
        privacyIndicatorButton.layer.cornerRadius = 11
        let privacyIndicatorButtonView = UIView()
        privacyIndicatorButtonView.addSubview(privacyIndicatorButton)
        privacyIndicatorButtonView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            privacyIndicatorButton.widthAnchor.constraint(equalToConstant: 22),
            privacyIndicatorButton.heightAnchor.constraint(equalToConstant: 22),
            privacyIndicatorButton.topAnchor.constraint(equalTo: privacyIndicatorButtonView.topAnchor, constant: 2),
            privacyIndicatorButton.bottomAnchor.constraint(equalTo: privacyIndicatorButtonView.bottomAnchor),
            privacyIndicatorButton.trailingAnchor.constraint(equalTo: privacyIndicatorButtonView.trailingAnchor)
        ])
        return privacyIndicatorButtonView
    }()

    private lazy var contentStackView: UIStackView = {
        let contentStackView = UIStackView(arrangedSubviews: [ nameColumn ])
        contentStackView.spacing = moreButtonSpacing
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        return contentStackView
    }()
    
    @objc private func showPrivacyIndicatorTapped() {
        showPrivacyAction?()
    }

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(avatarViewButton)
        addSubview(contentStackView)

        let contentStackViewCenterYConstraint = contentStackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        contentStackViewCenterYConstraint.priority = .defaultLow

        let minimizeHeightConstraint = heightAnchor.constraint(equalToConstant: 0)
        minimizeHeightConstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            avatarViewButton.topAnchor.constraint(equalTo: topAnchor),
            avatarViewButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarViewButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: avatarViewButton.trailingAnchor, constant: avatarButtonSpacing),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            contentStackViewCenterYConstraint,
            minimizeHeightConstraint,
        ])

        configureContentStackView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            configureContentStackView()
        }
    }

    private func configureContentStackView() {
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            contentStackView.axis = .vertical
            contentStackView.alignment = .fill
        } else {
            contentStackView.axis = .horizontal
            contentStackView.alignment = .leading
        }
    }

    func refreshTimestamp(with post: FeedPostDisplayable, dateFormatter: DateFormatter? = nil) {
        if let dateFormatter = dateFormatter {
            timestampLabel.text = dateFormatter.string(from: post.timestamp)
        } else {
            timestampLabel.text = post.timestamp.feedTimestamp()
        }
    }

    func configure(with post: FeedPostDisplayable, contentWidth: CGFloat, showGroupName: Bool, showArchivedDate: Bool = false, useFullUserName: Bool = false) {
        if useFullUserName, post.userId == MainAppContext.shared.userData.userId {
            nameLabel.text = MainAppContext.shared.userData.name
        } else {
            nameLabel.text = post.posterFullName
        }

        let isPostExpired = post.expiration.flatMap { $0 < Date() } ?? false

        var showExpiry = false
        if !isPostExpired,
           !post.fromExternalShare,
           let groupID = post.groupId,
           let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) {
            switch (post.expiration, group.postExpirationDate(from: post.timestamp)) {
            case (.some(let date1), .some(let date2)):
                // Treat times within 5sec as the same to account for rounding
                showExpiry = abs(date1.timeIntervalSince1970 - date2.timeIntervalSince1970) > Date.days(2)
            case (.some, .none), (.none, .some):
                showExpiry = true
            case (.none, .none):
                showExpiry = false
            }
        }

        if showExpiry {
            expiryOrArchivedLabel.text = " • " + Localizations.feedPostExpiredTimestamp(date: post.expiration)
            expiryOrArchivedLabel.isHidden = false
        } else if showArchivedDate, isPostExpired, let expiration = post.expiration {
            expiryOrArchivedLabel.text = " • " + Localizations.feedPostArchivedTimestamp(time: expiration.shortDateFormat())
            expiryOrArchivedLabel.isHidden = false
        } else {
            expiryOrArchivedLabel.text = nil
            expiryOrArchivedLabel.isHidden = true
        }

        let userAvatar = post.userAvatar(using: MainAppContext.shared.avatarStore)
        avatarViewButton.avatarView.configure(with: userAvatar, using: MainAppContext.shared.avatarStore)

        if post.audienceType == AudienceType.whitelist {
            contentStackView.addArrangedSubview(privacyIndicatorButtonView)
            contentStackView.setCustomSpacing(moreButtonPadding, after: privacyIndicatorButtonView)
        } else {
            privacyIndicatorButtonView.removeFromSuperview()
        }

        contentStackView.addArrangedSubview(moreButton)

        configureGroupLabel(with: post.groupId, contentWidth: contentWidth, showGroupName: showGroupName)
        refreshTimestamp(with: post)
    }

    func configureGroupLabel(with groupID: String?, contentWidth: CGFloat, showGroupName: Bool) {
        let viewContext = MainAppContext.shared.feedData.viewContext
        guard showGroupName, let groupID = groupID, let groupChat = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: viewContext) else {
            groupIndicatorLabel.isHidden = true
            groupNameLabel.isHidden = true
            groupNameLabel.text = nil
            secondLineGroupNameLabel.removeFromSuperview()
            secondLineGroupNameLabel.text = nil
            return
        }

        groupIndicatorLabel.isHidden = false
        groupNameLabel.isHidden = false
        groupNameLabel.text = groupChat.name

        if isRowTruncated(contentWidth: contentWidth) {
            groupNameLabel.text = nil
            secondLineGroupNameLabel.text = groupChat.name
            let index = (nameColumn.arrangedSubviews.firstIndex(of: userAndGroupNameRow) ?? 0) + 1
            nameColumn.insertArrangedSubview(secondLineGroupNameLabel, at: index)
        } else {
            secondLineGroupNameLabel.removeFromSuperview()
            secondLineGroupNameLabel.text = nil
        }
    }
    
    func prepareForReuse() {
        avatarViewButton.avatarView.prepareForReuse()
    }

    @objc func showUser() {
        showUserAction?()
    }
    
    @objc func showGroupFeed() {
        showGroupFeedAction?()
    }

    private func isRowTruncated(contentWidth: CGFloat) -> Bool {
        var requiredWidth = userAndGroupNameRow.systemLayoutSizeFitting(CGSize(width: contentWidth, height: 20)).width
        requiredWidth += moreButton.isHidden ? directionalLayoutMargins.trailing : (moreButtonWidth + moreButtonPadding + moreButtonSpacing)
        requiredWidth += avatarButtonSize + avatarButtonSpacing

        return requiredWidth > contentWidth
    }
}

protocol FeedItemFooterProtocol: UIView {
    func configure(with post: FeedPostDisplayable, contentWidth: CGFloat)
    func prepareForReuse()

    var deleteAction: (() -> ())? { get set }
    var cancelAction: (() -> ())? { get set }
    var retryAction: (() -> ())? { get set }
    var shareAction: (() -> ())? { get set }
    var commentAction: (() -> ())? { get set }
    var reactAction: (() -> ())? { get set }
    var seenByAction: (() -> ())? { get set }

    var messageButton: UIButton { get }
    var separator: UIView { get }

    var reactButtonLocation: CGPoint? { get }
}

final class FeedItemFooterView: UIView, FeedItemFooterProtocol {
    class ButtonWithBadge: UIButton {

        enum BadgeState {
            case hidden
            case unread
            case read
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupView()
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
            addSubview(badgeView)
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            guard let titleLabel else { return }

            let spacing: CGFloat = 6
            let spacingToCenter = spacing + badgeView.bounds.width / 2
            let badgeCenterX = effectiveUserInterfaceLayoutDirection == .leftToRight ? titleLabel.frame.maxX + spacingToCenter : titleLabel.frame.minX - spacingToCenter
            badgeView.center = badgeView.alignedCenter(from: CGPoint(x: badgeCenterX, y: titleLabel.frame.midY))
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
    var seenByAction: (() -> ())?
    var shareAction: (() -> ())?
    var commentAction: (() -> ())?

    // Reactions unsupported in legacy footer
    var reactAction: (() -> ())? = nil
    var reactButtonLocation: CGPoint? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    lazy var commentButton: ButtonWithBadge = {
        let button = ButtonWithBadge(type: .system)
        var buttonConfiguration = FeedItemFooterReactionView.buttonConfiguration()
        buttonConfiguration.contentInsets.leading = 20
        button.configuration = buttonConfiguration
        button.setTitle(Localizations.feedComment, for: .normal)
        button.setImage(UIImage(named: "FeedPostComment"), for: .normal)
        button.addTarget(self, action: #selector(commentButtonAction), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        return button
    }()

    // Gotham Medium, 15 pt (Subhead)
    lazy var messageButton: UIButton = {
        let stringMessage = NSLocalizedString("feedpost.button.reply", value: "Reply Privately", comment: "Button under someoneelse's post. Verb.")
        let button = UIButton(type: .system)
        var buttonConfiguration = FeedItemFooterReactionView.buttonConfiguration(spacing: 6)
        buttonConfiguration.contentInsets.leading = 20
        button.configuration = buttonConfiguration
        button.setTitle(stringMessage, for: .normal)
        button.setImage(UIImage(named: "FeedPostReply"), for: .normal)
        button.contentHorizontalAlignment = .trailing
        return button
    }()

    lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        view.addTarget(self, action: #selector(facePileAction), for: .touchUpInside)
        return view
    }()

    lazy var separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .separatorGray
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }()

    lazy var shareButton: UIButton = {
        let shareButton = UIButton(type: .system)
        var buttonConfiguration = FeedItemFooterReactionView.buttonConfiguration()
        buttonConfiguration.contentInsets.top -= 1
        buttonConfiguration.contentInsets.bottom += 1
        shareButton.configuration = buttonConfiguration
        shareButton.addTarget(self, action: #selector(shareButtonAction), for: .touchUpInside)
        let shareIcon = UIImage(systemName: "square.and.arrow.up")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        shareButton.setImage(shareIcon, for: .normal)
        shareButton.setTitle(Localizations.buttonShare, for: .normal)
        return shareButton
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
        addSubview(buttonStack)
        buttonStack.constrain(to: self)

        addSubview(facePileView)

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shareButton)

        let shareButtonCenterXConstraint = shareButton.centerXAnchor.constraint(equalTo: centerXAnchor)
        shareButtonCenterXConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            facePileView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            facePileView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),

            shareButton.topAnchor.constraint(equalTo: topAnchor),
            shareButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            shareButtonCenterXConstraint,
            shareButton.leadingAnchor.constraint(greaterThanOrEqualTo: commentButton.trailingAnchor, constant: 4),
            shareButton.trailingAnchor.constraint(lessThanOrEqualTo: facePileView.leadingAnchor, constant: -24),
        ])
    }

    private class func senderCategory(for post: FeedPostDisplayable) -> SenderCategory {
        if post.userId == MainAppContext.shared.userData.userId {
            return .ownPost
        }
        if UserProfile.find(with: post.userId, in: MainAppContext.shared.mainDataStore.viewContext)?.friendshipStatus ?? .none == .friends {
            return .contact
        }
        return .nonContact
    }

    private class func state(for post: FeedPostDisplayable) -> State {
        switch post.status {
        case .sending: return .sending
        case .sendError: return .error
        case .retracting: return .retracting
        default: return .normal(senderCategory(for: post))
        }
    }

    func configure(with post: FeedPostDisplayable, contentWidth: CGFloat) {
        let state = Self.state(for: post)

        buttonStack.isHidden = state == .sending || state == .error || state == .retracting
        facePileView.isHidden = true
        separator.isHidden = post.hideFooterSeparator

        commentButton.isEnabled = post.canComment

        if case .normal = state, post.canSharePost {
            shareButton.isHidden = false
        } else {
            shareButton.isHidden = true
        }

        switch state {
        case .normal(let sender):
            hideProgressView()
            hideErrorView()

            commentButton.badge = post.hasComments ? (post.unreadCount > 0 ? .unread : .read) : .hidden
            messageButton.alpha = sender == .contact ? 1 : 0
            messageButton.isEnabled = post.canReplyPrivately
            if sender == .ownPost {
                facePileView.isHidden = false
                facePileView.configure(with: post)
            }
        case .sending, .retracting:
            showProgressView(post)
            hideErrorView()

            if post.mediaCount > 0 {
                progressView.isIndeterminate = false

                uploadProgressCancellable = post.uploadProgressPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak progressView] progress in
                        progressView?.progress = progress
                    }
            } else {
                progressView.progress = 0.5
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

    private func showProgressView(_ post: FeedPostDisplayable) {
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

    @objc private func shareButtonAction() {
        shareAction?()
    }

    @objc private func commentButtonAction() {
        commentAction?()
    }

    @objc private func facePileAction() {
        seenByAction?()
    }
}

final class FeedItemFooterReactionView: UIView, FeedItemFooterProtocol {

    class CommentButton: UIButton {

        enum CommentState {
            case noComments
            case comments(unreadCount: Int)
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.setupView()
        }

        private static var commentBubbleEmpty: UIImage? = UIImage(named: "FeedPostComment.empty")?
            .withTintColor(.label.withAlphaComponent(0.7), renderingMode: .alwaysOriginal)
        private static var commentBubbleFull: UIImage? = UIImage(named: "FeedPostComment.fill")?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)

        private let badgeView = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: 7, height: 7)))
        private let badgeOutlineView = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: 12, height: 12)))
        private let numberView: UILabel = {
            let label = UILabel()
            label.textColor = .white
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 13)
            return label
        }()

        private func setupView() {
            badgeOutlineView.fillColor = .messageFooterBackground
            badgeOutlineView.layer.zPosition = 100
            addSubview(badgeOutlineView)

            badgeView.fillColor = .systemGray4
            badgeView.layer.zPosition = 101
            addSubview(badgeView)
            numberView.layer.zPosition = 102
            addSubview(numberView)

            configure(state: .noComments)
        }

        func configure(state: CommentState) {
            let isBadgeHidden: Bool
            let image: UIImage?
            let numberString: String?

            switch state {
            case .noComments:
                isBadgeHidden = true
                image = Self.commentBubbleEmpty
                numberString = nil

            case .comments(let unreadCount):
                if unreadCount > 0 {
                    isBadgeHidden = true
                    image = Self.commentBubbleFull
                    numberString = unreadCount >= 100 ? "!!!" : String(unreadCount)
                } else {
                    isBadgeHidden = false
                    image = Self.commentBubbleEmpty
                    numberString = nil
                }
            }
            badgeView.isHidden = isBadgeHidden
            badgeOutlineView.isHidden = isBadgeHidden
            setImage(image, for: .normal)
            numberView.text = numberString
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            
            guard let imageView else {
                return
            }

            numberView.frame = imageView.frame
            badgeView.center = badgeView.alignedCenter(from: CGPoint(x: imageView.frame.maxX * 7 / 8, y: imageView.frame.maxY * 16 / 20))
            badgeOutlineView.center = badgeView.alignedCenter(from: CGPoint(x: imageView.frame.maxX * 7 / 8, y: imageView.frame.maxY * 16 / 20))
            numberView.center = numberView.alignedCenter(from: CGPoint(x: imageView.frame.midX, y: imageView.frame.midY - 1))
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
    var shareAction: (() -> ())?
    var commentAction: (() -> ())?
    var reactAction: (() -> ())?
    var seenByAction: (() -> ())?

    var reactButtonLocation: CGPoint? {
        return convert(reactionButton.center, from: reactionButton.superview ?? self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    lazy var commentButton: CommentButton = {
        let button = CommentButton(type: .system)
        button.configuration = Self.buttonConfiguration(baseTextStyle: .subheadline)
        button.setTitle(Localizations.feedComments, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(commentButtonAction), for: .touchUpInside)
        return button
    }()

    lazy var trailingStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [facePileView, reactionPileView, reactionButton, messageButton, shareButton])
        stackView.spacing = 16
        stackView.setCustomSpacing(4, after: reactionPileView)
        return stackView
    }()

    // Gotham Medium, 15 pt (Subhead)
    lazy var messageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(named: "FeedReplyButton")?
                .withTintColor(.label.withAlphaComponent(0.7), renderingMode: .alwaysOriginal),
            for: .normal)
        button.contentHorizontalAlignment = .trailing
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var reactionButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(self, action: #selector(reactButtonAction), for: .touchUpInside)
        button.setImage(
            UIImage(named: "FeedReactionButton")?
                .withTintColor(.label.withAlphaComponent(0.7), renderingMode: .alwaysOriginal),
            for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        view.addTarget(self, action: #selector(facePileAction), for: .touchUpInside)
        return view
    }()

    lazy var reactionPileView: ReactionPileView = {
        let view = ReactionPileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        view.addTarget(self, action: #selector(reactionPileAction), for: .touchUpInside)
        return view
    }()

    lazy var separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .separatorGray
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }()

    lazy var shareButton: UIButton = {
        let shareButton = UIButton(type: .system)
        shareButton.addTarget(self, action: #selector(shareButtonAction), for: .touchUpInside)
        let shareIcon = UIImage(named: "shareButton")?
            .withTintColor(.label.withAlphaComponent(0.7), renderingMode: .alwaysOriginal)
        shareButton.setImage(shareIcon, for: .normal)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        return shareButton
    }()

    private func setupView() {
        isUserInteractionEnabled = true

        addSubview(separator)

        separator.topAnchor.constraint(equalTo: topAnchor).isActive = true

        addSubview(commentButton)
        commentButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(trailingStackView)
        trailingStackView.translatesAutoresizingMaskIntoConstraints = false

        let shareButtonCenterXConstraint = shareButton.centerXAnchor.constraint(equalTo: centerXAnchor)
        shareButtonCenterXConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            commentButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            commentButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            commentButton.heightAnchor.constraint(equalTo: heightAnchor),

            trailingStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            trailingStackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),
        ])
    }

    fileprivate static func buttonConfiguration(spacing: CGFloat = 4, baseTextStyle: UIFont.TextStyle = .footnote) -> UIButton.Configuration {
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.baseForegroundColor = .label.withAlphaComponent(0.75)
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 0, bottom: 9, trailing: 0)
        buttonConfiguration.imagePadding = spacing
        buttonConfiguration.titleLineBreakMode = .byWordWrapping
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .gothamFont(forTextStyle: baseTextStyle, weight: .medium, maximumPointSize: 18)
            return updatedAttributeContainer
        }
        return buttonConfiguration
    }

    private class func senderCategory(for post: FeedPostDisplayable) -> SenderCategory {
        if post.userId == MainAppContext.shared.userData.userId {
            return .ownPost
        }
        if UserProfile.find(with: post.userId, in: MainAppContext.shared.mainDataStore.viewContext)?.friendshipStatus ?? .none == .friends {
            return .contact
        }
        return .nonContact
    }

    private class func state(for post: FeedPostDisplayable) -> State {
        switch post.status {
        case .sending: return .sending
        case .sendError: return .error
        case .retracting: return .retracting
        default: return .normal(senderCategory(for: post))
        }
    }

    func configure(with post: FeedPostDisplayable, contentWidth: CGFloat) {
        let state = Self.state(for: post)

        commentButton.isHidden = state == .sending || state == .error || state == .retracting
        reactionButton.isHidden = state == .sending || state == .error || state == .retracting
        messageButton.isHidden = state == .sending || state == .error || state == .retracting
        facePileView.isHidden = true
        reactionPileView.isHidden = true
        separator.isHidden = post.hideFooterSeparator

        commentButton.isEnabled = post.canComment
        reactionButton.isHidden = !post.canReact


        if case .normal = state, post.canSharePost {
            shareButton.isHidden = false
        } else {
            shareButton.isHidden = true
        }

        switch state {
        case .normal(let sender):
            hideProgressView()
            hideErrorView()

            commentButton.configure(state: post.hasComments ? .comments(unreadCount: Int(post.unreadCount)) : .noComments)
            messageButton.isHidden = !post.canReplyPrivately
            messageButton.isEnabled = post.canReplyPrivately
            if sender == .ownPost {
                facePileView.isHidden = false
                facePileView.configure(with: post)
            } else {
                reactionPileView.isHidden = false
                reactionPileView.configure(with: post)
            }
        case .sending, .retracting:
            showProgressView(post)
            hideErrorView()

            if post.mediaCount > 0 {
                progressView.isIndeterminate = false

                uploadProgressCancellable = post.uploadProgressPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak progressView] progress in
                        progressView?.progress = progress
                    }
            } else {
                progressView.progress = 0.5
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
        reactionPileView.prepareForReuse()
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

    private func showProgressView(_ post: FeedPostDisplayable) {
        if progressView.superview == nil {
            addSubview(progressView)
            progressView.constrain(to: self)
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
            errorView.constrain(to: self)
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

    @objc private func shareButtonAction() {
        shareAction?()
    }

    @objc private func commentButtonAction() {
        commentAction?()
    }

    @objc private func reactButtonAction() {
        reactAction?()
    }

    @objc private func facePileAction() {
        seenByAction?()
    }

    @objc private func reactionPileAction() {
        seenByAction?()
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
    func configure(with post: FeedPostDisplayable) {
        let isTextPost = post.mediaCount == 0

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
    static func feedPostExpiredTimestamp(date: Date?) -> String {
        if let date = date {
            let formatString = NSLocalizedString("feed.post.expired.timestamp", value: "Expires %@", comment: "Indication of when a post expired")
            return String(format: formatString, date.shortDateFormat())
        } else {
            return NSLocalizedString("feed.post.expired.timestamp.never", value: "Never expires", comment: "Indication of when a post never expires")
        }
    }
    static var feedComment: String {
        NSLocalizedString("feedpost.button.comment", value: "Comment", comment: "Button under someone's post. Verb.")
    }
    static var feedComments: String {
        NSLocalizedString("feedpost.button.comments", value: "Comments", comment: "Button under someone's post. Noun.")
    }
}
