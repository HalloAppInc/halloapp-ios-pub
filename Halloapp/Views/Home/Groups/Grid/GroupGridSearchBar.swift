//
//  GroupGridSearchBar.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 6/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class GroupGridSearchBar: UICollectionReusableView {

    static let elementKind = "searchBar"
    static let reuseIdentifier = String(describing: GroupGridSearchBar.self)

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    var searchBar: UISearchBar? {
        didSet {
            oldValue?.removeFromSuperview()

            guard let searchBar = searchBar else {
                return
            }

            searchBar.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21)
            addSubview(searchBar)

            // Using auto-layout with the search bar breaks the active appearance where the search bar is extracted from our view hierarchy and added to
            // the search controller
            heightConstraint.constant = searchBar.intrinsicContentSize.height
            heightConstraint.isActive = true

            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        searchBar?.frame = bounds
    }
}
