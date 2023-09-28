//
//  HalloApp
//
//  Created by Tony Jiang on 10/21/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

class FeedWelcomeCell: UICollectionViewCell {

    class var reuseIdentifier: String {
        "welcome-post"
    }

    var openNetwork: (() -> ())?
    var closeWelcomePost: (() -> ())?

    public func configure(showCloseButton: Bool) {
        closeButtonColumn.isHidden = !showCloseButton
    }

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

    private lazy var backgroundPanelLeadingConstraint: NSLayoutConstraint = {
        backgroundPanelView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                     constant: layoutMargins.left * LayoutConstants.backgroundPanelHMarginRatio)
    }()

    private lazy var backgroundPanelTrailingConstraint: NSLayoutConstraint = {
        backgroundPanelView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                      constant: -layoutMargins.right * LayoutConstants.backgroundPanelHMarginRatio)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    private func setup() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        // Background
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        backgroundPanelView.translatesAutoresizingMaskIntoConstraints = false
        updateBackgroundPanelShadow()

        backgroundPanelView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(backgroundPanelView)
        contentView.addSubview(mainView)
        contentView.addSubview(inviteFriendsButton)

        let verticalPadding = LayoutConstants.backgroundPanelViewOutsetV + LayoutConstants.interCardSpacing * 0.5

        NSLayoutConstraint.activate([
            mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            mainView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),

            inviteFriendsButton.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            inviteFriendsButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            inviteFriendsButton.topAnchor.constraint(equalTo: mainView.bottomAnchor, constant: 20),
            inviteFriendsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding - 20),

            backgroundPanelView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.interCardSpacing * 0.5),
            backgroundPanelView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -LayoutConstants.interCardSpacing * 0.5),
            backgroundPanelLeadingConstraint,
            backgroundPanelTrailingConstraint,
        ])
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        
        backgroundPanelLeadingConstraint.constant = layoutMargins.left * LayoutConstants.backgroundPanelHMarginRatio
        backgroundPanelTrailingConstraint.constant = -layoutMargins.right * LayoutConstants.backgroundPanelHMarginRatio
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ headerRow, bodyColumn ])
        view.axis = .vertical
        view.spacing = 10
        view.setCustomSpacing(20, after: bodyColumn)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var headerRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [logoView, headerTitleColumn, closeButtonColumn])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 6

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var logoView: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "AppIconAvatarCircle")
        view.image = image

        view.widthAnchor.constraint(equalToConstant: 45).isActive = true
        view.heightAnchor.constraint(equalToConstant: 45).isActive = true
        return view
    }()

    private lazy var headerTitleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [headerTitleLabel, timeLabel])
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 3

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var headerTitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        label.textColor = .label
        label.text = Localizations.appNameHalloApp

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .timestampLabel
        label.text = Date().feedTimestamp()

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var closeButtonColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [closeButton])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 15, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeAction)))
        
        view.isHidden = true
        return view
    }()

    private lazy var closeButton: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate)
        view.image = image
        view.tintColor = .primaryBlackWhite.withAlphaComponent(0.4)

        view.widthAnchor.constraint(equalToConstant: 13).isActive = true
        view.heightAnchor.constraint(equalToConstant: 13).isActive = true
        return view
    }()

    private lazy var bodyColumn: UIStackView = {
        let firstSection = section(emoji: "🎉", title: Localizations.feedWelcomePostTitle1, body: Localizations.feedWelcomePostBody1)
        let secondSection = section(emoji: "🤗", title: Localizations.feedWelcomePostTitle2, body: Localizations.feedWelcomePostBody2)

        let view = UIStackView(arrangedSubviews: [firstSection, secondSection])
        view.axis = .vertical
        view.spacing = 15

        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func section(emoji: String, title: String, body: String) -> UIView {
        let emojiLabel = UILabel()
        emojiLabel.font = .systemFont(ofSize: 27)
        emojiLabel.textAlignment = .center
        emojiLabel.text = emoji

        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 18, weight: .medium)
        titleLabel.textAlignment = .natural
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let bodyLabel = UILabel()
        bodyLabel.font = .scaledSystemFont(ofSize: 18)
        bodyLabel.textAlignment = .natural
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.text = body

        let stack = UIStackView(arrangedSubviews: [emojiLabel, titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.setCustomSpacing(5, after: emojiLabel)
        stack.setCustomSpacing(5, after: titleLabel)

        return stack
    }

    private lazy var inviteFriendsButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .primaryBlue
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "chevron.forward")
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 14, weight: .medium)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 15
        configuration.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
        configuration.attributedTitle = .init(Localizations.seeMyNetwork,
                                              attributes: .init([.font: UIFont.scaledSystemFont(ofSize: 18, weight: .medium)]))
        let button = UIButton(configuration: configuration, primaryAction: .init { [weak self] _ in
            self?.openNetwork?()
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.breakable, for: .vertical)
        return button
    }()

    // MARK: Button actions

    @objc(closeAction)
    private func closeAction() {
        closeWelcomePost?()
    }
}

fileprivate extension UILabel {
    func getSize(width: CGFloat) -> CGSize {
        return systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }
}

extension Localizations {

    static var seeMyNetwork: String {
        NSLocalizedString("see.my.network", 
                          value: "See My Network",
                          comment: "Title of a button that displays the users friend list.")
    }

    static var feedWelcomePostTitle1: String {
        return NSLocalizedString("feed.welcome.post.title.1", 
                                 value: "Welcome to HalloApp! Your private social network",
                                 comment: "Title of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }

    static var feedWelcomePostTitle2: String {
        return NSLocalizedString("feed.welcome.post.title.2",
                                 value: "Who can see my posts?",
                                 comment: "Title of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }

    static var feedWelcomePostBody1: String {
        NSLocalizedString("feed.welcome.post.body.1",
                          value: "A private space with no influencers and no ads. Only you and people you care about.",
                          comment: "Body text of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }

    static var feedWelcomePostBody2: String {
        NSLocalizedString("feed.welcome.post.body.2",
                          value: "Your friends on HalloApp can see your posts. Add friends from your network and manage friend requests.",
                          comment: "Body text of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }
}
