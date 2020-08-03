//
//  AvatarView.swift
//  Core
//
//  Created by Alan Luo on 7/2/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Combine
import UIKit

public class AvatarView: UIImageView {
    private var avatarUpdatingCancellable: AnyCancellable?
    
    public static let defaultImage = UIImage(named: "AvatarPlaceholder")
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        applyCornerRadius()
    }
    
    public init() {
        super.init(frame: .zero)
        
        self.contentMode = .scaleAspectFill
        self.image = AvatarView.defaultImage
        self.tintColor = .systemGray
        self.translatesAutoresizingMaskIntoConstraints = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configure(with userId: UserID, using avatarStore: AvatarStore) {
        let userAvatar = avatarStore.userAvatar(forUserId: userId)
        configure(with: userAvatar, using: avatarStore)
    }
    
    public func configure(with userAvatar: UserAvatar, using avatarStore: AvatarStore) {
        if let image = userAvatar.image {
            self.image = image
        } else {
            self.image = AvatarView.defaultImage
            
            if !userAvatar.isEmpty {
                userAvatar.loadImage(using: avatarStore)
            }
        }
        
        avatarUpdatingCancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.image = image
            } else {
                self.image = AvatarView.defaultImage
            }
        }
    }
    
    public func prepareForReuse() {
        avatarUpdatingCancellable?.cancel()
        self.image = AvatarView.defaultImage
    }
    
    private func applyCornerRadius() {
        let rect = self.bounds
        let cornerRadius = min(rect.height, rect.width) / 2
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        
        self.layer.mask = maskLayer
    }

    public override var intrinsicContentSize: CGSize {
        get { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
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
