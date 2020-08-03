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
    
    public static let defaultImage = UIImage(named: "DefaultUser")
    
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
