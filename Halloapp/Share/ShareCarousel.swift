//
//  ShareCarousel.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/4/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

class ShareCarousel: UIView {

    var share: ((ShareProvider.Type) -> Void)?

    private enum Section {
        case all
    }

    private struct ShareDestination: Hashable {
        private let uuid = UUID()
        let icon: UIImage?
        let shareProvider: ShareProvider.Type

        static func == (lhs: ShareCarousel.ShareDestination, rhs: ShareCarousel.ShareDestination) -> Bool {
            return lhs.uuid == rhs.uuid
        }

        func hash(into hasher: inout Hasher) {
            uuid.hash(into: &hasher)
        }
    }

    private lazy var shareDestinations: [ShareDestination] = {
        return [
            ShareDestination(icon: UIImage(named: "ShareAppIconShareVia"), shareProvider: SystemShareProvider.self),
            ShareDestination(icon: UIImage(named: "ShareAppIconWhatsApp"), shareProvider: WhatsAppShareProvider.self),
            ShareDestination(icon: UIImage(named: "ShareAppIconMessages"), shareProvider: MessagesShareProvider.self),
            ShareDestination(icon: UIImage(named: "ShareAppIconTwitter"), shareProvider: TwitterShareProvider.self),
            ShareDestination(icon: UIImage(named: "ShareAppIconInstagram"), shareProvider: InstagramStoriesShareProvider.self),
        ]//.filter { $0.shareProvider.canShare }
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, ShareDestination> = {
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, shareDestination in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShareDestinationCollectionViewCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? ShareDestinationCollectionViewCell {
                cell.configure(shareDestination: shareDestination)
            }
            return cell
        }
    }()

    private lazy var collectionView: UICollectionView = {
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(64),
                                                                         heightDimension: .fractionalHeight(1.0)),
                                                       subitems: [NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                                                           heightDimension: .fractionalHeight(1.0)))])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: config)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceHorizontal = false
        collectionView.backgroundColor = nil
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(ShareDestinationCollectionViewCell.self, forCellWithReuseIdentifier: ShareDestinationCollectionViewCell.reuseIdentifier)
        return collectionView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        var snapshot = NSDiffableDataSourceSnapshot<Section, ShareDestination>()
        snapshot.appendSections([.all])
        snapshot.appendItems(shareDestinations)
        dataSource.apply(snapshot, animatingDifferences: false)

        layoutMarginsDidChange()
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        collectionView.contentInset = UIEdgeInsets(top: 0, left: layoutMargins.left, bottom: 0, right: layoutMargins.right)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: ShareDestinationCollectionViewCell.cellHeight)
    }
}

extension ShareCarousel: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let shareDestination = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        share?(shareDestination.shareProvider)
    }
}

// MARK: ShareDestinationCollectionViewCell

extension ShareCarousel {

    private class ShareDestinationCollectionViewCell: UICollectionViewCell {

        private struct Constants {
            static let iconSize: CGFloat = 42
            static let titleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            static let titleNumberOfLines = 2
            static let iconTitleSpacing: CGFloat = 4
            static let margins = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        }

        static let cellHeight = Constants.iconSize + CGFloat(Constants.titleNumberOfLines) * Constants.titleFont.lineHeight + Constants.margins.top + Constants.margins.bottom + Constants.iconTitleSpacing

        static var reuseIdentifier: String {
            return String(describing: self)
        }

        private let iconImageView: UIImageView = {
            let iconImageView = UIImageView()
            iconImageView.clipsToBounds = true
            iconImageView.layer.cornerRadius = 9.0
            return iconImageView
        }()

        private let titleLabel: UILabel = {
            let titleLabel = UILabel()
            titleLabel.font = Constants.titleFont
            titleLabel.numberOfLines = Constants.titleNumberOfLines
            titleLabel.textAlignment = .center
            titleLabel.textColor = .primaryBlackWhite
            return titleLabel
        }()

        override var isHighlighted: Bool {
            didSet {
                let alpha = isHighlighted ? 0.8 : 1.0
                UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { [contentView] in
                    contentView.alpha = alpha
                }
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.preservesSuperviewLayoutMargins = false
            contentView.layoutMargins = Constants.margins

            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(iconImageView)

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(titleLabel)

            NSLayoutConstraint.activate([
                iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                iconImageView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
                iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

                titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Constants.iconTitleSpacing),
                titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        func configure(shareDestination: ShareDestination) {
            iconImageView.image = shareDestination.icon
            titleLabel.text = shareDestination.shareProvider.title
        }
    }
}
