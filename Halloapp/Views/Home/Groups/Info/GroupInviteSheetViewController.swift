//
//  GroupInviteSheetViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 1/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import MessageUI
import UIKit

extension Localizations {

    static var groupInviteSheetTitle: String {
        NSLocalizedString("group.invitesheet.title",
                          value: "Share this link with friends & family and they’ll automatically join this HalloApp group",
                          comment: "Title of invite sheet")
    }

    static var groupInviteSheetUseLinkVia: String {
        NSLocalizedString("group.invitesheet.use.link.via",
                          value: "Share link using…",
                          comment: "Section header describing options to share link")
    }
}

class GroupInviteSheetViewController: BottomSheetViewController {

    private let groupInviteLink: String

    init(groupInviteLink: String) {
        self.groupInviteLink = groupInviteLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.text = Localizations.groupInviteSheetTitle
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label.withAlphaComponent(0.8)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let shareUrlLabel = GroupInviteCopyableLabel()
        shareUrlLabel.font = .systemFont(ofSize: 16, weight: .medium)
        shareUrlLabel.text = groupInviteLink
        shareUrlLabel.textColor = .label.withAlphaComponent(0.5)
        shareUrlLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareUrlLabel)

        let shareViaLabel = UILabel()
        shareViaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        shareViaLabel.text = Localizations.groupInviteSheetUseLinkVia.uppercased()
        shareViaLabel.textColor = .label.withAlphaComponent(0.5)
        shareViaLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareViaLabel)

        var shareOptionButtons: [GroupInviteSheetButton] = []

        let whatsAppButton = GroupInviteSheetButton()
        whatsAppButton.addTarget(self, action: #selector(inviteViaWhatsApp), for: .touchUpInside)
        whatsAppButton.imageView.image = UIImage(named: "WhatsAppLogo")
        whatsAppButton.titleLabel.text = Localizations.appNameWhatsApp
        shareOptionButtons.append(whatsAppButton)

        let canInviteViaWhatsApp = URL(string: "whatsapp://app").flatMap({ UIApplication.shared.canOpenURL($0) }) ?? false
        whatsAppButton.alpha = canInviteViaWhatsApp ? 1 : 0
        whatsAppButton.isUserInteractionEnabled = canInviteViaWhatsApp

        let messageButton = GroupInviteSheetButton()
        messageButton.addTarget(self, action: #selector(inviteViaMessages), for: .touchUpInside)
        messageButton.imageView.image = UIImage(named: "MessagesLogo")
        messageButton.titleLabel.text = Localizations.appNameSMS
        shareOptionButtons.append(messageButton)

        let canInviteViaText = MFMessageComposeViewController.canSendText()
        messageButton.alpha = canInviteViaText ? 1 : 0
        messageButton.isUserInteractionEnabled = canInviteViaText

        let copyButton = GroupInviteSheetButton()
        copyButton.addTarget(self, action: #selector(copyInviteLink), for: .touchUpInside)
        copyButton.imageView.image = UIImage(systemName: "link")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .bold))
            .withRenderingMode(.alwaysTemplate)
        copyButton.titleLabel.text = Localizations.groupInviteCopyLink
        shareOptionButtons.append(copyButton)

        let moreButton = GroupInviteSheetButton()
        moreButton.addTarget(self, action: #selector(openSystemShareMenu), for: .touchUpInside)
        moreButton.imageView.image = UIImage(systemName: "ellipsis")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .bold))
            .withRenderingMode(.alwaysTemplate)
            .withAlignmentRectInsets(.zero)
        moreButton.titleLabel.text = Localizations.buttonMore
        shareOptionButtons.append(moreButton)

        // UIStackView removes any hidden views, we want to maintain them to take advantage of stack views
        // equal spacing. However, we should move them to end, so we simply sort by alpha.
        var visibleShareOptionButtons: [UIView] = []
        var hiddenShareOptionButtons: [UIView] = []
        shareOptionButtons.forEach { shareOptionButton in
            if shareOptionButton.alpha > 0 {
                visibleShareOptionButtons.append(shareOptionButton)
            } else {
                hiddenShareOptionButtons.append(shareOptionButton)
            }
        }

        let buttonStackView = UIStackView(arrangedSubviews: visibleShareOptionButtons + hiddenShareOptionButtons)
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .equalSpacing
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(buttonStackView)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),

            shareUrlLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shareUrlLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            shareUrlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            shareViaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            shareViaLabel.topAnchor.constraint(equalTo: shareUrlLabel.bottomAnchor, constant: 24),

            buttonStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonStackView.topAnchor.constraint(equalTo: shareViaLabel.bottomAnchor, constant: 8),
            buttonStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    private var shareText: String {
        return "\(Localizations.groupInviteShareLinkMessage) \(groupInviteLink)"
    }

    @objc private func inviteViaWhatsApp() {
        dismiss(animated: true)

        guard let escapedShareText = shareText.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
              let url = URL(string: "whatsapp://send?text=\(escapedShareText)") else {
                  DDLogError("GroupInviteSheetViewController/Unable to create Whatsapp URL")
                  return
              }
        Analytics.log(event: .sendInvite, properties: [.service: "whatsapp"])
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc private func inviteViaMessages() {
        dismiss(animated: true) { [presentingViewController, shareText] in
            let messageComposeViewController = GroupInviteSheetMessageComposeViewController()
            messageComposeViewController.body = shareText
            presentingViewController?.present(messageComposeViewController, animated: true)
        }
    }

    @objc private func copyInviteLink() {
        UIPasteboard.general.string = groupInviteLink
        dismiss(animated: true)
    }

    @objc private func openSystemShareMenu() {
        dismiss(animated: true) { [presentingViewController, shareText] in
            let activityViewController = UIActivityViewController(activityItems: [shareText],
                                                                  applicationActivities: nil)
            presentingViewController?.present(activityViewController, animated: true)
        }
    }
}

private class GroupInviteSheetMessageComposeViewController: MFMessageComposeViewController, MFMessageComposeViewControllerDelegate {

    init() {
        super.init(nibName: nil, bundle: nil)
        messageComposeDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        if result == .sent {
            controller.recipients?.forEach { _ in Analytics.log(event: .sendInvite, properties: [.service: "sms"]) }
        }
        dismiss(animated: true)
    }
}

private class GroupInviteCopyableLabel: UILabel {

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = true
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(openMenu)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(copy(_:))
    }

    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = text
    }

    @objc private func openMenu() {
        becomeFirstResponder()
        UIMenuController.shared.showMenu(from: self, rect: bounds)
    }
}

private class GroupInviteSheetButton: UIControl {

    let imageView = UIImageView()
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.backgroundColor = UIColor(red: 0.855, green: 0.843, blue: 0.812, alpha: 1)
        imageView.contentMode = .center
        imageView.layer.cornerRadius = 13
        imageView.layer.masksToBounds = true
        imageView.tintColor = .black.withAlphaComponent(0.7)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let imageViewLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: leadingAnchor)
        imageViewLeadingConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            imageViewLeadingConstraint,
            imageView.widthAnchor.constraint(equalToConstant: 55),
            imageView.heightAnchor.constraint(equalToConstant: 55),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            let alpha = isHighlighted ? 0.8 : 1
            imageView.alpha = alpha
            titleLabel.alpha = alpha
        }
    }
}
