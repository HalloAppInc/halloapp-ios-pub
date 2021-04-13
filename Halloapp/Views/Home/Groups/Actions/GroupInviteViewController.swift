//
//  HalloApp
//
//  Created by Tony Jiang on 3/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 80
    static let ActionIconSize: CGFloat = 40
}

class GroupInviteViewController: UIViewController {
    private var groupID: GroupID
    private var group: ChatGroup?

    init(for groupID: GroupID) {
        self.groupID = groupID
        self.group = MainAppContext.shared.chatData.chatGroup(groupId: groupID)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        setupView()
    }

    private func formatLink(_ link: String) -> String {
        var result = "https://halloapp.com/invite/?g="
        result += link
        return result
    }

    func setupView() {
        view.backgroundColor = .primaryBg

        navigationItem.title = Localizations.groupInviteTitle

        view.addSubview(mainView)
        mainView.constrain(to: view)

        if group?.inviteLink == nil {
            MainAppContext.shared.chatData.getGroupInviteLink(groupID: groupID) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let link):
                    guard let link = link else { break }
                    DispatchQueue.main.async {
                        self.linkLabel.text = self.formatLink(link)
                    }
                case .failure(let error):
                    DDLogDebug("GroupInviteViewController/getGroupInviteLink/error \(error)")
                }
            }
        }

        groupAvatarView.configure(groupId: groupID, squareSize: Constants.AvatarSize, using: MainAppContext.shared.avatarStore)
        groupNameLabel.text = group?.name ?? ""
        linkLabel.text = formatLink(group?.inviteLink ?? "")
    }

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [linkRow, actionResultLabel, actionsRow, spacer])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var linkRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [linkDescriptionLabel, linkInfoRow])
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true

        return view
    }()

    private lazy var linkDescriptionLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(forTextStyle: .body)
        label.text = Localizations.groupInviteLinkDescription

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)

        return label
    }()

    private lazy var linkInfoRow: UIStackView = {

        let view = UIStackView(arrangedSubviews: [groupAvatarView, linkLabelColumn])
        view.axis = .horizontal
        view.spacing = 15

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var groupAvatarView: AvatarView = {
        let view = AvatarView()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        return view
    }()

    private lazy var linkLabelColumn: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [groupNameLabel, linkLabel, spacer])
        view.axis = .vertical
        view.spacing = 8

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .label
        label.font = UIFont.boldSystemFont(ofSize: 17)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return label
    }()
    
    private lazy var linkLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .label
        label.font = UIFont.systemFont(ofSize: 17)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return label
    }()
    
    private lazy var actionResultLabel: UILabel = {
        var label = UILabel()

        label.numberOfLines = 1
        label.textAlignment = .center
        label.textColor = .label
        label.font = UIFont.boldSystemFont(ofSize: 17)

        label.translatesAutoresizingMaskIntoConstraints = false

        label.heightAnchor.constraint(equalToConstant: 20).isActive = true

        return label
    }()
    
    private lazy var actionsRow: UIStackView = {
        let leftSpacer = UIView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false

        let rightSpacer = UIView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [leftSpacer, shareLinkLabelBox, copyLinkLabelBox, resetLinkLabelBox, rightSpacer])
        view.axis = .horizontal
        view.distribution = .fillProportionally
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var shareLinkLabelBox: UIStackView = {
        let view = UIStackView(arrangedSubviews: [shareLinkImage, shareLinkLabel])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 8

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(shareLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var shareLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(systemName: "square.and.arrow.up")
        view.image = image

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var shareLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteShareLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()
    
    private lazy var copyLinkLabelBox: UIStackView = {
        let view = UIStackView(arrangedSubviews: [copyLinkImage, copyLinkLabel])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 8

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(copyLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var copyLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(systemName: "doc.on.doc")
        view.image = image

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()
    
    private lazy var copyLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteCopyLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()
    
    private lazy var resetLinkLabelBox: UIStackView = {
        let view = UIStackView(arrangedSubviews: [resetLinkImage, resetLinkLabel])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 8

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(resetLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var resetLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(systemName: "xmark.square")
        view.image = image

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var resetLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteResetLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    // MARK: Actions

    @objc private func shareLinkAction(_ sender: UIView) {
        guard let link = linkLabel.text else { return }
        if let urlStr = NSURL(string: link) {
            let objectsToShare = [urlStr]
            let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)

            self.present(activityVC, animated: true, completion: nil)
        }
    }

    @objc func copyLinkAction(_ sender: UIView) {
        guard let link = linkLabel.text else { return }
        let pasteboard = UIPasteboard.general
        pasteboard.string = link

        actionResultLabel.text = Localizations.groupInviteLinkCopied
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.actionResultLabel.text = ""
        }
    }

    @objc func resetLinkAction(_ sender: UIView) {

        let actionSheet = UIAlertController(title: Localizations.groupInviteResetLinkWarning, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue

        actionSheet.addAction(UIAlertAction(title: Localizations.groupInviteResetLink, style: .default) { [weak self] _ in
            guard let self = self else { return }

            MainAppContext.shared.chatData.resetGroupInviteLink(groupID: self.groupID) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let link):
                    guard let link = link else { break }
                    DispatchQueue.main.async {
                        self.linkLabel.text = self.formatLink(link)
                        self.actionResultLabel.text = Localizations.groupInviteLinkReset
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.actionResultLabel.text = ""
                    }
                case .failure(let error):
                    DDLogDebug("GroupInviteViewController/resetLinkAction/error \(error)")
                }
            }

        })

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }
}

private extension Localizations {
    static var groupInviteTitle: String {
        NSLocalizedString("group.invite.title", value: "Group Invite Link", comment: "Title of group invite screen")
    }

    static var groupInviteLinkDescription: String {
        NSLocalizedString("group.invite.link.description", value: "Anyone with Halloapp can use this link to join the group.", comment: "Text to describe what the group invite link is")
    }

    static var groupInviteShareLink: String {
        NSLocalizedString("group.invite.share.link", value: "Share Link", comment: "Label for sharing link")
    }

    static var groupInviteCopyLink: String {
        NSLocalizedString("group.invite.copy.link", value: "Copy Link", comment: "Label for copying link")
    }

    static var groupInviteResetLink: String {
        NSLocalizedString("group.invite.reset.link", value: "Reset Link", comment: "Label for resetting link")
    }

    static var groupInviteResetLinkWarning: String {
        NSLocalizedString("group.invite.reset.link.warning", value: "If this invite link is reset, no one will be able to use it to join the group.", comment: "Warning shown when user clicks on reset link action")
    }

    static var groupInviteLinkCopied: String {
        NSLocalizedString("group.invite.link.copied", value: "Link copied", comment: "Text shown when link is copied")
    }

    static var groupInviteLinkReset: String {
        NSLocalizedString("group.invite.link.reset", value: "Link reset", comment: "Text shown when link is reset")
    }
}
