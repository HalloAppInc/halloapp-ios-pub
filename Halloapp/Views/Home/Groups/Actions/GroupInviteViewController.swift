//
//  HalloApp
//
//  Created by Tony Jiang on 3/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import Foundation
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 100
    static let ActionIconSize: CGFloat = 21
    static let RowHeight: CGFloat = 52
    static let MaxFontPointSize: CGFloat = 28
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
        groupNameText.text = group?.name ?? ""
        linkLabel.text = formatLink(group?.inviteLink ?? "")
    }

    private lazy var mainView: UIScrollView = {
        let view = UIScrollView()
        view.backgroundColor = .clear
        view.addSubview(innerStack)

        view.translatesAutoresizingMaskIntoConstraints = false

        innerStack.constrain(to: view)

        return view
    }()

    private lazy var innerStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [infoRow, resultRow, spacer])
        view.axis = .vertical
        view.alignment = .fill
        view.setCustomSpacing(70, after: infoRow)

        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width).isActive = true

        return view
    }()
    
    private lazy var infoRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [avatarRow, groupNameLabelRow, groupNameRow, groupLinkLabelRow, groupLinkRow])
        view.axis = .vertical
        view.spacing = 0
        view.setCustomSpacing(30, after: avatarRow)
        view.setCustomSpacing(30, after: groupNameRow)

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var avatarRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupAvatarView])
        view.axis = .vertical
        view.alignment = .center
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

    private lazy var groupNameLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupNameLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()

    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.chatGroupNameLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var groupNameRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ groupNameText ])

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Constants.RowHeight).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()

    private lazy var groupNameText: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var groupLinkLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupLinkLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()

    private lazy var groupLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.groupInviteLinkLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var groupLinkRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ descriptionRow, copyLinkRow, shareLinkRow, QRCodeRow, resetLinkRow ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()

    private lazy var descriptionRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [linkLabel, linkDescriptionLabel])
        view.axis = .vertical

        view.spacing = 8

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(copyLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var linkLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(forTextStyle: .body)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return label
    }()

    private lazy var linkDescriptionLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(forTextStyle: .body)
        label.text = Localizations.groupInviteLinkDescription

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)

        return label
    }()

    private lazy var copyLinkRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [copyLinkImage, copyLinkLabel])
        view.axis = .horizontal

        view.spacing = 8

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView()
        subView.backgroundColor = .systemGray5
        subView.translatesAutoresizingMaskIntoConstraints = false
 
        view.insertSubview(subView, at: 0)
        subView.heightAnchor.constraint(equalToConstant: 0.7).isActive = true
        subView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        subView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        subView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(copyLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var copyLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(named: "CopyLink")?.withRenderingMode(.alwaysTemplate)
        view.image = image
        view.tintColor = .primaryBlue

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var copyLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .primaryBlue
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteCopyLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var shareLinkRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [shareLinkImage, shareLinkLabel])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 8

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView()
        subView.backgroundColor = .systemGray5
        subView.translatesAutoresizingMaskIntoConstraints = false

        view.insertSubview(subView, at: 0)
        subView.heightAnchor.constraint(equalToConstant: 0.7).isActive = true
        subView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        subView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        subView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(shareLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var shareLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(systemName: "square.and.arrow.up")
        view.image = image
        view.tintColor = .primaryBlue

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var shareLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .primaryBlue
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteShareLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var QRCodeRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [QRCodeImage, QRCodeLabel])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 8

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView()
        subView.backgroundColor = .systemGray5
        subView.translatesAutoresizingMaskIntoConstraints = false

        view.insertSubview(subView, at: 0)
        subView.heightAnchor.constraint(equalToConstant: 0.7).isActive = true
        subView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        subView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        subView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(QRAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var QRCodeImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(named: "QRCodeLink")?.withRenderingMode(.alwaysTemplate)
        view.image = image
        view.tintColor = .primaryBlue

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var QRCodeLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .primaryBlue
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteQRCode
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var resetLinkRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [resetLinkImage, resetLinkLabel])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 8

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(resetLinkAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var resetLinkImage: UIImageView = {
        let view = UIImageView()

        var image = UIImage(systemName: "xmark")
        view.image = image
        view.tintColor = .systemRed

        view.contentMode = .scaleAspectFit

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.ActionIconSize).isActive = true

        return view
    }()

    private lazy var resetLinkLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 17)
        label.text = Localizations.groupInviteResetLink
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var resultRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ actionResultLabel ])

        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Constants.RowHeight).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .groupInviteResultBg
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        view.isHidden = true

        return view
    }()

    private lazy var actionResultLabel: UILabel = {
        var label = UILabel()

        label.numberOfLines = 1
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 17)

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    // MARK: Actions

    @objc private func shareLinkAction(_ sender: UIView) {
        guard let link = linkLabel.text else { return }
        if let urlStr = NSURL(string: link) {
            let shareText = "\(Localizations.groupInviteShareLinkMessage) \(urlStr)"
            let objectsToShare = [shareText]
            let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)

            self.present(activityVC, animated: true, completion: nil)
        }
    }

    @objc func copyLinkAction(_ sender: UIView) {
        guard let link = linkLabel.text else { return }
        let pasteboard = UIPasteboard.general
        pasteboard.string = link

        actionResultLabel.attributedText = formatResultAttributedText(text: Localizations.groupInviteLinkCopied)

        resultRow.isHidden = false
        DispatchQueue.main.async { [weak self] in
            self?.scrollToBottom()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.resultRow.isHidden = true
            self?.actionResultLabel.attributedText = nil
        }
    }

    @objc func QRAction(_ sender: UIView) {
        guard let link = linkLabel.text else { return }
        let vc = GroupInviteQRViewController(for: link)
        navigationController?.pushViewController(vc, animated: true)
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
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.linkLabel.text = self.formatLink(link)

                        self.actionResultLabel.attributedText = self.formatResultAttributedText(text: Localizations.groupInviteLinkReset)
                        self.resultRow.isHidden = false
                        DispatchQueue.main.async { [weak self] in
                            self?.scrollToBottom()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                            self?.resultRow.isHidden = true
                            self?.actionResultLabel.attributedText = nil
                        }
                    }
                case .failure(let error):
                    DDLogDebug("GroupInviteViewController/resetLinkAction/error \(error)")
                }
            }

        })

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }

    // MARK: Helpers

    private func formatResultAttributedText(text: String) -> NSMutableAttributedString {
        let messageStatusIcon: UIImage? = UIImage(named: "CheckmarkSingle")?.withTintColor(.secondaryLabel)
        let result = NSMutableAttributedString(string: "")
        if let messageStatusIcon = messageStatusIcon {
            let iconAttachment = NSTextAttachment(image: messageStatusIcon)
            result.append(NSAttributedString(attachment: iconAttachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text))
        return result
    }

    private func scrollToBottom() {
        guard mainView.contentSize.height > UIScreen.main.bounds.height else { return }
        let bottomOffset = CGPoint(x: 0, y: mainView.contentSize.height - mainView.bounds.height + mainView.contentInset.bottom)
        mainView.setContentOffset(bottomOffset, animated: true)
    }
}

private extension Localizations {
    static var groupInviteTitle: String {
        NSLocalizedString("group.invite.title", value: "Group Invite", comment: "Title of group invite screen")
    }

    static var groupInviteLinkLabel: String {
        NSLocalizedString("group.invite.link.label", value: "GROUP LINK", comment: "Text label above the group link section in group invite screen")
    }

    static var groupInviteLinkDescription: String {
        NSLocalizedString("group.invite.link.description", value: "Anyone with HalloApp can follow this link to join this group.", comment: "Text to describe what the group invite link is")
    }

    static var groupInviteShareLinkMessage: String {
        NSLocalizedString("group.invite.share.link.message", value: "Click on this link to join my HalloApp group: ", comment: "Text shown before the sharing link")
    }

    static var groupInviteShareLink: String {
        NSLocalizedString("group.invite.share.link", value: "Share Link", comment: "Label for sharing link")
    }

    static var groupInviteCopyLink: String {
        NSLocalizedString("group.invite.copy.link", value: "Copy Link", comment: "Label for copying link")
    }

    static var groupInviteQRCode: String {
        NSLocalizedString("group.invite.qr.code", value: "QR Code", comment: "Label for opening QR screen")
    }

    static var groupInviteResetLink: String {
        NSLocalizedString("group.invite.reset.link", value: "Reset Link", comment: "Label for resetting link")
    }

    static var groupInviteResetLinkWarning: String {
        NSLocalizedString("group.invite.reset.link.warning", value: "If this invite link is reset, no one will be able to use it to join the group.", comment: "Warning shown when user clicks on reset link action")
    }

    static var groupInviteLinkCopied: String {
        NSLocalizedString("group.invite.link.copied", value: "Copied To Clipboard", comment: "Text shown when link is copied")
    }

    static var groupInviteLinkReset: String {
        NSLocalizedString("group.invite.link.reset", value: "Link Reset", comment: "Text shown when link is reset")
    }
}
