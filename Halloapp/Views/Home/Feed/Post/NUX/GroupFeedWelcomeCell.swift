//
//  HalloApp
//
//  Created by Tony Jiang on 10/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import Foundation
import CocoaLumberjackSwift
import UIKit

class GroupFeedWelcomeCell: UICollectionViewCell {

    var openShareLink: ((String) -> ())?

    class var reuseIdentifier: String {
        "group-welcome-post"
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

    private lazy var maxWidthConstraint: NSLayoutConstraint = {
        widthAnchor.constraint(equalToConstant: maxWidth)
    }()

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

    private var groupID: GroupID?
    private var cancellableSet: Set<AnyCancellable> = []

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

    func configure(groupID: GroupID) {
        self.groupID = groupID
        refreshInviteLinkLabel()
    }

    private func setup() {
        backgroundColor = .clear
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.constrain(to: self)

        contentView.heightAnchor.constraint(equalToConstant: 320).isActive = true

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
        mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        cancellableSet.insert(MainAppContext.shared.chatData.didResetGroupInviteLink.sink { [weak self] (groupID) in
            guard let self = self else { return }
            guard self.groupID == groupID else { return }
            self.refreshInviteLinkLabel()
        })
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [headerRow, bodyColumn, footerColumn])
        view.axis = .vertical
        view.spacing = 5
        view.distribution = .fill

        view.layoutMargins = UIEdgeInsets(top: 35, left: 0, bottom: 20, right: 0)
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
        label.text = Localizations.appNameHalloApp

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
        view.spacing = 5

        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bodyTitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.text = Localizations.groupFeedWelcomePostTitle

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.text = Localizations.groupFeedWelcomePostBody

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var footerColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [inviteLinkBubble, shareLinkButton])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 15, left: 10, bottom: 20, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var inviteLinkBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ inviteLinkLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.backgroundColor = UIColor.primaryBg
        view.layer.cornerRadius = 15

        view.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 52).isActive = true

        return view
    }()

    private lazy var inviteLinkLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.6)

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // todo: these kind of buttons can be normalized and share one button view
    private lazy var shareLinkButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ shareLinkLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.backgroundColor = UIColor.primaryBlue
        view.layer.cornerRadius = 20

        view.layoutMargins = UIEdgeInsets(top: 0, left: 25, bottom: 2, right: 25)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 172).isActive = true
        view.heightAnchor.constraint(equalToConstant: 42).isActive = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shareLinkAction)))

        return view
    }()

    private lazy var shareLinkLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor.primaryWhiteBlack
        label.text = Localizations.groupInviteShareLink

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: Helpers for refreshing

    private func refreshInviteLinkLabel() {
        guard let groupID = self.groupID else { return }
        guard let sharedChatData = MainAppContext.shared.chatData else { return }
        guard let group = sharedChatData.chatGroup(groupId: groupID, in: sharedChatData.viewContext) else { return }
        inviteLinkLabel.text = ChatData.formatGroupInviteLink(group.inviteLink ?? "")

        // always get link due to off chance that group gets two admins and one resets the link
        sharedChatData.getGroupInviteLink(groupID: groupID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let link):
                guard let link = link else { break }
                DispatchQueue.main.async {
                    self.inviteLinkLabel.text = ChatData.formatGroupInviteLink(link)
                }
            case .failure(let error):
                DDLogDebug("GroupFeedWelcomeCell/refreshInviteLinkLabel/getGroupInviteLink/error \(error)")
            }
        }
    }

    // MARK: Button actions

    @objc(shareLinkAction)
    private func shareLinkAction() {
        guard let link = inviteLinkLabel.text else { return }
        openShareLink?(link)
    }
}

extension Localizations {

    static var groupFeedWelcomePostTitle: String {
        return NSLocalizedString("group.feed.welcome.post.title", value: "Invite a friend to your group", comment: "Title of welcome post shown to users who have no contacts and no content (zero zone) in their group feed, in their newly created group")
    }

    static var groupFeedWelcomePostBody: String {
        return NSLocalizedString("group.feed.welcome.post.body", value: "Share this link with friends and they'll automatically join your group.", comment: "Body text of welcome post shown to users who have no contacts and no content (zero zone) in their group feed, in their newly created group")
    }

}

