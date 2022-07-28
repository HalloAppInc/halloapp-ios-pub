//
//  GroupGridSearchBar.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 6/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class GroupGridSearchBar: UICollectionReusableView {

    /*
     When a search controller is presented, the search bar will be inserted into a new view hierarchy, and placeholder view will be inserted in its place.
     When it is dismissed, the placeholder will be replaced by the searchbar, no matter where the searchbar has moved.
     This provides a convenince wrapper view that can act as the search bar host and be shared between GroupGridSearchBarCells to provide a fixed restore point.
     */
    class SearchBarContainer: UIView {

        let searchBar: UISearchBar

        init(searchBar: UISearchBar) {
            self.searchBar = searchBar
            super.init(frame: searchBar.frame)
            addSubview(searchBar)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            searchBar.frame = bounds
        }

        override var intrinsicContentSize: CGSize {
            return searchBar.intrinsicContentSize
        }
    }

    static let elementKind = "searchBar"
    static let reuseIdentifier = String(describing: GroupGridSearchBar.self)

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    var searchBarContainer: SearchBarContainer? {
        didSet {
            if oldValue !== searchBarContainer, oldValue?.superview === self {
                oldValue?.removeFromSuperview()
            }

            guard let searchBarContainer = searchBarContainer else {
                return
            }

            addSubview(searchBarContainer)

            // Using auto-layout with the search bar breaks the active appearance where the search bar is extracted from our view hierarchy and added to
            // the search controller
            heightConstraint.priority = .defaultHigh
            heightConstraint.constant = searchBarContainer.intrinsicContentSize.height
            heightConstraint.isActive = true

            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        searchBarContainer?.frame = bounds
    }
}
