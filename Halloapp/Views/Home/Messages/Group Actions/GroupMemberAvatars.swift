//
//  GroupMemberAvatars.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
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
   
    private var avatarUserIDs: [UserID] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    func configure(with avatars: [UserID]) {
        avatarUserIDs = avatars
        for (index, avatarUserID) in avatars.enumerated() {

            let avatarView = AvatarView()
            avatarView.configure(with: avatarUserID, using: MainAppContext.shared.avatarStore)
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
            
            let deleteButtonSize: CGFloat = 25
            
            let button = UIImageView()
            button.image = UIImage(systemName: "xmark")?
                .withRenderingMode(.alwaysTemplate)
//                .withAlignmentRectInsets(UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7))
                
            button.contentMode = .center
            button.tintColor = UIColor.white
            button.backgroundColor = UIColor.systemGray
            
            button.layer.masksToBounds = false
            button.layer.cornerRadius = deleteButtonSize/2
            button.clipsToBounds = true
            
            button.frame = CGRect(x: avatarView.bounds.maxX - 15, y: -5, width: deleteButtonSize, height: deleteButtonSize)
            button.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            
            button.tag = index
            
            
            button.isUserInteractionEnabled = true
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.deleteImage(_:)))
            button.addGestureRecognizer(tapGestureRecognizer)
            
            
            avatarView.isUserInteractionEnabled = true
            
            avatarView.addSubview(button)
            

            avatarView.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10);
            
            
            innerStack.addArrangedSubview(avatarView)
            
        }
        
        // Set the scrollView contentSize
        let contentSizeWidth = Constants.AvatarSize * CGFloat(avatars.count)

        scrollView.contentSize = CGSize(width: contentSizeWidth, height: 100)
        
        mainView.constrain(to: self) // constrain again since subviews were added to scrollview
        
    }
    
    func insert(with avatars: [UserID]) {
        avatarUserIDs = avatars
        for (index, avatarUserID) in avatars.enumerated() {

            let avatarView = AvatarView()
            avatarView.configure(with: avatarUserID, using: MainAppContext.shared.avatarStore)
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
            
            let deleteButtonSize: CGFloat = 25
            
            let button = UIImageView()
            button.image = UIImage(systemName: "xmark")?
                .withRenderingMode(.alwaysTemplate)
//                .withAlignmentRectInsets(UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7))
                
            button.contentMode = .center
            button.tintColor = UIColor.white
            button.backgroundColor = UIColor.systemGray
            
            button.layer.masksToBounds = false
            button.layer.cornerRadius = deleteButtonSize/2
            button.clipsToBounds = true
            
            button.frame = CGRect(x: avatarView.bounds.maxX - 15, y: -5, width: deleteButtonSize, height: deleteButtonSize)
            button.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            
            button.tag = index
            
            
            button.isUserInteractionEnabled = true
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.deleteImage(_:)))
            button.addGestureRecognizer(tapGestureRecognizer)
            
            
            avatarView.isUserInteractionEnabled = true
            
            avatarView.addSubview(button)
            

            avatarView.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10);
            
            
            innerStack.addArrangedSubview(avatarView)
            
        }
        
        // Set the scrollView contentSize
        let contentSizeWidth = Constants.AvatarSize * CGFloat(avatars.count)

        scrollView.contentSize = CGSize(width: contentSizeWidth, height: 100)
        
        
        
//        mainView.constrain(to: self) // constrain again since subviews were added to scrollview
        
        scrollView.contentSize.height = 1.0
        
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
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        
        return view
    }()
    
    // MARK: Actions
    
    @objc private func deleteImage(_ sender: AnyObject) {
        
    
        let selectedUserID = avatarUserIDs[sender.view.tag]
        
        delegate?.groupMemberAvatarsDelegate(self, selectedUser: selectedUserID)
        
        if let view2 = sender.view.superview {
            view2.removeFromSuperview()
        }
    }
    
    // MARK: Helpers
    

}

