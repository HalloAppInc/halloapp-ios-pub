//
//  Banner.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

// MARK: Constraint Constants
fileprivate struct Constants {
    static let AvatarSize: CGFloat = 40
}

class Banner {
    static func show(title: String, body: String, userID: String? = nil, groupID: GroupID? = nil, using avatarStore: AvatarStore) {
        guard let keyWindow = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first else {
            return
        }
        
        let bannerView = BannerView(keyWindow: keyWindow)
        bannerView.configure(title: title,
                              body: body,
                            userID: userID,
                           groupID: groupID,
                             using: avatarStore)
    }
}

fileprivate class BannerView: UIView, UIGestureRecognizerDelegate {
    private static let cornerRadius: CGFloat = 16.0
    
    private(set) var type: ChatType = .oneToOne
    private(set) var userID: UserID? = nil
    private(set) var groupID: GroupID? = nil

    private var autoDismiss: DispatchWorkItem?
    private var dismissAnimator: UIViewPropertyAnimator?
    
    var topConstraint: NSLayoutConstraint?
    private var topPadding: CGFloat {
        return superview?.safeAreaInsets.top ?? .zero
    }
    
    init(keyWindow: UIWindow) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        keyWindow.addSubview(self)
        
        let topConstraint = self.topAnchor.constraint(equalTo: keyWindow.topAnchor, constant: keyWindow.safeAreaInsets.top)
        self.topConstraint = topConstraint
        
        backgroundColor = .primaryBg
        layer.cornerRadius = Self.cornerRadius
        
        addSubview(backgroundView)
        addSubview(mainView)
        
        NSLayoutConstraint.activate([
            topConstraint,
            leadingAnchor.constraint(equalTo: keyWindow.leadingAnchor, constant: 8),
            trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor, constant: -8),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainView.topAnchor.constraint(equalTo: topAnchor),
            mainView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        layoutIfNeeded()
        topConstraint.constant = -(mainView.bounds.height + keyWindow.safeAreaInsets.top)
        
        let dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.animateDismiss()
        }
        self.autoDismiss = dismissWorkItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseInOut, animations: {
                self.topConstraint?.constant = keyWindow.safeAreaInsets.top
                self.superview?.layoutIfNeeded()
            }, completion: { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: dismissWorkItem)
            })
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("Banner view coder init not implemented...")
    }

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

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ avatarView, textColumn ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = nil
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 10
        
        view.insetsLayoutMarginsFromSafeArea = false
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        
        isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoChat(_:)))
        addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        addGestureRecognizer(panGesture)

        return view
    }()
    
    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .feedPostBackground
        
        view.layer.cornerRadius = Self.cornerRadius
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.label.withAlphaComponent(0.18).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2.75)
        view.layer.shadowRadius = 3
        
        return view
    }()

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        return view
    }()
    
    private lazy var textColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ titleRow, bodyRow ])
        view.axis = .vertical
        view.spacing = 4
        
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
        label.font = UIFont.gothamFont(ofFixedSize: 16.0, weight: .medium)
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
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let path = UIBezierPath(roundedRect: backgroundView.bounds, cornerRadius: 16)
        backgroundView.layer.shadowPath = path.cgPath
    }
    
    @objc
    private func gotoChat(_ sender: UIView) {
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
        
        autoDismiss?.cancel()
        animateDismiss()
    }
    
    private func animateDismiss(using spring: UISpringTimingParameters? = nil) {
        let duration = 0.5
        if let spring = spring {
            dismissAnimator = UIViewPropertyAnimator(duration: duration, timingParameters: spring)
        } else {
            dismissAnimator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.75)
        }
        
        dismissAnimator?.addAnimations {
            self.topConstraint?.constant = -self.bounds.height
            self.superview?.layoutIfNeeded()
        }
        
        dismissAnimator?.addCompletion { _ in
            self.dismissAnimator = nil
            self.removeFromSuperview()
        }
        
        dismissAnimator?.startAnimation()
    }
    
    @objc
    private func didPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            autoDismiss?.cancel()
            fallthrough
        case .changed:
            let translation = gesture.translation(in: gesture.view)
            if translation.y > 0 {
                topConstraint?.constant = topPadding + pow(translation.y, 0.55)
            } else {
                topConstraint?.constant = topPadding + translation.y
            }
        case .ended, .cancelled:
            let spring = timingParameters(from: gesture)
            animateDismiss(using: spring)
        default:
            break
        }
    }
    
    private func timingParameters(from gesture: UIPanGestureRecognizer) -> UISpringTimingParameters {
        var velocity = CGVector.zero
        let distanceToGo = frame.maxY
        
        if distanceToGo != 0 {
            let gestureVelocity = gesture.velocity(in: gesture.view)
            let initial = abs(gestureVelocity.y) / distanceToGo
            velocity.dy = initial
        }
        
        return UISpringTimingParameters(dampingRatio: 0.75, initialVelocity: velocity)
    }
}
