//
//  UICollectionView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/20/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

extension UICollectionView {

    // I can't find an API to adjust orthogonal embedded scroll views
    func scrollEmbeddedOrthoginalScrollViewsToOrigin(animated: Bool) {
        for case let scrollView as UIScrollView in subviews {
            // TODO: add support for vertical orthoginal scrollers
            let offset = CGPoint(x: -scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y)
            scrollView.setContentOffset(offset, animated: animated)
        }
    }
}
