//
//  AvatarView.swift
//  Core
//
//  Created by Alan Luo on 7/2/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import Combine
import UIKit
import CocoaLumberjackSwift

public class AvatarView: UIView {
    public static let defaultImage = UIImage(named: "AvatarUser")
    public static var defaultGroupImage = UIImage(named: "AvatarGroup")

    public private(set) var hasImage: Bool = false {
        didSet {
            placeholderOverlayView?.isHidden = hasImage
        }
    }
    private var avatar = UIImageView()
    private let avatarContainerView = UIView()
    private var avatarUpdatingCancellable: AnyCancellable?
    private var userCacheCancellable: AnyCancellable?
    private var borderLayer: CAShapeLayer?

    /**
      Caller is responsible for configuring overlay's bounds and position.
     */
    public var placeholderOverlayView: UIView? {
        willSet {
            if let view = placeholderOverlayView {
                view.removeFromSuperview()
            }
        }
        didSet {
            if let view = placeholderOverlayView {
                addSubview(view)
            }
        }
    }
    
    public var borderColor: UIColor? {
        didSet {
            if oldValue != borderColor {
                applyBorder()
            }
        }
    }
    
    public var borderWidth: CGFloat? {
        didSet {
            if oldValue != borderWidth {
                applyBorder()
            }
        }
    }
    
    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                applyCornerRadius()
                applyBorder()
            }
        }
    }
    
    public override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                applyCornerRadius()
                applyBorder()
            }
        }
    }
    
    public var imageAlpha: CGFloat {
        get {
            avatar.alpha
        }
        set {
            avatar.alpha = newValue
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        isUserInteractionEnabled = false
        
        avatar.contentMode = .scaleAspectFit
        avatar.image = AvatarView.defaultImage
        avatarContainerView.addSubview(avatar)
        addSubview(avatarContainerView)
    }
    
    public func configure(with userId: UserID, using avatarStore: AvatarStore) {
        let userAvatar = avatarStore.userAvatar(forUserId: userId)
        configure(with: userAvatar, using: avatarStore)
    }
    
    public func configure(with userAvatar: UserAvatar, using avatarStore: AvatarStore) {
        if let image = userAvatar.image {
            hasImage = true
            avatar.image = image
        } else {
            hasImage = false
            avatar.image = AvatarView.defaultImage

            if !userAvatar.isEmpty {
                userAvatar.loadThumbnailImage(using: avatarStore)
            }
        }
        
        avatarUpdatingCancellable?.cancel()
        avatarUpdatingCancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }
            self.hasImage = image != nil
            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultImage
            }
        }

        userCacheCancellable = avatarStore.userCacheUpdates
            .filter { $0.userId == userAvatar.userId }
            .sink { [weak self] in
                self?.configure(with: $0, using: avatarStore)
            }
    }

    public func configure(image: UIImage?) {
        avatar.image = image
        avatarUpdatingCancellable?.cancel()
        userCacheCancellable?.cancel()
    }

    public func prepareForReuse() {
        avatarUpdatingCancellable?.cancel()
        userCacheCancellable?.cancel()
        avatar.image = AvatarView.defaultImage
        hasImage = false
    }
    
    public func resetImage() {
        hasImage = false
        avatar.image = AvatarView.defaultImage
    }
    
    private func applyCornerRadius() {
        avatarContainerView.frame = bounds
        let avatarBounds = avatarContainerView.bounds
        avatarContainerView.layer.cornerRadius = min(avatarBounds.width, avatarBounds.height) / 2
        avatarContainerView.clipsToBounds = true
    }
    
    private func applyBorder() {
        avatarContainerView.frame = bounds
        if let borderColor = borderColor, let borderWidth = borderWidth, borderWidth > 0 {
            avatar.frame = avatarContainerView.bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            
            let border = CAShapeLayer()
            border.fillColor = UIColor.clear.cgColor
            border.strokeColor = borderColor.cgColor
            border.lineWidth = borderWidth * 2 // Make sure the stroke can reach the border
            border.path = UIBezierPath(roundedRect: avatarContainerView.bounds, cornerRadius: avatarContainerView.layer.cornerRadius).cgPath
            if let oldBorderLayer = borderLayer {
                avatarContainerView.layer.replaceSublayer(oldBorderLayer, with: border)
            } else {
                avatarContainerView.layer.addSublayer(border)
            }
            borderLayer = border
        } else {
            avatar.frame = avatarContainerView.bounds
            
            if let oldBorderLayer = borderLayer {
                oldBorderLayer.removeFromSuperlayer()
                borderLayer = nil
            }
        }
    }

    public override var intrinsicContentSize: CGSize {
        get { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Reapply borderColor
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle,
            let borderColor = borderColor {
            borderLayer?.strokeColor = borderColor.cgColor
        }
    }
}

extension AvatarView {

    public func configure(groupId: GroupID, squareSize: CGFloat = 0, using avatarStore: AvatarStore) {

        let groupAvatarData = avatarStore.groupAvatarData(for: groupId)

        let isSquare = squareSize > 0

        let radiusRatio = CGFloat(16) / CGFloat(52)

        let borderRadius:CGFloat = {
            switch squareSize {
            case 1...50:
                return 11
            default:
                return squareSize * radiusRatio
            }
        }()

        if isSquare {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.avatarContainerView.backgroundColor = UIColor(named: "AvatarDefaultBg")!
                self.avatarContainerView.layer.mask = nil
                self.avatarContainerView.layer.cornerRadius = borderRadius
                self.avatarContainerView.clipsToBounds = true
                self.avatarContainerView.layoutIfNeeded()
            }
        }

        if let image = groupAvatarData.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultGroupImage
            if !groupAvatarData.isEmpty {
                groupAvatarData.loadImage(using: avatarStore)
            }
        }

        avatarUpdatingCancellable?.cancel()
        avatarUpdatingCancellable = groupAvatarData.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultGroupImage
            }
        }

    }
}

extension AvatarView {

    public func configure(contactIdentfier identifer: String, using avatarStore: AvatarStore) {
        let addressBookAvatar = avatarStore.addressBookAvatar(for: identifer)

        if let image = addressBookAvatar.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultImage
            addressBookAvatar.loadImage(using: avatarStore)
        }

        avatarUpdatingCancellable?.cancel()
        avatarUpdatingCancellable = addressBookAvatar.imageDidChange.sink { [weak self] image in
            self?.avatar.image = image ?? AvatarView.defaultImage
        }
    }
}
