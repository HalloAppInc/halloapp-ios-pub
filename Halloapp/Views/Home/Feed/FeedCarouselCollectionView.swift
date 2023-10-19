//
//  FeedCarouselCollectionView.swift
//  HalloApp
//
//  Created by Tanveer on 10/16/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

class FeedCarouselCollectionView: UICollectionView {

    class var layout: UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(152),
                                               heightDimension: .fractionalHeight(1.0))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 16

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal

        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: FeedCarouselCell.height)
    }
}
