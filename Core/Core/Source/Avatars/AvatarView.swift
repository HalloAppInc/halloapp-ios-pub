//
//  AvatarView.swift
//  Core
//
//  Created by Alan Luo on 7/2/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Combine
import UIKit

public class AvatarView: UIView {
    public static let defaultImage = UIImage(named: "AvatarPlaceholder")
    
    private let avatar = UIImageView()
    private var avatarUpdatingCancellable: AnyCancellable?
    private var borderLayer: CAShapeLayer?
    
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
            if oldValue != self.bounds {
                applyCornerRadius()
                applyBorder()
            }
        }
    }
    
    public override var frame: CGRect {
        didSet {
            if oldValue != self.frame {
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
        avatar.contentMode = .scaleAspectFit
        avatar.image = AvatarView.defaultImage
        avatar.tintColor = .systemGray
        self.addSubview(avatar)
        
        self.translatesAutoresizingMaskIntoConstraints = false
    }
    
    public func configure(with userId: UserID, using avatarStore: AvatarStore) {
        let userAvatar = avatarStore.userAvatar(forUserId: userId)
        configure(with: userAvatar, using: avatarStore)
    }
    
    public func configure(with userAvatar: UserAvatar, using avatarStore: AvatarStore) {
        if let image = userAvatar.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultImage
            
            if !userAvatar.isEmpty {
                userAvatar.loadImage(using: avatarStore)
            }
        }
        
        avatarUpdatingCancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultImage
            }
        }
    }
    
    public func prepareForReuse() {
        avatarUpdatingCancellable?.cancel()
    }
    
    public func resetImage() {
        avatar.image = AvatarView.defaultImage
    }
    
    private func applyCornerRadius() {
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(ovalIn: self.bounds).cgPath
        self.layer.mask = maskLayer
    }
    
    private func applyBorder() {
        if let borderColor = borderColor, let borderWidth = borderWidth, borderWidth > 0 {
            avatar.frame = self.bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            
            let border = CAShapeLayer()
            border.fillColor = UIColor.clear.cgColor
            border.strokeColor = borderColor.cgColor
            border.lineWidth = borderWidth * 2 // Make sure the stroke can reach the border
            border.path = UIBezierPath(ovalIn: self.bounds).cgPath
            
            if let oldBorderLayer = borderLayer {
                self.layer.replaceSublayer(oldBorderLayer, with: border)
            } else {
                self.layer.addSublayer(border)
            }
            
            borderLayer = border
        } else {
            avatar.frame = self.bounds
            
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


public class AvatarViewButton: UIButton {

    public let avatarView = AvatarView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.addSubview(avatarView)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.frame = self.bounds
        avatarView.isUserInteractionEnabled = false
    }

    public override var intrinsicContentSize: CGSize {
        // Something random but rational.
        get { CGSize(width: 32, height: 32) }
    }

    public override var isEnabled: Bool {
        didSet {
            // Value is chosen to mimic behavior of UIButton with type "system".
            avatarView.alpha = isEnabled ? 1 : 0.35
        }
    }

    public override var isHighlighted: Bool {
        didSet {
            // Value is chosen to mimic behavior of UIButton with type "system".
            avatarView.alpha = isHighlighted ? 0.2 : 1
        }
    }
}
