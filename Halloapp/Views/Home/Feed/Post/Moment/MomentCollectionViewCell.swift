//
//  MomentCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 4/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

class MomentCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "secretPostCell"
    
    private(set) lazy var momentView = MomentView()
    
    private var contentViewWidthConstraint: NSLayoutConstraint?
    
    private var momentViewLeading: NSLayoutConstraint?
    private var momentViewTrailing: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true
        
        contentView.addSubview(momentView)
        momentView.translatesAutoresizingMaskIntoConstraints = false
        
        let ratio = MomentView.LayoutConstants.backgroundPanelHMarginRatio
        let spacing = MomentView.LayoutConstants.interCardSpacing
        
        let leading = momentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                         constant: layoutMargins.left * ratio * 3)
        let trailing = momentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                           constant: -layoutMargins.right * ratio * 3)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            momentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing / 2),
            momentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing / 2),
        ])
        
        momentViewLeading = leading
        momentViewTrailing = trailing
    }
    
    required init?(coder: NSCoder) {
        fatalError("SecretPostCollectionViewCell required init not implemented...")
    }
    
    func configure(with post: FeedPost, contentWidth: CGFloat) {
        guard post.isMoment else {
            return
        }
        
        momentView.configure(with: post)
    }
    
    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        momentViewLeading?.constant = layoutMargins.left * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 4
        momentViewTrailing?.constant = -layoutMargins.right * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 4
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        momentView.prepareForReuse()
    }
}
