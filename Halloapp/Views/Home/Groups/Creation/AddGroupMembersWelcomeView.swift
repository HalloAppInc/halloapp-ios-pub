//
//  AddGroupMembersWelcomeView.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Foundation
import UIKit

final class AddGroupMembersWelcomeView: UIView {

    var openShareLink: ((String) -> ())?
    private var groupID: GroupID?

    func configure(groupID: GroupID) {
        self.groupID = groupID
        refreshInviteLinkLabel()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        addSubview(mainView)
        mainView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [bodyColumn, footerColumn])
        view.axis = .vertical
        view.spacing = 15
        view.distribution = .fill

        view.layoutMargins = UIEdgeInsets(top: 20, left: 10, bottom: 0, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.secondarySystemGroupedBackground
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bodyColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [bodyTitleLabel, bodyLabel])
        view.axis = .vertical
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bodyTitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 19, weight: .semibold)
        label.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.9)
        label.text = Localizations.groupFeedWelcomePostTitle

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = UIColor.primaryBlackWhite.withAlphaComponent(0.6)
        label.text = Localizations.groupFeedWelcomePostBody

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var footerColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [inviteLinkBubble, shareLinkButton])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 13

        view.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 20, right: 10)
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

    // MARK: Helpers
    
    private func refreshInviteLinkLabel() {
        guard let groupID = self.groupID else { return }
        guard let sharedChatData = MainAppContext.shared.chatData else { return }
        guard let group = sharedChatData.chatGroup(groupId: groupID, in: sharedChatData.viewContext) else { return }
        inviteLinkLabel.text = ChatData.formatGroupInviteLink(group.inviteLink ?? "")

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

    @objc(shareLinkAction)
    private func shareLinkAction() {
        guard let link = inviteLinkLabel.text else { return }
        openShareLink?(link)
    }
}
