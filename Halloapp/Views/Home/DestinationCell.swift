//
//  DestinationCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class DestinationCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: DestinationCell.self)
    }

    private lazy var homeView: UIView = {
        let imageView = UIImageView(image: Self.homeIcon)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .avatarHomeIcon
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .avatarHomeBg
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        container.isHidden = true

        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()

    private lazy var favoritesView: UIView = {
        let imageView = UIImageView(image: Self.favoritesIcon)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .favoritesBg
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        container.isHidden = true

        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.widthAnchor.constraint(equalToConstant: 32).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        return view
    }()

    private lazy var title: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitle: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private lazy var selectedView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = Self.checkmarkUnchecked
        imageView.tintColor = Self.colorUnchecked
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return imageView
    }()

    fileprivate let seperator: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        homeView.isHidden = true
        favoritesView.isHidden = true
        avatarView.isHidden = true
        subtitle.isHidden = true
        seperator.isHidden = true
    }

    private func setup() {
        layer.cornerRadius = 10
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        layer.masksToBounds = false

        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true

        let labels = UIStackView(arrangedSubviews: [ title, subtitle ])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.distribution = .fill
        labels.spacing = 3

        let hStack = UIStackView(arrangedSubviews: [homeView, favoritesView, avatarView, labels, selectedView])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.distribution = .fill
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 44, left: 0, bottom: 44, right: 0)
        hStack.spacing = 10

        contentView.addSubview(hStack)
        contentView.addSubview(seperator)
        NSLayoutConstraint.activate([
            hStack.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            hStack.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -16),
            hStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            seperator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            seperator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            seperator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            seperator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
    }

    public func configure(title: String, subtitle: String, privacyListType: PrivacyListType, isSelected: Bool, hasNext: Bool) {
        self.title.text = title
        self.subtitle.text = subtitle
        switch privacyListType {
        case .all:
            homeView.isHidden = false
        case .whitelist:
            favoritesView.isHidden = false
        default:
            break
        }
        if privacyListType == .whitelist {
            favoritesView.isHidden = false
        }
        avatarView.isHidden = true
        self.subtitle.isHidden = false
        seperator.isHidden = true
    }

    public func configure(_ group: ChatThread, isSelected: Bool) {
        title.text = group.title
        if let groupID = group.groupID {
            avatarView.configure(groupId: groupID, squareSize: 32, using: MainAppContext.shared.avatarStore)
        }
        homeView.isHidden = true
        favoritesView.isHidden = true
        avatarView.isHidden = false
        self.subtitle.isHidden = true
        configureSelected(isSelected)
        seperator.isHidden = false
    }

    public func configure(_ contact: ABContact, isSelected: Bool) {
        title.text = contact.fullName
        subtitle.isHidden = false
        subtitle.text = contact.phoneNumber
        homeView.isHidden = true
        favoritesView.isHidden = true
        avatarView.isHidden = false
        self.subtitle.isHidden = true

        if let id = contact.userId {
            avatarView.configure(with: id, using: MainAppContext.shared.avatarStore)
        }
        configureSelected(isSelected)
        seperator.isHidden = false
    }

    private func configureSelected(_ isSelected: Bool) {
        selectedView.image = isSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked
        selectedView.tintColor = isSelected ? Self.colorChecked : Self.colorUnchecked
    }

    static var homeIcon: UIImage {
        UIImage(named: "PrivacySettingMyContacts")!.withRenderingMode(.alwaysTemplate)
    }

    static var favoritesIcon: UIImage {
       UIImage(named: "PrivacySettingFavoritesWithBackground")!.withRenderingMode(.alwaysOriginal)
    }

    private static var checkmarkUnchecked: UIImage {
        UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!.withRenderingMode(.alwaysTemplate)
    }

    private static var checkmarkChecked: UIImage {
        UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!.withRenderingMode(.alwaysTemplate)
    }

    private static var colorChecked: UIColor {
        .primaryBlue
    }

    private static var colorUnchecked: UIColor {
        .primaryBlackWhite.withAlphaComponent(0.2)
    }
}

class DestinationPickerHeaderView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: DestinationPickerHeaderView.self)
    }

    var text: String? {
        get {
            titleView.text
        }
        set {
            titleView.text = newValue?.uppercased()
        }
    }

    private lazy var titleView: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .primaryBlackWhite.withAlphaComponent(0.5)

        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleView)
        titleView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        titleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
