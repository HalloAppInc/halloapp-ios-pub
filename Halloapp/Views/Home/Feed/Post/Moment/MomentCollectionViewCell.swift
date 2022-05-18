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

    private(set) lazy var momentView: MomentView = {
        let view = MomentView(style: .normal)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// - note: `headerView` and `facePileView` are only shown for the user's own moment post.
    private(set) lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.showUserAction = { [weak self] in self?.showUserAction?() }
        view.showMoreAction = { [weak self] in self?.showMoreAction?() }
        return view
    }()

    private(set) lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.avatarViews.forEach { $0.borderColor = .feedBackground }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addTarget(self, action: #selector(seenByTapped), for: .touchUpInside)
        return view
    }()

    private var momentViewLeading: NSLayoutConstraint?
    private var momentViewTrailing: NSLayoutConstraint?

    var showUserAction: (() -> Void)?
    var showMoreAction: (() -> Void)?
    var showSeenByAction: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true
        
        contentView.addSubview(momentView)
        let spacing = MomentView.LayoutConstants.interCardSpacing

        let leading = momentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: layoutMargins.left)
        let trailing = momentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -layoutMargins.right)
        let top = momentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing / 2)
        let bottom = momentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing / 2)

        // these top and bottom constraints are used when displaying other people's moments
        top.priority = UILayoutPriority(rawValue: UILayoutPriority.defaultHigh.rawValue - 1)
        bottom.priority = UILayoutPriority(rawValue: UILayoutPriority.defaultHigh.rawValue - 1)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            top,
            bottom,
        ])
        
        momentViewLeading = leading
        momentViewTrailing = trailing
    }

    @objc
    private func seenByTapped(_ sender: AnyObject) {
        showSeenByAction?()
    }
    
    required init?(coder: NSCoder) {
        fatalError("SecretPostCollectionViewCell required init not implemented...")
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        momentViewLeading?.constant = layoutMargins.left * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5
        momentViewTrailing?.constant = -layoutMargins.right * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        momentView.prepareForReuse()
        facePileView.prepareForReuse()
        headerView.prepareForReuse()
    }
    
    func configure(with post: FeedPost, contentWidth: CGFloat) {
        guard post.isMoment else {
            return
        }

        if post.userID == MainAppContext.shared.userData.userId {
            installHeaderAndFooter()
        } else {
            removeHeaderAndFooter()
        }
        
        momentView.configure(with: post)
        headerView.configure(with: post, contentWidth: bounds.width, showGroupName: false)
        facePileView.configure(with: post)
    }

    private func installHeaderAndFooter() {
        guard headerView.superview == nil else {
            return
        }

        contentView.addSubview(headerView)
        contentView.addSubview(facePileView)

        let spacing = MomentView.LayoutConstants.interCardSpacing

        let headerTop = headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing / 2)
        let headerLeading = headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor)
        let headerTrailing = headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor)

        let momentTop = momentView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 7)
        let momentBottom = momentView.bottomAnchor.constraint(equalTo: facePileView.topAnchor, constant: -7)

        let faceBottom = facePileView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing / 2)
        let faceTrailing = facePileView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor)
        faceBottom.priority = .defaultHigh
        faceTrailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            headerTop,
            headerLeading,
            headerTrailing,
            momentTop,
            momentBottom,
            faceBottom,
            faceTrailing
        ])
    }

    private func removeHeaderAndFooter() {
        headerView.removeFromSuperview()
        facePileView.removeFromSuperview()
    }
}
