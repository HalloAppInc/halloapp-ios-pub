//
//  FeedInviteCarousel.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 2/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class FeedInviteCarouselCell: UICollectionViewCell {

    var inviteContact: ((InviteContact) -> Void)?
    var hideContact: ((InviteContact) -> Void)?
    var openInviteViewController: (() -> Void)?

    var invitedContacts: Set<InviteContact> = Set()

    static let reuseIdentifier = "FeedInviteCarouselCell"

    private enum Section {
        case contacts
    }

    private enum Item: Hashable {
        case contact(InviteContact, Bool)
        case more
    }

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] in
        self?.cellProvider(collectionView: $0, indexPath: $1, item: $2)
    }

    private lazy var collectionView: UICollectionView = {
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

        let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)

        let collectionView = FeedInviteCarouselCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = nil
        collectionView.showsHorizontalScrollIndicator = false

        collectionView.register(FeedInviteCarouselContactCell.self,
                                forCellWithReuseIdentifier: FeedInviteCarouselContactCell.reuseIdentifier)

        return collectionView
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label.withAlphaComponent(0.9)
        titleLabel.text = Localizations.feedInviteCarouselTitle
        return titleLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        collectionView.clipsToBounds = false
        collectionView.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        let bottomAnchor = collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        bottomAnchor.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomAnchor,
        ])

        updateCollectionViewInsets()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func cellProvider(collectionView: UICollectionView,
                              indexPath: IndexPath,
                              item: Item) -> UICollectionViewCell? {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedInviteCarouselContactCell.reuseIdentifier,
                                                      for: indexPath)
        if let cell = cell as? FeedInviteCarouselContactCell {
            switch item {
            case .contact(let contact, let invited):
                cell.configure(with: contact, invited: invited)
            case .more:
                cell.configureForSearch()
            }
            cell.delegate = self
        }
        return cell
    }

    func configure(with contacts: [InviteContact], invitedContacts: Set<InviteContact>, animated: Bool = false) {
        self.invitedContacts = invitedContacts

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.contacts])
        snapshot.appendItems(contacts.map { Item.contact($0, invitedContacts.contains($0)) }, toSection: .contacts)
        snapshot.appendItems([Item.more], toSection: .contacts)

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        updateCollectionViewInsets()
    }

    private func updateCollectionViewInsets() {
        let layoutMargins = contentView.layoutMargins
        collectionView.contentInset = UIEdgeInsets(top: 0, left: layoutMargins.left + 8, bottom: 0, right: layoutMargins.right + 8)
    }
}

extension FeedInviteCarouselCell: FeedInviteCarouselContactCellDelegate {

    fileprivate func feedInviteCarouselContactCellDidInvite(_ cell: FeedInviteCarouselContactCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch item {
        case .contact(let contact, _):
            inviteContact?(contact)
        case .more:
            openInviteViewController?()
        }
    }

    fileprivate func feedInviteCarouselContactCellDidDismiss(_ cell: FeedInviteCarouselContactCell) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch item {
        case .contact(let contact, _):
            hideContact?(contact)
        case .more:
            // no-op
            break
        }
    }
}

private class FeedInviteCarouselCollectionView: UICollectionView {

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: FeedInviteCarouselContactCell.height)
    }
}

private protocol FeedInviteCarouselContactCellDelegate: AnyObject {
    func feedInviteCarouselContactCellDidInvite(_ cell: FeedInviteCarouselContactCell)
    func feedInviteCarouselContactCellDidDismiss(_ cell: FeedInviteCarouselContactCell)
}

private class FeedInviteCarouselContactCell: UICollectionViewCell {

    private struct Constants {
        static let avatarTopSpacing: CGFloat = 22
        static let avatarSize: CGFloat = 36
        static let avatarNameLabelSpacing: CGFloat = 8
        static let nameLabelNumContactsLabelSpacing: CGFloat = 8
        static let numContactsLabelInviteButtonSpacing: CGFloat = 12
        static let inviteButtonBottomSpacing: CGFloat = 16
        static let inviteButtonVerticalPadding: CGFloat = 8
        static let nameLabelFont = UIFont.gothamFont(ofFixedSize: 15, weight: .medium)
        static let numContactsLabelFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let inviteButtonFont = UIFont.systemFont(ofSize: 15, weight: .medium)
    }

    static let reuseIdentifier = "FeedInviteCarouselCell"

    static var height: CGFloat {
        var height: CGFloat = 0
        height += Constants.avatarTopSpacing
        height += Constants.avatarSize
        height += Constants.avatarNameLabelSpacing
        height += Constants.nameLabelFont.lineHeight * 2.0
        height += Constants.nameLabelNumContactsLabelSpacing
        height += Constants.numContactsLabelFont.lineHeight * 2.0
        height += Constants.numContactsLabelInviteButtonSpacing
        height += Constants.inviteButtonVerticalPadding
        height += Constants.inviteButtonFont.lineHeight
        height += Constants.inviteButtonVerticalPadding
        height += Constants.inviteButtonBottomSpacing
        return height
    }

    weak var delegate: FeedInviteCarouselContactCellDelegate?

    private let avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Constants.avatarSize / 2.0
        return avatarView
    }()

    private let searchIconImageView: UIImageView = {
        let searchIconImageView = UIImageView()
        searchIconImageView.backgroundColor = AvatarView.defaultBackgroundColor
        searchIconImageView.contentMode = .center
        searchIconImageView.image = UIImage(systemName: "magnifyingglass")
        searchIconImageView.layer.cornerRadius = Constants.avatarSize / 2.0
        searchIconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        searchIconImageView.tintColor = .avatarDefaultIcon
        return searchIconImageView
    }()

    private let nameLabel: UILabel = {
        let nameLabel = UILabel()
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.font = Constants.nameLabelFont
        nameLabel.textAlignment = .center
        nameLabel.textColor = .label
        nameLabel.minimumScaleFactor = 0.5
        return nameLabel
    }()

    private let numContactsLabel: UILabel = {
        let numContactsLabel = UILabel()
        numContactsLabel.font = Constants.numContactsLabelFont
        numContactsLabel.numberOfLines = 2
        numContactsLabel.textAlignment = .center
        numContactsLabel.textColor = .label.withAlphaComponent(0.5)
        return numContactsLabel
    }()

    private lazy var inviteButtonConfiguration: UIButton.Configuration = {
        var inviteButtonConfiguration = UIButton.Configuration.filled()
        inviteButtonConfiguration.baseBackgroundColor = .primaryBlue
        inviteButtonConfiguration.baseForegroundColor = .white
        inviteButtonConfiguration.cornerStyle = .capsule
        // adjust down for visual alignment
        inviteButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: Constants.inviteButtonVerticalPadding - 1,
                                                                          leading: 16,
                                                                          bottom: Constants.inviteButtonVerticalPadding + 1,
                                                                          trailing: 16)
        return inviteButtonConfiguration
    }()

    private lazy var inviteButtonInvitedConfiguration: UIButton.Configuration = {
        var inviteButtonInvitedConfiguration = inviteButtonConfiguration
        inviteButtonInvitedConfiguration.baseBackgroundColor = .systemGray
        return inviteButtonInvitedConfiguration
    }()

    private lazy var inviteButton: UIButton = {
        let inviteButton = UIButton(type: .system)
        inviteButton.configuration = inviteButtonConfiguration
        inviteButton.titleLabel?.adjustsFontSizeToFitWidth = true
        inviteButton.titleLabel?.font = Constants.inviteButtonFont
        inviteButton.titleLabel?.minimumScaleFactor = 0.5
        return inviteButton
    }()

    private let dismissButton: UIButton = {
        var dismissButtonConfiguration = UIButton.Configuration.plain()
        dismissButtonConfiguration.baseForegroundColor = .label.withAlphaComponent(0.2)
        dismissButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        let dismissButton = UIButton(type: .system)
        dismissButton.configuration = dismissButtonConfiguration
        let dismissButtonImage = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        dismissButton.setImage(dismissButtonImage, for: .normal)
        return dismissButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = UIColor.feedPostBackground
        contentView.layer.borderColor = UIColor.label.cgColor
        contentView.layer.borderWidth = 1.0 / UIScreen.main.scale
        contentView.layer.cornerRadius = 15
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 3)
        contentView.layer.shadowOpacity = 0.08
        contentView.layer.shadowRadius = 5

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        searchIconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchIconImageView)

        nameLabel.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        nameLabel.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        numContactsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(numContactsLabel)

        inviteButton.addTarget(self, action: #selector(inviteButtonTapped), for: .touchUpInside)
        inviteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inviteButton)

        dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dismissButton)

        // Prevent layout breakage when sized at parent's estimated size
        let inviteButtonBottomConstraint = inviteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.inviteButtonBottomSpacing)
        inviteButtonBottomConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: Constants.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: Constants.avatarSize),

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.avatarTopSpacing),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            searchIconImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            searchIconImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            searchIconImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            searchIconImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: Constants.avatarNameLabelSpacing),

            numContactsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            numContactsLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            numContactsLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.nameLabelNumContactsLabelSpacing),

            inviteButton.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            inviteButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            inviteButton.topAnchor.constraint(equalTo: numContactsLabel.bottomAnchor, constant: Constants.numContactsLabelInviteButtonSpacing),
            inviteButtonBottomConstraint,

            dismissButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: InviteContact, invited: Bool) {
        if let userID = contact.userID {
            avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
        } else {
            avatarView.configure(contactIdentfier: contact.identifier, using: MainAppContext.shared.avatarStore)
        }
        avatarView.isHidden = false
        searchIconImageView.isHidden = true
        nameLabel.numberOfLines = 2
        nameLabel.text = contact.fullName
        numContactsLabel.text = contact.friendCount.flatMap { Localizations.contactsOnHalloApp($0) }
        inviteButton.configuration = invited ? inviteButtonInvitedConfiguration : inviteButtonConfiguration
        // Prevent title fade animation
        UIView.performWithoutAnimation {
            inviteButton.setTitle(Localizations.buttonInvite, for: .normal)
            inviteButton.layoutIfNeeded()
        }
        dismissButton.isHidden = false
    }

    func configureForSearch() {
        avatarView.isHidden = true
        searchIconImageView.isHidden = false
        nameLabel.numberOfLines = 0
        nameLabel.text = Localizations.feedInviteCarouselSearchPrompt
        numContactsLabel.text = nil
        inviteButton.configuration = inviteButtonConfiguration
        // Prevent title fade animation
        UIView.performWithoutAnimation {
            inviteButton.setTitle(Localizations.labelSearch, for: .normal)
            inviteButton.layoutIfNeeded()
        }
        dismissButton.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.shadowPath = UIBezierPath(roundedRect: contentView.bounds,
                                                    cornerRadius: contentView.layer.cornerRadius).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderColor()
        }
    }

    private func updateBorderColor() {
        contentView.layer.borderColor = UIColor.label.withAlphaComponent(0.18).resolvedColor(with: traitCollection).cgColor
    }

    @objc private func inviteButtonTapped() {
        delegate?.feedInviteCarouselContactCellDidInvite(self)
    }

    @objc private func dismissButtonTapped() {
        delegate?.feedInviteCarouselContactCellDidDismiss(self)
    }
}

extension Localizations {

    static var feedInviteCarouselTitle: String {
        return NSLocalizedString("feedInviteCarousel.title",
                                 value: "HalloApp is fun with friends & family",
                                 comment: "Title for section of contacts to invite in feed")
    }

    static var feedInviteCarouselSearchPrompt: String {
        return NSLocalizedString("feedInviteCarousel.searchPrompt",
                                 value: "Search for more friends and family",
                                 comment: "Text for 'more' cell prompting users to open the invite screen")
    }
}
