//
//  ContactSelectionViewController.swift
//  HalloApp
//
//  Created by Garrett on 6/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

let SelectableContactReuse = "SelectableContactReuse"

final class ContactSelectionViewController: UIViewController {
    static let rowHeight = ContactSelectionView.forSizing.systemLayoutSizeFitting(CGSize(width: UIScreen.main.bounds.width - CGFloat(16), height: 0)).height
    var sectionIndexes: [String] = []
    enum Style {
        case `default`, destructive, all
    }
    var privacyListType: PrivacyListType

    var showOnlySelectedContacts = false {
        didSet {
            editSelectionRow.isHidden = isEditLinkHidden()
            header = getGlobalHeader()
            collectionView.reloadData()
        }
    }
    private lazy var editSelectionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = true
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemBlue
        label.text = getEditLabel()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.didTapEdit(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return label
    }()

    private lazy var editSelectionRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let hStack = UIStackView(arrangedSubviews: [spacer, editSelectionLabel])
        hStack.axis = .horizontal
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        hStack.isLayoutMarginsRelativeArrangement = true
        return hStack
    }()

    @objc func didTapEdit(_ sender: UITapGestureRecognizer) {
        showOnlySelectedContacts = false
        updateSearchResultsController(showOnlySelectedContacts: showOnlySelectedContacts)
        dataSource.apply(makeDataSnapshot(searchString: nil))
    }
    
    private func updateSearchResultsController(showOnlySelectedContacts: Bool) {
        let searchResultsController = searchController?.searchResultsController as? ContactSelectionViewController
        searchResultsController?.showOnlySelectedContacts = showOnlySelectedContacts
    }

    init(
        manager: ContactSelectionManager,
        title: String? = nil,
        header: String? = nil,
        showSearch: Bool = true,
        style: Style = .default,
        privacyListType: PrivacyListType,
        saveAction: ((ContactSelectionViewController, Set<UserID>) -> Void)? = nil,
        dismissAction: (() -> Void)? = nil)
    {
        searchController = {
            guard showSearch else { return nil }
            let searchResultsController = ContactSelectionViewController(manager: manager, header: header, showSearch: false, style: style, privacyListType: privacyListType, dismissAction: nil)
            let searchController = UISearchController(searchResultsController: searchResultsController)
            searchController.searchResultsUpdater = searchResultsController
            searchController.searchBar.showsCancelButton = false
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.tintColor = .systemBlue
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.hidesNavigationBarDuringPresentation = false
            searchController.definesPresentationContext = true

            // Set the background color we want...
            searchController.searchBar.searchTextField.backgroundColor = .searchBarBg
            // ... then work around the weird extra background layer Apple adds (see https://stackoverflow.com/questions/61364175/uisearchbar-with-a-white-background-is-impossible)
            searchController.searchBar.setSearchFieldBackgroundImage(UIImage(), for: .normal)
            searchController.searchBar.searchTextField.layer.cornerRadius = 10

            searchResultsController.searchController = searchController
            return searchController
        }()
        self.style = style
        self.privacyListType = privacyListType
        self.manager = manager
        self.saveAction = saveAction
        self.dismissAction = dismissAction
        super.init(nibName: nil, bundle: nil)

        self.title = title
        self.showOnlySelectedContacts = self.shouldOnlyShowSelectedContacts()
        updateSearchResultsController(showOnlySelectedContacts: showOnlySelectedContacts)
        self.header = getGlobalHeader()
        editSelectionRow.isHidden = isEditLinkHidden()
        collectionView.delegate = self

        cancellableSet.insert(
            manager.$selectedUserIDs.sink { [weak self] userIDs in
                DispatchQueue.main.async {
                    self?.update(selection: userIDs)
                }
            }
        )
    }

    private func shouldOnlyShowSelectedContacts() -> Bool {
        // If favorites/blocked list if empty, turn on edit mode
        manager.selectedUserIDs.isEmpty ? false : true
    }

    private func getGlobalHeader() -> String {
        if privacyListType == .blocked {
            return PrivacyList.name(forPrivacyListType: privacyListType)
        }
        return showOnlySelectedContacts ? Localizations.favoritesTitle : Localizations.favoritesTitleAlt
    }

    private func isEditLinkHidden() -> Bool {
        // If the list is not editable, do not ever show the edit link
        if !isListEditable() { return true }
        // If we are showing only selected contacts, show the edit link
        return showOnlySelectedContacts ? false : true
    }

    private func isListEditable() -> Bool {
        // Currently in the app, only whitelist and blocked list are editable
        return privacyListType == .whitelist || privacyListType == .blocked
    }

    private func getEditLabel() -> String {
        if privacyListType == .whitelist {
            return Localizations.editFavorites
        } else {
            return Localizations.editBlocked
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        if saveAction != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
            navigationItem.rightBarButtonItem?.tintColor = .primaryBlue
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))
        navigationItem.leftBarButtonItem?.tintColor = .primaryBlue

        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg
        isModalInPresentation = true

        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: view.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])

        dataSource.apply(makeDataSnapshot(searchString: nil), animatingDifferences: false)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    lazy var dataSource: UICollectionViewDiffableDataSource<String, SelectableContact> = {
        let source = UICollectionViewDiffableDataSource<String, SelectableContact>(collectionView: collectionView) { [weak self] collectionView, indexPath, contact in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SelectableContactReuse, for: indexPath)
            if let self = self, let itemCell = cell as? SelectableContactCell {
                itemCell.configure(with: contact, isSelected: self.manager.selectedUserIDs.contains(contact.userID), style: self.style, showOnlySelectedContacts: self.showOnlySelectedContacts)
            }
            return cell
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            if kind == HeaderView.elementKind {
                let supplementaryView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeaderView.elementKind, for: indexPath)

                if let self = self, let headerView = supplementaryView as? HeaderView {
                    headerView.text = String(self.sectionIndexes[indexPath.section])
                }
                return supplementaryView
            } else {
                let supplementaryView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PrivacySettingsHeaderView.elementKind, for: indexPath)

                if let self = self, let headerTitle = self.header, let headerView = supplementaryView as? PrivacySettingsHeaderView {
                    headerView.text = headerTitle
                }
                return supplementaryView
            }
        }

        return source
    }()

    private let style: Style
    private var header: String?
    private let manager: ContactSelectionManager
    private lazy var collectionView: UICollectionView = {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(ContactSelectionViewController.rowHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: BackgroundDecorationView.elementKind)
        backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16)

        let sectionHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(28))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionHeaderSize, elementKind: HeaderView.elementKind, alignment: .top)
        let section = NSCollectionLayoutSection(group: group)

        if header != nil {
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 28, leading: 16, bottom: 10, trailing: 16)
            section.boundarySupplementaryItems = [sectionHeader]
        }

        section.decorationItems = [backgroundDecoration]
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16)

        let globalHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(20))
        let globalHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: globalHeaderSize, elementKind: PrivacySettingsHeaderView.elementKind, alignment: .top)
        globalHeader.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.boundarySupplementaryItems = [globalHeader]

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration = layoutConfig
        layout.register(BackgroundDecorationView.self, forDecorationViewOfKind: BackgroundDecorationView.elementKind)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        collectionView.register(SelectableContactCell.self, forCellWithReuseIdentifier: SelectableContactReuse)
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: HeaderView.elementKind, withReuseIdentifier: HeaderView.elementKind)
        collectionView.register(PrivacySettingsHeaderView.self, forSupplementaryViewOfKind: PrivacySettingsHeaderView.elementKind, withReuseIdentifier: PrivacySettingsHeaderView.elementKind)

        return collectionView
    }()
    private var searchController: UISearchController?

    private let saveAction: ((ContactSelectionViewController, Set<UserID>) -> Void)?
    private let dismissAction: (() -> Void)?

    private var cancellableSet = Set<AnyCancellable>()

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ editSelectionRow, collectionView ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private func makeDataSnapshot(searchString: String?) -> NSDiffableDataSourceSnapshot<String, SelectableContact> {
        var snapshot = NSDiffableDataSourceSnapshot<String, SelectableContact>()
        var contacts: [SelectableContact]
        //if in edit mode, only show selected contacts
        if isListEditable(), showOnlySelectedContacts {
            contacts = manager.contacts(searchString: searchString).filter { manager.selectedUserIDs.contains($0.userID) }
        } else {
            contacts = manager.contacts(searchString: searchString)
        }
        let sections = Dictionary(grouping: contacts) { (contact) -> String in
            // All favorite contacts need to be in a single group on top
            if manager.selectedUserIDs.contains(contact.userID) { return "" }
            guard let name = contact.name.first else { return "" }
            return String(name.uppercased())
        }.sorted { (left, right) -> Bool in
            left.key < right.key
        }

        snapshot.appendSections(sections.map { $0.key} )
        sectionIndexes = sections.map { $0.key}
        for section in sections {
            snapshot.appendItems(section.value, toSection: section.key)
        }
        return snapshot
    }

    private func update(selection: Set<UserID>) {
        collectionView.reloadData()
    }

    // MARK: Top Nav Button Actions

    @objc private func didTapDone() {
        showOnlySelectedContacts = true
        updateSearchResultsController(showOnlySelectedContacts: showOnlySelectedContacts)
        saveAction?(self, manager.selectedUserIDs)
    }

    @objc private func didTapCancel() {
        showOnlySelectedContacts = true
        updateSearchResultsController(showOnlySelectedContacts: showOnlySelectedContacts)
        if let dismissAction = dismissAction {
            dismissAction()
        } else if let navigationController = navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    // Keyboard

    @objc private func keyboardWillShow(notification: Notification) {
        animateWithKeyboard(notification: notification) { (keyboardFrame) in
            self.mainView.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: keyboardFrame.height, right: 0)
        }
    }

    @objc private func keyboardWillHide(notification: Notification) {
        animateWithKeyboard(notification: notification) { (keyboardFrame) in
            self.mainView.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        }
    }

    // TODO: define as delegate?
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController?.searchBar.endEditing(true)
    }

    // MARK: Helpers

    private func animateWithKeyboard(notification: Notification, animations: ((_ keyboardFrame: CGRect) -> Void)?) {

        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        guard let duration = notification.userInfo?[durationKey] as? Double else { return }

        let frameKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameValue = notification.userInfo?[frameKey] as? NSValue else { return }

        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        guard let curveValue = notification.userInfo?[curveKey] as? Int else { return }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return }

        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            animations?(keyboardFrameValue.cgRectValue)
            self.view?.layoutIfNeeded()
        }
        animator.startAnimation()
    }
}

extension ContactSelectionViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let contact = dataSource.itemIdentifier(for: indexPath) else { return }
        if style == .all || showOnlySelectedContacts {
            return
        }
        searchController?.searchBar.text = ""
        manager.toggleSelection(for: contact.userID)
    }
}

extension ContactSelectionViewController: GroupMemberAvatarsDelegate {
    func groupMemberAvatarsDelegate(_ view: GroupMemberAvatars, selectedUser: String) {
        manager.toggleSelection(for: selectedUser)
    }
}

extension ContactSelectionViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        dataSource.apply(makeDataSnapshot(searchString: searchController.searchBar.text))
    }
}

fileprivate class HeaderView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: HeaderView.self)
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
        label.font = .systemFont(ofSize: 16, weight: .medium)
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

fileprivate class PrivacySettingsHeaderView: UICollectionReusableView {

    public override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        // Always ensure global header is on top of the section header
        // Setting the ZIndex on the supplementary item did not work
        // and hence we need to override the zPosition here
        self.layer.zPosition = 1000
    }

    static var elementKind: String {
        return String(describing: PrivacySettingsHeaderView.self)
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
        backgroundColor = UIColor.primaryBg
        addSubview(titleView)
        titleView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        titleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

fileprivate class BackgroundDecorationView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: BackgroundDecorationView.self)
    }

    override var bounds: CGRect {
        didSet {
            configure()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feedPostBackground
        layer.cornerRadius = 10
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        for view in subviews {
            view.removeFromSuperview()
        }

        let height = ContactSelectionViewController.rowHeight
        let inset = CGFloat(16)
        let color = UIColor.separatorGray
        let count = Int(bounds.height / height)

        if count > 0 {
            for i in 1..<count {
                let position = height * CGFloat(i)
                let separatorView = UIView(frame: CGRect(x: inset, y: position, width: bounds.width - inset, height: 0.5))
                separatorView.backgroundColor = color

                addSubview(separatorView)
            }
        }
    }
}

final class SelectableContactCell: UICollectionViewCell {

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(contactView)
        contactView.translatesAutoresizingMaskIntoConstraints = false
        contactView.constrain(to: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: SelectableContact, isSelected: Bool, style: ContactSelectionViewController.Style, showOnlySelectedContacts: Bool) {
        contactView.configure(with: contact, isSelected: isSelected, style: style, showOnlySelectedContacts: showOnlySelectedContacts)
    }

    private let contactView = ContactSelectionView(frame: .zero)
}

final class ContactSelectionView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label

        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel

        let labelStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.axis = .vertical
        labelStack.distribution = .fillProportionally
        labelStack.alignment = .leading
        labelStack.spacing = 0

        accessoryImageView.translatesAutoresizingMaskIntoConstraints = false
        accessoryImageView.tintColor = .lavaOrange

        addSubview(avatarView)
        addSubview(labelStack)
        addSubview(accessoryImageView)

        let spacing: CGFloat = 13

        avatarView.constrain(anchor: .centerY, to: self)
        avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        avatarView.widthAnchor.constraint(equalToConstant: 30).isActive = true
        avatarView.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor).isActive = true
        avatarView.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true

        labelStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: spacing).isActive = true
        labelStack.constrain(anchor: .centerY, to: self)
        labelStack.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor).isActive = true
        labelStack.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true

        accessoryImageView.leadingAnchor.constraint(equalTo: labelStack.trailingAnchor, constant: spacing).isActive = true
        accessoryImageView.constrain(anchor: .centerY, to: self)
        accessoryImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16).isActive = true
        accessoryImageView.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor).isActive = true
        accessoryImageView.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: SelectableContact, isSelected: Bool, style: ContactSelectionViewController.Style, showOnlySelectedContacts: Bool) {
        nameLabel.text = contact.name
        subtitleLabel.text = contact.phoneNumber ?? ""
        avatarView.configure(with: contact.userID, using: MainAppContext.shared.avatarStore)
        accessoryImageView.image = isSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked

        if isSelected {
            switch style {
            case .`default`:
                accessoryImageView.tintColor = .primaryBlue
                accessoryImageView.image = Self.checkmarkChecked
                accessoryImageView.isHidden = showOnlySelectedContacts
            case .destructive:
                accessoryImageView.tintColor = .lavaOrange
                accessoryImageView.image = Self.xmarkChecked
            case .all:
                accessoryImageView.isHidden = true
            }
        } else {
            switch style {
            case .all:
                accessoryImageView.isHidden = true
            default:
                accessoryImageView.tintColor = .primaryBlackWhite.withAlphaComponent(0.2)
                accessoryImageView.image = Self.checkmarkUnchecked
                accessoryImageView.isHidden = showOnlySelectedContacts
            }
        }
    }

    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let avatarView = AvatarView()
    private let accessoryImageView = UIImageView()

    private static var checkmarkUnchecked: UIImage {
        UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate)
    }

    private static var checkmarkChecked: UIImage {
        UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate)
    }

    private static var xmarkChecked: UIImage {
        UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 25))!.withRenderingMode(.alwaysTemplate)
    }
    
    static var forSizing: ContactSelectionView {
        let cell = ContactSelectionView()
        cell.nameLabel.text = " "
        cell.subtitleLabel.text = " "
        return cell
    }
}

extension ContactSelectionViewController {

    static func forAllContacts(_ privacyListType: PrivacyListType, in privacySettings: PrivacySettings, doneAction: (() -> Void)? = nil, dismissAction: (() -> Void)?) -> ContactSelectionViewController {
        return ContactSelectionViewController(
            manager: ContactSelectionManager(initialSelection: Set()),
            title: PrivacyList.title(forPrivacyListType: privacyListType),
            header: PrivacyList.details(forPrivacyListType: privacyListType),
            style: .all,
            privacyListType: privacyListType,
            saveAction: { vc, userIDs in

                if let doneAction = doneAction {
                    doneAction()
                } else {
                    dismissAction?()
                }
            },
            dismissAction: dismissAction)
    }

    static func forPrivacyList(_ privacyList: PrivacyList, in privacySettings: PrivacySettings, setActiveType: Bool, doneAction: (() -> Void)? = nil, dismissAction: (() -> Void)?) -> ContactSelectionViewController {
        return ContactSelectionViewController(
            manager: ContactSelectionManager(initialSelection: Set(privacyList.userIds)),
            title: PrivacyList.title(forPrivacyListType: privacyList.type),
            header: PrivacyList.details(forPrivacyListType: privacyList.type),
            style: privacyList.type == .blacklist ? .destructive : .default,
            privacyListType: privacyList.type,
            saveAction: { vc, userIDs in

                // If the favorites list is empty, default to MyContacts
                if privacyList.type == .whitelist, userIDs.isEmpty, setActiveType {
                    MainAppContext.shared.privacySettings.activeType = .all
                    privacySettings.replaceUserIDs(in: privacyList, with: userIDs, setActiveType: false)
                } else {
                    privacySettings.replaceUserIDs(in: privacyList, with: userIDs, setActiveType: setActiveType)
                }

                if let doneAction = doneAction {
                    doneAction()
                } else {
                    dismissAction?()
                }
            },
            dismissAction: dismissAction)
    }

    func presentNoContactSelectedAlert() {
        let alert = UIAlertController(
            title: Localizations.noContactSelected,
            message: Localizations.selectAtLeastOneContact,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
        present(alert, animated: true)
    }
}

class ContactSelectionManager {

    init(initialSelection: Set<UserID>) {
        let ownUserID = MainAppContext.shared.userData.userId
        var uniqueUserIDs = Set<UserID>()
        allContacts = MainAppContext.shared.contactStore
            .allRegisteredContacts(sorted: true, in: MainAppContext.shared.contactStore.viewContext)
            .compactMap {
                guard let userID = $0.userId, let name = $0.fullName else { return nil }
                guard userID != ownUserID, !uniqueUserIDs.contains(userID) else { return nil }
                uniqueUserIDs.insert(userID)
                return SelectableContact(
                    userID: userID,
                    name: name,
                    phoneNumber: $0.phoneNumber,
                    searchTokens: $0.searchTokens)
            }
        let unknownUserIDs = initialSelection.subtracting(uniqueUserIDs)
        let namesForUnknownContacts = UserProfile.names(from: unknownUserIDs, in: MainAppContext.shared.mainDataStore.viewContext)
        allContacts += unknownUserIDs.map {
            SelectableContact(userID: $0, name: namesForUnknownContacts[$0] ?? Localizations.unknownContact)
        }
        self.selectedUserIDs = initialSelection
    }

    @Published private(set) var selectedUserIDs: Set<UserID>

    func contacts(searchString: String?) -> [SelectableContact] {
        let strippedString = searchString?.trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
        let searchItems = strippedString.components(separatedBy: " ").filter { !$0.isEmpty }

        guard !searchItems.isEmpty else { return allContacts }

        let returningContacts = allContacts.filter { contact in
            let allTokens = [contact.name] + contact.searchTokens
            for token in allTokens {
                for item in searchItems {
                    if token.localizedCaseInsensitiveContains(item) { return true }
                }
            }
            return false
        }
        return returningContacts
    }

    func toggleSelection(for userID: UserID) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.remove(userID)
        } else {
            selectedUserIDs.insert(userID)
        }
    }

    private var allContacts: [SelectableContact]
}

struct SelectableContact: Hashable, Equatable {
    var userID: UserID
    var name: String
    var phoneNumber: String?
    var searchTokens = [String]()
}

extension Localizations {
    static var noContactSelected: String {
        NSLocalizedString("no.contact.selected", value: "No contact selected", comment: "Title for alert that pops up when user attempts to save an empty contact list")
    }
    static var selectAtLeastOneContact: String {
        NSLocalizedString("select.at.least.one.contact", value: "Please select at least one contact.", comment: "Message that pops up when user attempts to save an empty contact list")
    }
    static var editFavorites: String {
        NSLocalizedString("edit.favorites", value: "Edit Favorites", comment: "link, tapping on which launched the flow to edit favorites")
    }

    static var editBlocked: String {
        NSLocalizedString("edit.blocked", value: "Edit", comment: "link, tapping on which launched the flow to edit blocked contacts")
    }
}
