//
//  GroupInvitePreviewViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//


import CocoaLumberjack
import Core
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 100
}

class GroupInvitePreviewViewController: UIViewController {

    private var inviteLink: String

    private var groupID: GroupID? = nil

    init(for inviteLink: String) {
        self.inviteLink = inviteLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        setupView()
    }

    func setupView() {
        view.backgroundColor = UIColor.primaryBg.withAlphaComponent(0.1)

        navigationController?.setNavigationBarHidden(true, animated: true)

        view.addSubview(mainView)
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        MainAppContext.shared.chatData.getGroupPreviewWithLink(inviteLink: inviteLink) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupInviteLink):
                self.groupID = groupInviteLink.group.gid
                var numMembers: Int = 0
                groupInviteLink.group.members.forEach {
                    let userID = String($0.uid)
                    if userID != MainAppContext.shared.userData.userId {
                        numMembers += 1
                        self.groupMemberAvatars.insert(with: [userID])
                    }
                }
                DispatchQueue.main.async {
                    guard let groupID = self.groupID else { return }
                    self.groupAvatarView.configure(groupId: groupID, squareSize: Constants.AvatarSize, using: MainAppContext.shared.avatarStore)
                    self.groupNameLabel.text = groupInviteLink.group.name
                    self.numMembersLabel.text = "\(numMembers) Members"
                }
            case .failure(let error):
                DDLogDebug("GroupInviteViewController/getGroupInviteLink/error \(error)")
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [groupInfoRow, actionsRow, spacer])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.primaryBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        return view
    }()

    private lazy var groupInfoRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [groupAvatarView, groupNameLabel, numMembersLabel, groupMemberAvatars])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        groupMemberAvatars.widthAnchor.constraint(greaterThanOrEqualToConstant: UIScreen.main.bounds.size.width).isActive = true
        groupMemberAvatars.heightAnchor.constraint(lessThanOrEqualToConstant: 100).isActive = true

        return view
    }()
    
    private lazy var groupAvatarView: AvatarView = {
        let view = AvatarView()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        return view
    }()

    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 10
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()
    
    private lazy var numMembersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: UIScreen.main.bounds.size.width - 30).isActive = true

        return label
    }()
    
    private lazy var groupMemberAvatars: GroupMemberAvatars = {
        let view = GroupMemberAvatars()
        view.showActionButton = false
        view.translatesAutoresizingMaskIntoConstraints = false

        view.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        return view
    }()

    private lazy var actionsRow: UIStackView = {
        let leftSpacer = UIView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rightSpacer = UIView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [leftSpacer, cancelLabel, joinLabel])
        view.axis = .horizontal
        view.spacing = 50

        view.layoutMargins = UIEdgeInsets(top: 30, left: 20, bottom: 15, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var cancelLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.font = .systemFont(ofSize: 20)
        label.text = Localizations.buttonCancelCapitalized
        label.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cancelAction(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private lazy var joinLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .primaryBlue
        label.font = .systemFont(ofSize: 20)
        label.text = Localizations.groupPreviewJoinGroup
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(joinAction(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)
        
        return label
    }()

    // MARK: Actions

    @objc func cancelAction(_ sender: UIView) {
        dismiss(animated: true, completion: nil)
    }

    @objc func joinAction(_ sender: UIView) {
        
        MainAppContext.shared.chatData.joinGroupWithLink(inviteLink: inviteLink) { [weak self] result in
            guard let self = self else { return }
            guard let groupID = self.groupID else { return }

            switch result {
            case .success(let groupInviteLink):
                guard groupInviteLink.hasGroup else { break }
                self.dismiss(animated: true) {
                    MainAppContext.shared.groupFeedFromGroupTabPresentRequest.send(groupID)
                }
            case .failure(let error):
                switch error {
                case .serverError(let reason):
                    if reason == "already_member" {
                        self.dismiss(animated: true) {
                            MainAppContext.shared.groupFeedFromGroupTabPresentRequest.send(groupID)
                        }
                    } else {
                        DDLogDebug("GroupInviteViewController/joinGroupWithLink/error \(error)")
                        //todo: check what is good UX to handle error cases of max_group_size, invalid_invite, admin_removed
                        self.dismiss(animated: true)
                    }
                default:
                    self.dismiss(animated: true)
                }
            }
        }
    }

}

private extension Localizations {

    static var groupPreviewJoinGroup: String {
        NSLocalizedString("group.preview.join.group", value: "JOIN GROUP", comment: "Label for joining group action")
    }
}

