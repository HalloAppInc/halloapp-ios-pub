//
//  GroupTitleView.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/28/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

protocol GroupTitleViewDelegate: AnyObject {
    func groupTitleViewRequestsOpenGroupInfo(_ groupTitleView: GroupTitleView)
    func groupTitleViewRequestsOpenGroupFeed(_ groupTitleView: GroupTitleView)
}

class GroupTitleView: UIView {

    private struct LayoutConstants {
        static let avatarSize: CGFloat = 32
    }
    
    weak var delegate: GroupTitleViewDelegate?
    
    public var isShowingTypingIndicator: Bool = false
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func update(with groupId: String, isFeedView: Bool = false) {
        
        if let chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            nameLabel.text = chatGroup.name
            
            if !isFeedView {
                var firstNameList: [String] = []
                var fullNameList: [String] = []
                var addYourself = false
                for member in chatGroup.orderedMembers {
                    if member.userId == MainAppContext.shared.userData.userId {
                        addYourself = true
                    } else {
                        firstNameList.append(MainAppContext.shared.contactStore.firstName(for: member.userId))
                        fullNameList.append(MainAppContext.shared.contactStore.fullName(for: member.userId))
                    }
                }
                
                if addYourself {
                    firstNameList.append(Localizations.userYouCapitalized)
                    fullNameList.append(Localizations.userYouCapitalized)
                }
                
                let localizedFirstNameList = ListFormatter.localizedString(byJoining: firstNameList)
                let localizedFullNameList = ListFormatter.localizedString(byJoining: fullNameList)

                memberNamesLabel.text = localizedFirstNameList
                
                memberNamesLabel.isHidden = false
                
                DDLogDebug("GroupTitleView/memberFirstNamesList [\(localizedFirstNameList)]")
                DDLogDebug("GroupTitleView/fullNameList [\(localizedFullNameList)]")
            }
        }
        
        avatarView.configure(groupId: groupId, squareSize: LayoutConstants.avatarSize, using: MainAppContext.shared.avatarStore)
    }

    func showChatState(with typingIndicatorStr: String?) {
        let show: Bool = typingIndicatorStr != nil
        
        memberNamesLabel.isHidden = show
        typingLabel.isHidden = !show
        isShowingTypingIndicator = show
        
        guard let typingStr = typingIndicatorStr else { return }
        typingLabel.text = typingStr
        
    }
    
    private func setup() {
        avatarView = AvatarViewButton(type: .custom)
//        avatarView.hasNewPostsIndicator = ServerProperties.isGroupFeedEnabled
//        avatarView.newPostsIndicatorRingWidth = 3
//        avatarView.newPostsIndicatorRingSpacing = 1
        let avatarButtonWidth: CGFloat = LayoutConstants.avatarSize + (avatarView.hasNewPostsIndicator ? 2*(avatarView.newPostsIndicatorRingSpacing + avatarView.newPostsIndicatorRingWidth) : 0)
        avatarView.widthAnchor.constraint(equalToConstant: avatarButtonWidth).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
//        if ServerProperties.isGroupFeedEnabled {
//            avatarView.addTarget(self, action: #selector(avatarButtonTapped), for: .touchUpInside)
//        } else {
//            avatarView.isUserInteractionEnabled = false
//        }

        avatarView.isUserInteractionEnabled = false
        
        addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true

        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(gesture:)))
        addGestureRecognizer(tapGesture)
    }
    
    private lazy var hStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [avatarView, nameColumn])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 10
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private var avatarView: AvatarViewButton!
    
    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [nameLabel, memberNamesLabel, typingLabel])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.spacing = 0
        return view
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .primaryBlue
        return label
    }()
    
    private lazy var memberNamesLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()
    
    private lazy var typingLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()
    
    @objc func handleSingleTap(gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            delegate?.groupTitleViewRequestsOpenGroupInfo(self)
        }
    }

    @objc private func avatarButtonTapped() {
        delegate?.groupTitleViewRequestsOpenGroupFeed(self)
    }
}
