//
//  StackedMomentCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 7/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class StackedMomentCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "stacked.moment.cell"

    private(set) lazy var stackedView: StackedMomentView = {
        let view = StackedMomentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var stackedViewLeading = stackedView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                                              constant: layoutMargins.left)
    private lazy var stackedViewTrailing = stackedView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                                                constant: -layoutMargins.right)

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        contentView.addSubview(stackedView)

        let spacing = MomentView.LayoutConstants.interCardSpacing
        NSLayoutConstraint.activate([
            stackedViewLeading,
            stackedViewTrailing,
            stackedView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing / 2),
            stackedView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing / 2),
        ])

        contentView.clipsToBounds = false
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("StackedMomentCollectionViewCell coder init not implemented...")
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        stackedViewLeading.constant = layoutMargins.left * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 8.25
        stackedViewTrailing.constant = -layoutMargins.right * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 8.25
    }

    func configure(with items: [MomentStackItem]) {
        stackedView.configure(with: items)
    }
}
