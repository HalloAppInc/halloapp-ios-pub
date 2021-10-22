//
//  HalloApp
//
//  Created by Tony Jiang on 10/21/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import Foundation
import UIKit

class FeedWelcomeCell: UICollectionViewCell {

    class var reuseIdentifier: String {
        "welcome-post"
    }

    var openInvite: (() -> ())?

    private lazy var maxWidthConstraint: NSLayoutConstraint = {
        widthAnchor.constraint(equalToConstant: maxWidth)
    }()

    var maxWidth: CGFloat = 0 {
        didSet {
            guard maxWidth != oldValue else {
                return
            }
            maxWidthConstraint.constant = maxWidth
            maxWidthConstraint.isActive = true
        }
    }

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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    private func setup() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.constrain(to: self)

        contentView.heightAnchor.constraint(equalToConstant: 380).isActive = true

        // Background
        backgroundPanelView.cornerRadius = LayoutConstants.backgroundCornerRadius
        let bgView = UIView()
        bgView.preservesSuperviewLayoutMargins = true
        bgView.addSubview(backgroundPanelView)
        backgroundView = bgView
        updateBackgroundPanelShadow()

        contentView.addSubview(mainView)
        // anchoring top instead of layoutMargins as margins seem to change when there's zero posts and some posts
        mainView.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ headerRow, bodyColumn, footerColumn ])
        view.axis = .vertical
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 33, left: 0, bottom: 20, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var headerRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [logoView, headerTitleColumn])
        view.axis = .horizontal
        view.spacing = 6

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var logoView: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "AppIconAvatarCircle")
        view.image = image

        view.widthAnchor.constraint(equalToConstant: 36).isActive = true
        view.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return view
    }()

    private lazy var headerTitleColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [headerTitleLabel, timeLabel])
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 0

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var headerTitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        label.textColor = .label
        label.text = "HalloApp"

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor(named: "TimestampLabel")
        label.text = Date().feedTimestamp()

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bodyColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [bodyTitleLabel, bodyLabel])
        view.axis = .vertical
        view.spacing = 15

        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bodyTitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.text = Localizations.feedWelcomePostTitle

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.text = Localizations.feedWelcomePostBody

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var footerColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [inviteFriendsButton])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // todo: these kind of buttons can be normalized and share one button view
    private lazy var inviteFriendsButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ inviteFriendsLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.backgroundColor = UIColor.primaryBlue
        view.layer.cornerRadius = 20

        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 0, right: 25)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openInviteAction)))

        return view
    }()

    private lazy var inviteFriendsLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 17)
        label.textColor = UIColor.primaryWhiteBlack
        label.text = Localizations.chatInviteFriends

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: Button actions

    @objc(openInviteAction)
    private func openInviteAction() {
        openInvite?()
    }
}

extension Localizations {

    static var feedWelcomePostTitle: String {
        return NSLocalizedString("feed.welcome.post.title", value: "Welcome to HalloApp, a space for real relationships ✨", comment: "Title of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }

    static var feedWelcomePostBody: String {
        return NSLocalizedString("feed.welcome.post.body", value: "Use your phone number to connect with friends and family in a space with no ads, no brands, no likes, and no influencers.\n\nHalloApp is for you, and those closest to you, in private. Invite your real friends to get started!", comment: "Body text of welcome post shown to users who have no contacts and no content (zero zone) in their feed")
    }

}
