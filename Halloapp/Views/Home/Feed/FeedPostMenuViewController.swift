//
//  FeedPostMenuViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreCommon
import UIKit

class FeedPostMenuViewController: BottomSheetViewController {

    struct Menu {
        let sections: [Section]

        init(@MenuBuilder _ builder: () -> [Section]) {
            sections = builder()
        }
    }

    struct Section: Hashable {

        fileprivate enum SectionType: Hashable {
            case description(Description), actions([Item]), postPreview(FeedPostPreview)
        }

        fileprivate let type: SectionType

        init(@SectionBuilder _ builder: () -> [Item]) {
            type = .actions(builder())
        }

        init(description: String, icon: UIImage? = nil) {
            type = .description(Description(description: description, icon: icon))
        }

        init(postPreview: FeedPostPreview) {
            type = .postPreview(postPreview)
        }

        var items: [AnyHashable] {
            switch type {
            case .description(let description):
                return [description]
            case .actions(let items):
                return items
            case .postPreview(let feedPostPreview):
                return [feedPostPreview]
            }
        }
    }

    struct Item: Hashable {

        enum Style {
            case standard, destructive
        }

        private let uuid = UUID()
        let style: Style
        let icon: UIImage?
        let title: String
        let action: ((Item) -> Void)?

        init(style: Style, icon: UIImage? = nil, title: String, action: ((Item) -> Void)? = nil) {
            self.style = style
            self.icon = icon
            self.title = title
            self.action = action
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            return lhs.uuid == rhs.uuid
        }

        func hash(into hasher: inout Hasher) {
            uuid.hash(into: &hasher)
        }
    }

    struct FeedPostPreview: Hashable {
        let image: UIImage?
        let title: String?
        let subtitle: String?
    }

    struct Description: Hashable {
        let description: String
        let icon: UIImage?
    }

    @resultBuilder
    struct MenuBuilder {

        static func buildExpression(_ expression: Section) -> [Section] {
            return [expression]
        }

        static func buildBlock(_ components: [Section]...) -> [Section] {
            return Array(components.joined())
        }

        static func buildEither(first component: [Section]) -> [Section] {
            return component
        }

        static func buildEither(second component: [Section]) -> [Section] {
            return component
        }

        static func buildOptional(_ component: [Section]?) -> [Section] {
            return component ?? []
        }
    }

    @resultBuilder
    struct SectionBuilder {

        static func buildExpression(_ expression: Item) -> [Item] {
            return [expression]
        }

        static func buildBlock(_ components: [Item]...) -> [Item] {
            return Array(components.joined())
        }

        static func buildEither(first component: [Item]) -> [Item] {
            return component
        }

        static func buildEither(second component: [Item]) -> [Item] {
            return component
        }

        static func buildOptional(_ component: [Item]?) -> [Item] {
            return component ?? []
        }
    }

    private struct ReuseIdentifier {
        static let cell = "cell"
        static let descriptionCell = "description"
        static let postPreviewCell = "postPreview"
        static let footer = "footer"
    }

    private struct ElementKind {
        static let footer = "footer"
    }

    private lazy var collectionView: UICollectionView = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 12
        configuration.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                          heightDimension: .estimated(44)),
                                                        elementKind: ElementKind.footer,
                                                        alignment: .bottom),
        ]

        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)

        let collectionView = FeedPostMenuCollectionView(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)),
                                                        collectionViewLayout: layout)
        collectionView.backgroundColor = nil
        collectionView.isScrollEnabled = false
        collectionView.register(FeedPostMenuCell.self, forCellWithReuseIdentifier: ReuseIdentifier.cell)
        collectionView.register(FeedPostMenuDescriptionCell.self, forCellWithReuseIdentifier: ReuseIdentifier.descriptionCell)
        collectionView.register(FeedPostMenuPostPreviewCell.self, forCellWithReuseIdentifier: ReuseIdentifier.postPreviewCell)
        collectionView.register(FeedPostMenuFooter.self,
                                forSupplementaryViewOfKind: ElementKind.footer,
                                withReuseIdentifier: ReuseIdentifier.footer)
        return collectionView
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, AnyHashable> = {
        let dataSource = UICollectionViewDiffableDataSource<Section, AnyHashable>(collectionView: collectionView, cellProvider: cellProvider)
        dataSource.supplementaryViewProvider = supplementaryViewProvider
        return dataSource
    }()

    var menu: Menu = Menu({}) {
        didSet {
            updateMenu()
        }
    }

    convenience init(menu: Menu) {
        self.init(nibName: nil, bundle: nil)
        self.menu = menu
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        collectionView.constrain(to: view)

        updateMenu()
    }

    private func updateMenu() {
        guard isViewLoaded else {
            return
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, AnyHashable>()
        snapshot.appendSections(menu.sections)
        menu.sections.forEach { section in
            snapshot.appendItems(section.items, toSection: section)
        }
        dataSource.apply(snapshot)
    }

    private func cellProvider(_ collectionView: UICollectionView,
                              _ indexPath: IndexPath,
                              _ item: AnyHashable) -> UICollectionViewCell {
        switch item {
        case let item as Item:
            let isInitialItem = indexPath.item == 0
            let isFinalItem = indexPath.item == collectionView.numberOfItems(inSection: indexPath.section) - 1
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReuseIdentifier.cell, for: indexPath)
            (cell as? FeedPostMenuCell)?.configure(with: item, isInitialItem: isInitialItem, isFinalItem: isFinalItem)
            return cell
        case let item as Description:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReuseIdentifier.descriptionCell, for: indexPath)
            (cell as? FeedPostMenuDescriptionCell)?.configure(with: item)
            return cell
        case let item as FeedPostPreview:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReuseIdentifier.postPreviewCell, for: indexPath)
            (cell as? FeedPostMenuPostPreviewCell)?.configure(with: item)
            return cell
        default:
            fatalError()
        }
    }

    private func supplementaryViewProvider(_ collectionView: UICollectionView,
                                           _ elementKind: String,
                                           _ indexPath: IndexPath) -> UICollectionReusableView {
        switch elementKind {
        case ElementKind.footer:
            let footer = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                         withReuseIdentifier: ReuseIdentifier.footer,
                                                                         for: indexPath)
            (footer as? FeedPostMenuFooter)?.cancelAction = dismissAnimated
            return footer
        default:
            fatalError()
        }
    }

    private func dismissAnimated() {
        dismiss(animated: true)
    }
}

extension FeedPostMenuViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) as? Item else {
            DDLogWarn("FeedPostMenuViewController/Unable to find item")
            return
        }
        collectionView.deselectItem(at: indexPath, animated: true)
        dismiss(animated: true) {
            item.action?(item)
        }
    }
}

private class FeedPostMenuCollectionView: UICollectionView {

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != intrinsicContentSize {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        let contentSize = collectionViewLayout.collectionViewContentSize
        let insets = safeAreaInsets
        return CGSize(width: contentSize.width + insets.left + insets.right,
                      height: contentSize.height + insets.top + insets.bottom)
    }
}

private class FeedPostMenuFooter: UICollectionReusableView {

    var cancelAction: (() -> Void)?

    private let cancelButton: UIButton = {
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle(Localizations.buttonCancel, for: .normal)
        cancelButton.setTitleColor(.systemBlue, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        return cancelButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func cancelButtonTapped() {
        cancelAction?()
    }
}

private class FeedPostMenuDescriptionCell: UICollectionViewCell {

    private let iconImageView: UIImageView = {
        let iconImageView = UIImageView()
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconImageView.tintColor = .label.withAlphaComponent(0.4)
        return iconImageView
    }()

    private let descriptionLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label.withAlphaComponent(0.4)
        return titleLabel
    }()

    private lazy var descriptionLabelLeadingConstraint: NSLayoutConstraint = {
        descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconImageView)

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)

        let heightMinimizationConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)
        heightMinimizationConstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            iconImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            descriptionLabelLeadingConstraint,
            descriptionLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with description: FeedPostMenuViewController.Description) {
        descriptionLabel.text = description.description
        let hasIcon = (description.icon != nil)
        descriptionLabel.textAlignment = hasIcon ? .natural : .center
        descriptionLabelLeadingConstraint.constant = hasIcon ? 50 : 0
        iconImageView.image = description.icon
    }
}

private class FeedPostMenuCell: UICollectionViewCell {

    private let iconImageView: UIImageView = {
        let iconImageView = UIImageView()
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        return iconImageView
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        return titleLabel
    }()

    private let separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = .label.withAlphaComponent(0.2)
        return separator
    }()

    private lazy var titleLabelLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                                                       constant: 10)

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = 10

        let backgroundView = UIView()
        backgroundView.backgroundColor = .feedPostMenuCellBackground
        self.backgroundView = backgroundView

        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .systemGray5
        self.selectedBackgroundView = selectedBackgroundView

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        let minimizeHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)
        minimizeHeightConstraint.priority = UILayoutPriority(1)

        updateTitleLabelLeadingConstraint()

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 50),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            minimizeHeightConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with menuItem: FeedPostMenuViewController.Item, isInitialItem: Bool, isFinalItem: Bool) {
        iconImageView.image = menuItem.icon?.withRenderingMode(.alwaysTemplate)
        titleLabel.text = menuItem.title

        var maskedCorners: CACornerMask = []
        if isInitialItem {
            maskedCorners.update(with: [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }
        if isFinalItem {
            maskedCorners.update(with: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        layer.maskedCorners = maskedCorners
        separator.isHidden = isFinalItem

        updateTitleLabelLeadingConstraint()

        let tintColor: UIColor
        switch menuItem.style {
        case .standard:
            tintColor = .systemBlue
        case .destructive:
            tintColor = .systemRed
        }

        iconImageView.tintColor = tintColor
        titleLabel.textColor = tintColor
    }

    private func updateTitleLabelLeadingConstraint() {
        titleLabelLeadingConstraint.priority = iconImageView.image == nil ? .defaultHigh : UILayoutPriority(1)
    }
}

private class FeedPostMenuPostPreviewCell: UICollectionViewCell {

    private let imageView: UIImageView = {
        class FeedPostMenuPostPreviewCellImageView: UIImageView {
            override var intrinsicContentSize: CGSize {
                return image == nil ? .zero : CGSize(width: 75, height: 75)
            }
        }
        let imageView = FeedPostMenuPostPreviewCellImageView()
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 13
        return imageView
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .label
        return titleLabel
    }()

    private let subtitleLabel: UILabel = {
        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = .label.withAlphaComponent(0.7)
        return subtitleLabel
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let textStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 2

        let contentStackView = UIStackView(arrangedSubviews: [imageView, textStackView])
        contentStackView.alignment = .top
        contentStackView.axis = .horizontal
        contentStackView.spacing = 12
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -2),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func configure(with feedPostPreview: FeedPostMenuViewController.FeedPostPreview) {
        imageView.image = feedPostPreview.image
        imageView.isHidden = (feedPostPreview.image == nil)
        titleLabel.text = feedPostPreview.title
        titleLabel.isHidden = feedPostPreview.title?.isEmpty ?? true
        subtitleLabel.text = feedPostPreview.subtitle
        subtitleLabel.isHidden = feedPostPreview.subtitle?.isEmpty ?? true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
