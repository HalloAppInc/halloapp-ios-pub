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
    
    public static let defaultImage = UIImage.init(systemName: "person.crop.circle")
    
    public override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                applyCornerRadius()
            }
        }
    }
    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                applyCornerRadius()
            }
        }
    }
    
    public init() {
        super.init(image: AvatarView.defaultImage)
        
        tintColor = UIColor.systemGray
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configure(with userId: UserID, using avatarStore: AvatarStore) {
        let userAvatar = avatarStore.userAvatar(forUserId: userId)
        
        if let image = userAvatar.image {
            self.image = image
            self.tintColor = nil
        } else {
            self.image = AvatarView.defaultImage
            self.tintColor = UIColor.systemGray
            
            if !userAvatar.isEmpty {
                userAvatar.loadImage(using: avatarStore)
            }
        }
        
        avatarUpdatingCancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.image = image
                self.tintColor = nil
            } else {
                self.image = AvatarView.defaultImage
                self.tintColor = UIColor.systemGray
            }
        }
    }
    
    public func prepareForReuse() {
        avatarUpdatingCancellable?.cancel()
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
