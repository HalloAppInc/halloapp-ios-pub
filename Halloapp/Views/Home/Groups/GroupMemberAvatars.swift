//
//  GroupMemberAvatars.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 50
}

protocol GroupMemberAvatarsDelegate: AnyObject {
    func groupMemberAvatarsDelegate(_ view: GroupMemberAvatars, selectedUser: String)
}

class GroupMemberAvatars: UIView, UIScrollViewDelegate {
    weak var delegate: GroupMemberAvatarsDelegate?

    public var showActionButton: Bool = true
    public var scrollToLastAfterInsert: Bool = true
    private(set) var avatarUserIDs: [UserID] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func insert(with avatars: [UserID]) {

        var didAddNewAvatar = false
        for (_, avatarUserID) in avatars.enumerated() {
            guard !avatarUserIDs.contains(avatarUserID) else { continue }
            
            avatarUserIDs.append(avatarUserID)
            didAddNewAvatar = true
            
            // avatar image
            let avatarView = AvatarView()
            avatarView.configure(with: avatarUserID, using: MainAppContext.shared.avatarStore)
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
            
            // delete icon
            let deleteIconSize: CGFloat = 25
            let deleteIcon = TaggableUIImageView()
            deleteIcon.image = UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate)
            deleteIcon.contentMode = .center
            deleteIcon.tintColor = UIColor.secondarySystemGroupedBackground
            deleteIcon.backgroundColor = UIColor.label
            deleteIcon.layer.masksToBounds = false
            deleteIcon.layer.cornerRadius = deleteIconSize/2
            deleteIcon.clipsToBounds = true
            deleteIcon.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            
            deleteIcon.tagString = avatarUserID
            
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(deleteImage(_:)))
            deleteIcon.addGestureRecognizer(tapGestureRecognizer)
            deleteIcon.isUserInteractionEnabled = true
            
            // name label
            let nameLabel = UILabel()
            nameLabel.numberOfLines = 1
            nameLabel.font = .systemFont(ofSize: 11)
            nameLabel.textColor = .label
            nameLabel.textAlignment = .center
            nameLabel.text = MainAppContext.shared.contactStore.firstName(for: avatarUserID)
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            
            // main avatar container
            let avatarBoxView = UIView()
            
            avatarBoxView.translatesAutoresizingMaskIntoConstraints = false
            avatarBoxView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize + 15).isActive = true
            avatarBoxView.heightAnchor.constraint(equalToConstant: Constants.AvatarSize + 25).isActive = true
            
            // add avatar image
            avatarBoxView.addSubview(avatarView)
            
            avatarView.centerXAnchor.constraint(equalTo: avatarBoxView.centerXAnchor).isActive = true
            avatarView.topAnchor.constraint(equalTo: avatarBoxView.topAnchor, constant: 10).isActive = true
            
            // add delete icon
            if showActionButton {
                deleteIcon.frame = CGRect(x: avatarBoxView.bounds.maxX - deleteIconSize, y: 0, width: deleteIconSize, height: deleteIconSize)
                avatarBoxView.addSubview(deleteIcon)
            }
            
            // add name label
            avatarBoxView.addSubview(nameLabel)
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarBoxView.leadingAnchor).isActive = true
            nameLabel.trailingAnchor.constraint(equalTo: avatarBoxView.trailingAnchor).isActive = true
            nameLabel.bottomAnchor.constraint(equalTo: avatarBoxView.bottomAnchor).isActive = true
            
            // add main avatar container into scrollview
            innerStack.addArrangedSubview(avatarBoxView)
        }
        
        DispatchQueue.main.async {
            self.setContentSizeAndOffset(scrollToEnd: self.scrollToLastAfterInsert && didAddNewAvatar)
        }
    }
    
    private func setup() {
        addSubview(mainView)
        mainView.constrain(to: self)
    }
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ scrollViewRow ])
        view.axis = .vertical
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var scrollViewRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ scrollView ])
        view.axis = .horizontal
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.delegate = self
        
        view.addSubview(innerStack)
        
        innerStack.constrain(to: view)
        
        return view
    }()
    
    private lazy var innerStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [])
        view.axis = .horizontal
        view.spacing = 10
        
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    func removeUser(_ userID: UserID) {
        guard let index = avatarUserIDs.firstIndex(where: {$0 == userID}) else { return }
        
        avatarUserIDs.removeAll(where: {$0 == userID})
        
        let subview = innerStack.arrangedSubviews[index]
        innerStack.removeArrangedSubview(subview)
        subview.removeFromSuperview()

        setContentSizeAndOffset(scrollToEnd: false)
    }
    
    // MARK: Actions
    
    @objc private func deleteImage(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view as? TaggableUIImageView else { return }
        guard let userID = view.tagString else { return }
       
        avatarUserIDs.removeAll(where: {$0 == userID})
        
        delegate?.groupMemberAvatarsDelegate(self, selectedUser: userID)
        
        if let parent = view.superview {
            parent.removeFromSuperview()
        }
        
        setContentSizeAndOffset(scrollToEnd: false)
    }
    
    // MARK: Helpers
    
    private func setContentSizeAndOffset(scrollToEnd: Bool) {
        let contentSizeWidth = innerStack.bounds.width + 20
        let currentContentOffset = scrollView.contentOffset

        let maxOffsetX = max(0, contentSizeWidth - scrollView.bounds.width)
        let newOffsetX = scrollToEnd ? maxOffsetX : min(currentContentOffset.x, maxOffsetX)
        let newOffset = CGPoint(x: newOffsetX, y: 0)

        scrollView.contentSize = CGSize(width: contentSizeWidth, height: 1)
        scrollView.setContentOffset(newOffset, animated: true)
    }
    
}

fileprivate class TaggableUIImageView:UIImageView {
    var tagString: String?
}
