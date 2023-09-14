//
//  InsetCollectionView.swift
//  HalloApp
//
//  Created by Tanveer on 4/20/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon

protocol InsetCollectionViewDelegate: UICollectionViewDelegate {
    var collectionView: InsetCollectionView { get }
    func insetCollectionView(didSelectItemAt indexPath: IndexPath)
}

// MARK: - default delegate implementations

extension InsetCollectionViewDelegate {
    /**
     A default implementation for `collectionView(_:didSelectItemAt:)` provided by ``InsetCollectionView``.

     > Important: Due to restrictions on protocol extensions, aside from making the delegate conform to ``InsetCollectionViewDelegate``, you have to manually add the following code to adopt the default implementation.

     ```swift
     func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
         insetCollectionView(didSelectItemAt: indexPath)
     }
     ```
     */
    func insetCollectionView(didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? InsetCollectionView.Item else {
            return
        }

        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }
}

extension InsetCollectionView {
    static var cornerRadius: CGFloat {
        10
    }

    static var insets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}

/// A collection view with an appearance similar to that of an inset-grouped table view.
class InsetCollectionView: UICollectionView {
    typealias Configuration = (showSeparators: Bool, showDisclosureIndicator: Bool)
    private var configuration: Configuration = (true, true)

    private(set) lazy var data: UICollectionViewDiffableDataSource<Section, AnyHashable> = {
        let dataSource = UICollectionViewDiffableDataSource<Section, AnyHashable>(collectionView: self, cellProvider: cellProvider)

        return dataSource
    }()

    init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewLayout())

        dataSource = data
        register(StandardCollectionViewCell.self, forCellWithReuseIdentifier: StandardCollectionViewCell.reuseIdentifier)
        register(ToggleCollectionViewCell.self, forCellWithReuseIdentifier: ToggleCollectionViewCell.reuseIdentifier)
        register(UserCollectionViewCell.self, forCellWithReuseIdentifier: UserCollectionViewCell.reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("InsetCollectionView coder init not implemented...")
    }

    func apply(_ collection: Collection) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AnyHashable>()
        snapshot.appendSections(collection.sections)

        for section in collection.sections {
            snapshot.appendItems(section.items, toSection: section)
        }

        configuration = (collection.showSeparators, collection.showDisclosureIndicator)
        data.apply(snapshot)
    }
}

// MARK: - static methods

extension InsetCollectionView {

    static var defaultLayoutConfiguration: UICollectionViewCompositionalLayoutConfiguration {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        return config
    }

    static var defaultLayoutSection: NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)

        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = Self.insets

        return section
    }

    static var defaultLayout: UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout(section: defaultLayoutSection)
    }

    private func cellProvider(_ collectionView: UICollectionView, _ indexPath: IndexPath, _ item: AnyHashable) -> UICollectionViewCell {
        guard let item = item as? Item else {
            return UICollectionViewCell()
        }

        let cell: UICollectionViewCell
        switch item.style {
        case .standard:
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: StandardCollectionViewCell.reuseIdentifier, for: indexPath)
            (cell as? StandardCollectionViewCell)?.configure(with: item, configuration: configuration)
        case .toggle(_, _, _):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToggleCollectionViewCell.reuseIdentifier, for: indexPath)
            (cell as? ToggleCollectionViewCell)?.configure(with: item, configuration: configuration)
        case .user(_, _):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserCollectionViewCell.reuseIdentifier, for: indexPath)
            (cell as? UserCollectionViewCell)?.configure(with: item, configuration: configuration)
        }

        let isFirstItem = indexPath.row == 0
        let isLastItem = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1
        let section = data.sectionIdentifier(for: indexPath.section)

        if let cell = cell as? InsetCollectionViewCell, let options = section?.roundedCorners {
            finalizeStyle(for: cell, isFirstItem: isFirstItem, isLastItem: isLastItem, options: options)
        }

        return cell
    }

    private func finalizeStyle(for cell: InsetCollectionViewCell, isFirstItem: Bool, isLastItem: Bool, options: Section.RoundCorners) {
        var maskedCorners = CACornerMask()
        let roundTopCorners = options == .top || options == .all
        let roundBottomCorners = options == .bottom || options == .all

        if isFirstItem, roundTopCorners {
            maskedCorners.update(with: [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }

        if isLastItem, roundBottomCorners {
            maskedCorners.update(with: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
            cell.layer.shadowOpacity = 1
        } else {
            cell.layer.shadowOpacity = 0
        }

        cell.selectedBackgroundView?.layer.maskedCorners = maskedCorners
        cell.backgroundView?.layer.maskedCorners = maskedCorners
        cell.contentView.layer.maskedCorners = maskedCorners

        if configuration.showSeparators {
            cell.separator.isHidden = isLastItem
        }
    }
}

// MARK: - StandardCollectionViewCell implementation

fileprivate class StandardCollectionViewCell: InsetCollectionViewCell {
    class var reuseIdentifier: String {
        "standardCell"
    }

    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        return imageView
    }()

    fileprivate let disclosureImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium, scale: .default)
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .center
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        leadingViewContainer.addSubview(imageView)
        trailingViewContainer.addSubview(disclosureImageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingViewContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: leadingViewContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: leadingViewContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: leadingViewContainer.bottomAnchor),

            disclosureImageView.leadingAnchor.constraint(equalTo: trailingViewContainer.leadingAnchor),
            disclosureImageView.trailingAnchor.constraint(equalTo: trailingViewContainer.trailingAnchor),
            disclosureImageView.topAnchor.constraint(equalTo: trailingViewContainer.topAnchor),
            disclosureImageView.bottomAnchor.constraint(equalTo: trailingViewContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ProfileCollectionViewCell coder init not implemented...")
    }

    override func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        super.configure(with: item, configuration: configuration)

        imageView.image = item.icon
        titleStackLeadingConstraint.constant = item.icon == nil ? 0 : 33

        if configuration.showDisclosureIndicator {
            disclosureImageView.image = UIImage(systemName: "chevron.forward")?.withRenderingMode(.alwaysTemplate)
        }
    }
}

// MARK: - UserCollectionViewCell implementation

///
fileprivate class UserCollectionViewCell: InsetCollectionViewCell {

    class var reuseIdentifier: String {
        "userCell"
    }

    private let avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .systemBlue
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let existingMargins = contentView.layoutMargins
        contentView.layoutMargins = UIEdgeInsets(top: 8, left: existingMargins.left + 5, bottom: 8, right: existingMargins.right + 5)

        leadingViewContainer.addSubview(avatarView)
        trailingViewContainer.addSubview(button)

        let diameter: CGFloat = 35
        let titleDistance: CGFloat = diameter + 3

        titleStackLeadingConstraint.constant = titleDistance
        let heightConstraint = avatarView.heightAnchor.constraint(equalToConstant: diameter)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingViewContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: leadingViewContainer.trailingAnchor),
            avatarView.topAnchor.constraint(equalTo: leadingViewContainer.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: leadingViewContainer.bottomAnchor),

            heightConstraint,
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor),

            button.leadingAnchor.constraint(equalTo: trailingViewContainer.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingViewContainer.trailingAnchor),
            button.topAnchor.constraint(equalTo: trailingViewContainer.topAnchor),
            button.bottomAnchor.constraint(equalTo: trailingViewContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("UserCollectionViewCell coder init not implemented...")
    }

    override func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        guard case let .user(id, menu) = item.style else {
            return
        }

        let contactStore = MainAppContext.shared.contactStore
        let name = contactStore.fullName(for: id, in: contactStore.viewContext)
        var number = contactStore.normalizedPhoneNumber(for: id, using: contactStore.viewContext)
        if let normalized = number, let parsed = try? AppContextCommon.shared.phoneNumberFormatter.parse(normalized) {
           number = AppContextCommon.shared.phoneNumberFormatter.format(parsed, toType: .international)
        }

        let item = InsetCollectionView.Item(title: name,
                                         subtitle: number,
                                    accessoryText: item.accessoryText)
        super.configure(with: item, configuration: configuration)

        avatarView.configure(with: id, using: MainAppContext.shared.avatarStore)
        button.configureWithMenu(menu)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }
}

// MARK: - ToggleCollectionViewCell implementation

/// A cell that has a `UISwitch` instance at its trailing edge.
fileprivate class ToggleCollectionViewCell: InsetCollectionViewCell {

    class var reuseIdentifier: String {
        "toggleCell"
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        return imageView
    }()

    private lazy var toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        return toggle
    }()

    private var onChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let existingMargins = contentView.layoutMargins
        contentView.layoutMargins = UIEdgeInsets(top: 5, left: existingMargins.left, bottom: 5, right: existingMargins.right)

        trailingViewContainer.addSubview(toggle)

        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: trailingViewContainer.leadingAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingViewContainer.trailingAnchor),
            toggle.topAnchor.constraint(equalTo: trailingViewContainer.topAnchor),
            toggle.bottomAnchor.constraint(equalTo: trailingViewContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ToggleCollectionViewCell coder init not implemented...")
    }

    override func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        super.configure(with: item, configuration: configuration)
        guard case let .toggle(initial, enabled, onChanged) = item.style else {
            return
        }

        toggle.isEnabled = enabled
        toggle.isOn = initial
        self.onChanged = onChanged

        imageView.image = item.icon
        titleStackLeadingConstraint.constant = item.icon == nil ? 0 : 33
    }

    @objc
    private func toggled(_ sender: UISwitch) {
        onChanged?(sender.isOn)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChanged = nil
    }
}

// MARK: - InsetCollectionViewCell implementation

/// The base cell class. We use this for rounding corners and applying the shadow.
fileprivate class InsetCollectionViewCell: UICollectionViewCell {
    /// - note: We remove the shadow in dark mode since the cell has some transparency.
    private static var shadowColor: UIColor {
        UIColor() { traits in
            if case .dark = traits.userInterfaceStyle {
                return UIColor.black.withAlphaComponent(0)
            } else {
                return UIColor.black.withAlphaComponent(0.1)
            }
        }
    }

    private lazy var titleStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fillProportionally
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()

    private(set) lazy var titleStackLeadingConstraint: NSLayoutConstraint = {
        let constraint = titleStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        return constraint
    }()

    let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    let leadingViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let accessoryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.font = .systemFont(forTextStyle: .body)
        return label
    }()

    let trailingViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = .separatorGray
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layoutMargins = UIEdgeInsets(top: 12, left: 15, bottom: 12, right: 15)

        backgroundView = UIView()
        backgroundView?.backgroundColor = .feedPostBackground
        backgroundView?.layer.masksToBounds = true
        backgroundView?.layer.cornerRadius = 10
        selectedBackgroundView = UIView()
        selectedBackgroundView?.layer.masksToBounds = true
        selectedBackgroundView?.backgroundColor = .secondarySystemFill

        let radius = InsetCollectionView.cornerRadius
        contentView.layer.masksToBounds = true
        contentView.layer.cornerCurve = .continuous
        contentView.layer.cornerRadius = radius

        layer.cornerCurve = .continuous
        layer.cornerRadius = radius
        layer.masksToBounds = false

        selectedBackgroundView?.layer.cornerRadius = radius

        layer.shadowColor = Self.shadowColor.cgColor
        layer.shadowRadius = 0.6
        layer.shadowOffset = CGSize(width: 0, height: 1)

        contentView.addSubview(leadingViewContainer)
        contentView.addSubview(titleStack)
        contentView.addSubview(accessoryLabel)
        contentView.addSubview(trailingViewContainer)
        contentView.addSubview(separator)

        let minimalPriority = UILayoutPriority(1)
        let minimizeHeight = contentView.heightAnchor.constraint(equalToConstant: 0)
        minimizeHeight.priority = minimalPriority

        let minimizeContainers = [leadingViewContainer, trailingViewContainer]
            .flatMap { [$0.widthAnchor.constraint(equalToConstant: 0), $0.heightAnchor.constraint(equalToConstant: 0)] }
        minimizeContainers.forEach { $0.priority = minimalPriority }

        NSLayoutConstraint.activate([
            leadingViewContainer.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            leadingViewContainer.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 10),
            leadingViewContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            titleStackLeadingConstraint,
            titleStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: accessoryLabel.leadingAnchor, constant: -5),

            trailingViewContainer.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            trailingViewContainer.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingViewContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            accessoryLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            accessoryLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accessoryLabel.trailingAnchor.constraint(equalTo: trailingViewContainer.leadingAnchor, constant: -10),

            separator.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            minimizeHeight,
        ] + minimizeContainers)
    }

    required init?(coder: NSCoder) {
        fatalError("InsetCollectionViewCell coder init not implemented...")
    }

    func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        accessoryLabel.text = item.accessoryText

        subtitleLabel.isHidden = item.subtitle == nil
        separator.isHidden = !configuration.showSeparators
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection != previousTraitCollection {
            layer.shadowColor = Self.shadowColor.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0),
                                       cornerRadius: InsetCollectionView.cornerRadius).cgPath
    }
}

// MARK: - result builder stuff

fileprivate protocol Modifier {
    func modify(_ block: (inout Self) -> Void) -> Self
}

extension Modifier {
    func modify(_ block: (inout Self) -> Void) -> Self {
        var copy = self
        block(&copy)
        return copy
    }
}

extension InsetCollectionView {
    struct Collection: Modifier {
        private(set) var showDisclosureIndicator = false
        private(set) var showSeparators = false
        let sections: [Section]

        init(@CollectionBuilder _ builder: () -> [Section]) {
            sections = builder()
        }

        func separators() -> Self {
            modify { $0.showSeparators = true }
        }

        func disclosure() -> Self {
            modify { $0.showDisclosureIndicator = true }
        }
    }

    struct Section: Hashable, Modifier {
        enum RoundCorners { case top, bottom, all}

        let identifier: AnyHashable
        let items: [Item]
        private(set) var roundedCorners: RoundCorners = .all

        init(identifier: AnyHashable = UUID(), @SectionBuilder _ builder: () -> [Item]) {
            self.identifier = identifier
            items = builder()
        }

        func rounding(corners: RoundCorners) -> Self {
            modify { $0.roundedCorners = corners }
        }
    }

    struct Item: Hashable {
        enum Style {
            case standard
            /// Creates a cell with a `UISwitch`.
            case toggle(initial: Bool, isEnabled: Bool = true, onChanged: (Bool) -> Void)
            /// Creates a cell for a given user with a customizable menu.
            case user(id: UserID, menu: () -> HAMenu)
        }

        let identifier: AnyHashable

        let icon: UIImage?
        let title: String
        let subtitle: String?
        let accessoryText: String?

        let style: Style
        let action: (() -> Void)?

        init(identifier: AnyHashable = UUID(),
             title: String = "",
             subtitle: String? = nil,
             accessoryText: String? = nil,
             icon: UIImage? = nil,
             style: Style = .standard,
             action: (() -> Void)? = nil) {

            self.identifier = identifier
            self.title = title
            self.subtitle = subtitle
            self.accessoryText = accessoryText
            self.icon = icon
            self.style = style
            self.action = action
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            return lhs.identifier == rhs.identifier
        }

        func hash(into hasher: inout Hasher) {
            identifier.hash(into: &hasher)
        }
    }

    @resultBuilder
    struct CollectionBuilder {
        static func buildExpression(_ expression: Section) -> [Section] {
            return [expression]
        }

        static func buildBlock(_ components: [Section]...) -> [Section] {
            return Array(components.joined())
        }

        static func buildArray(_ components: [[Section]]) -> [Section] {
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

        static func buildArray(_ components: [[Item]]) -> [Item] {
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
}
