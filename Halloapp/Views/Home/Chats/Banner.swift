//
//  Banner.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import UIKit

// MARK: Constraint Constants
fileprivate struct Constants {
    static let AvatarSize: CGFloat = 50
}

class Banner {

    static let animateDuration = 0.5
    static let bannerDuration: TimeInterval = 2
    
    static func show(title: String, body: String, userID: String? = nil, groupID: GroupID? = nil, using avatarStore: AvatarStore) {
        guard let superView = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        
        let width = superView.bounds.size.width
        let height: CGFloat = 110
        
        let bannerView = BannerView(frame: CGRect(x: 0, y: 0 - height, width: width, height: height))
        bannerView.configure(title: title, body: body, userID: userID, groupID: groupID, using: avatarStore)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
              
        superView.addSubview(bannerView)
    
        bannerView.widthAnchor.constraint(equalToConstant: width).isActive = true
        bannerView.heightAnchor.constraint(equalToConstant: height).isActive = true
 
        let bannerTopConstraint = NSLayoutConstraint(item: bannerView, attribute: .top, relatedBy: .equal, toItem: superView, attribute: .top, multiplier: 1, constant: 0 - height)

        NSLayoutConstraint.activate([bannerTopConstraint])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIView.animate(withDuration: animateDuration) {
                bannerTopConstraint.constant = 0
                superView.layoutIfNeeded()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + bannerDuration) {
                UIView.animate(withDuration: animateDuration, animations: {
                    bannerTopConstraint.constant = 0 - bannerView.frame.height
                    superView.layoutIfNeeded()
                }, completion: { finished in
                    if finished {
                        bannerView.removeFromSuperview()
                    }
                })
            }
        }
    }
}


class BannerView: UIView, UIGestureRecognizerDelegate {

    var type: ChatType = .oneToOne
    var userID: UserID? = nil
    var groupID: GroupID? = nil
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configure(title: String, body: String, userID: UserID? = nil, groupID: GroupID? = nil, using avatarStore: AvatarStore) {

        if let userID = userID {
            self.type = .oneToOne
            self.userID = userID
            avatarView.configure(with: userID, using: avatarStore)
        } else if let groupID = groupID {
            self.type = .group
            self.groupID = groupID
            avatarView.configure(groupId: groupID, using: avatarStore)
        }
        
        titleLabel.text = title
        let ham = HAMarkdown(font: bodyLabel.font, color: bodyLabel.textColor)
        bodyLabel.attributedText = ham.parse(body)
    }
    
    private func setup() {
        backgroundColor = UIColor.systemGray2
        addSubview(mainView)
        mainView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        mainView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.backgroundColor = UIColor.white
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ avatarView, textColumn ])
        view.axis = .horizontal
        view.alignment = .center
     
        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        
        isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoChat(_:)))
        addGestureRecognizer(tapGesture)
        
        let slideUp = UISwipeGestureRecognizer(target: self, action: #selector(dismiss(_:)))
        slideUp.direction = .up
        addGestureRecognizer(slideUp)

        return view
    }()

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        return view
    }()
    
    private lazy var textColumn: UIStackView = {
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottomSpacer = UIView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let view = UIStackView(arrangedSubviews: [ titleRow, bodyRow ])
        view.axis = .vertical
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var titleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ titleLabel ])
        view.axis = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.boldSystemFont(ofSize: 16.0)
        label.textColor = .label
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var bodyRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ bodyLabel ])
        view.axis = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textColor = .label
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    @objc func gotoChat(_ sender: UIView) {
        var id: String? = nil
        var notificationType: NotificationContentType
    
        if type == .oneToOne {
            notificationType = .chatMessage
            id = userID
        } else {
            notificationType = .groupAdd
            id = groupID
        }
        
        guard let contentId = id else { return }
        
        let metadata = NotificationMetadata(contentId: contentId,
                                            contentType: notificationType,
                                            fromId: contentId,
                                            timestamp: nil,
                                            data: nil,
                                            messageId: nil)
        metadata.groupId = groupID
        metadata.saveToUserDefaults()
        
        MainAppContext.shared.didTapNotification.send(metadata)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.removeFromSuperview()
        }
    }
    
    @objc func dismiss(_ sender: UIView) {
        UIView.animate(withDuration: 0.2, animations: {
            self.frame.origin.y -= self.frame.height
        }, completion: { finished in
            if finished {
                self.removeFromSuperview()
            }
        })
    }
}
