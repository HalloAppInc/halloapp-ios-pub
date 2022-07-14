//
//  InsetCollectionView.swift
//  HalloApp
//
//  Created by Tanveer on 4/20/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine

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
        register(LabeledCollectionViewCell.self, forCellWithReuseIdentifier: LabeledCollectionViewCell.reuseIdentifier)
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
    static func defaultLayoutConfiguration() -> UICollectionViewCompositionalLayoutConfiguration {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20
        
        return config
    }
    
    static func defaultLayout() -> UICollectionViewCompositionalLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = Self.insets
        
        return UICollectionViewCompositionalLayout(section: section)
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
        case .label(_):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: LabeledCollectionViewCell.reuseIdentifier, for: indexPath)
            (cell as? LabeledCollectionViewCell)?.configure(with: item, configuration: configuration)
        }

        let isFirstItem = indexPath.row == 0
        let isLastItem = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1
        let section: Section?
        if #available(iOS 15, *) {
            section = data.sectionIdentifier(for: indexPath.section)
        } else {
            section = data.snapshot().sectionIdentifiers[indexPath.section]
        }

        if let cell = cell as? StandardCollectionViewCell, let options = section?.roundedCorners {
            finalizeStyle(for: cell, isFirstItem: isFirstItem, isLastItem: isLastItem, options: options)
        }

        return cell
    }

    private func finalizeStyle(for cell: StandardCollectionViewCell, isFirstItem: Bool, isLastItem: Bool, options: Section.RoundCorners) {
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

        let disclosure = configuration.showDisclosureIndicator ? UIImage(systemName: "chevron.forward")?.withRenderingMode(.alwaysTemplate) : nil
        cell.disclosureView.image = disclosure

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
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .regular)
        
        return label
    }()
    
    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        
        return label
    }()
    
    fileprivate lazy var titleVStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fillProportionally
        stackView.axis = .vertical
        
        return stackView
    }()
    
    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        
        return imageView
    }()

    /// Subclasses can add an accessory view to this view; the constraints should be taken care of.
    fileprivate let accessoryContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    fileprivate let disclosureView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium, scale: .default)
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .center
        return imageView
    }()
    
    fileprivate let separator: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleVStackLeadingConstraint = titleVStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(imageView)
        contentView.addSubview(titleVStack)
        contentView.addSubview(separator)
        contentView.addSubview(accessoryContainer)
        contentView.addSubview(disclosureView)
        
        contentView.layoutMargins = UIEdgeInsets(top: 13, left: 15, bottom: 13, right: 15)
        let minimizeHeight = contentView.heightAnchor.constraint(equalToConstant: 0)
        minimizeHeight.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            imageView.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            titleVStackLeadingConstraint,
            titleVStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleVStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            titleVStack.trailingAnchor.constraint(lessThanOrEqualTo: accessoryContainer.leadingAnchor, constant: 5),

            accessoryContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accessoryContainer.trailingAnchor.constraint(equalTo: disclosureView.leadingAnchor, constant: 0),

            disclosureView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            disclosureView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            disclosureView.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            minimizeHeight,
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("ProfileCollectionViewCell coder init not implemented...")
    }
    
    override func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        super.configure(with: item, configuration: configuration)

        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        subtitleLabel.isHidden = (item.subtitle == nil)
        imageView.image = item.icon
        titleVStackLeadingConstraint.constant = item.icon == nil ? 0 : 33

        if configuration.showDisclosureIndicator {
            disclosureView.image = UIImage(systemName: "chevron.forward")?.withRenderingMode(.alwaysTemplate)
        }

        if configuration.showSeparators {
            separator.isHidden = false
        }
    }
}

/// A cell that has a `UISwitch` instance at its trailing edge.
fileprivate class ToggleCollectionViewCell: StandardCollectionViewCell {
    override class var reuseIdentifier: String {
        "toggleCell"
    }

    private lazy var toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        return toggle
    }()

    private var onChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        accessoryContainer.addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
            toggle.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor),
            toggle.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
            toggle.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
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

        // toggle cell doesn't show the disclosure that may have been configured by super class
        disclosureView.image = nil
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

/// A cell that has a second label at its trailing edge.
fileprivate class LabeledCollectionViewCell: StandardCollectionViewCell {
    override class var reuseIdentifier: String {
        "labledCell"
    }

    private let accessoryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var accessoryLabelTrailing = accessoryLabel.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)

        accessoryContainer.addSubview(accessoryLabel)
        NSLayoutConstraint.activate([
            accessoryLabel.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
            accessoryLabelTrailing,
            accessoryLabel.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
            accessoryLabel.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("LabeledCollectionViewCell coder init not implemented...")
    }

    override func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {
        super.configure(with: item, configuration: configuration)
        guard case let .label(text) = item.style else {
            return
        }

        accessoryLabel.text = text
        let constant: CGFloat = disclosureView.image == nil ? 0 : -10
        accessoryLabelTrailing.constant = constant
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryLabel.text = nil
    }
}

// MARK: - InsetCollectionViewCell implementation

/// The base cell class. We use this for rounding corners and applying the shadow.
fileprivate class InsetCollectionViewCell: UICollectionViewCell {
    /// - note: We remove the shadow in dark mode since the cell has some transparency.
    private lazy var shadowColor: UIColor = {
        return UIColor() { traits in
            if case .dark = traits.userInterfaceStyle {
                return UIColor.black.withAlphaComponent(0)
            } else {
                return UIColor.black.withAlphaComponent(0.1)
            }
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        
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
        
        layer.shadowColor = shadowColor.cgColor
        layer.shadowRadius = 0.6
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }
    
    required init?(coder: NSCoder) {
        fatalError("InsetCollectionViewCell coder init not implemented...")
    }
    
    func configure(with item: InsetCollectionView.Item, configuration: InsetCollectionView.Configuration) {

    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection != previousTraitCollection {
            layer.shadowColor = shadowColor.cgColor
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
            /// Creates a cell with a secondary label at the trailing edge.
            case label(string: String)
        }
        
        let identifier: AnyHashable
        let title: String
        let subtitle: String?
        let icon: UIImage?
        let style: Style
        let action: (() -> Void)?

        init(identifier: AnyHashable = UUID(), title: String = "", subtitle: String? = nil, icon: UIImage? = nil, style: Style = .standard, action: (() -> Void)? = nil) {
            self.identifier = identifier
            self.title = title
            self.subtitle = subtitle
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
