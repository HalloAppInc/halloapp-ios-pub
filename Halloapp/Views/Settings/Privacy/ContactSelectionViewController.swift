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
    static let rowHeight = CGFloat(54)

    enum Style {
        case `default`, destructive
    }

    init(
        manager: ContactSelectionManager,
        title: String? = nil,
        header: String? = nil,
        showSearch: Bool = true,
        style: Style = .default,
        saveAction: ((ContactSelectionViewController, Set<UserID>) -> Void)? = nil,
        dismissAction: (() -> Void)? = nil)
    {
        searchController = {
            guard showSearch else { return nil }
            let searchResultsController = ContactSelectionViewController(manager: manager, header: header, showSearch: false, dismissAction: nil)
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
        self.header = header
        self.manager = manager
        self.saveAction = saveAction
        self.dismissAction = dismissAction

        super.init(nibName: nil, bundle: nil)

        self.title = title
        collectionView.delegate = self

        cancellableSet.insert(
            manager.$selectedUserIDs.sink { [weak self] userIDs in
                DispatchQueue.main.async {
                    self?.update(selection: userIDs)
                }
            }
        )
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

        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        // TODO: Get rid of key window stuff
        let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first
        let safeAreaInsetBottom = (keyWindow?.safeAreaInsets.bottom ?? 0) + 10
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: safeAreaInsetBottom).isActive = true

        dataSource.apply(makeDataSnapshot(searchString: nil), animatingDifferences: false)

        groupMemberAvatars.insert(with: Array(manager.selectedUserIDs))
        selectedAvatarsRow.isHidden = manager.selectedUserIDs.isEmpty

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    lazy var dataSource: UICollectionViewDiffableDataSource<Int, SelectableContact> = {
        let source = UICollectionViewDiffableDataSource<Int, SelectableContact>(collectionView: collectionView) { [weak self] collectionView, indexPath, contact in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SelectableContactReuse, for: indexPath)
            if let self = self, let itemCell = cell as? SelectableContactCell {
                itemCell.configure(with: contact, isSelected: self.manager.selectedUserIDs.contains(contact.userID), style: self.style)
            }
            return cell
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            let supplementaryView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeaderView.elementKind, for: indexPath)

            if let self = self, let headerTitle = self.header, let headerView = supplementaryView as? HeaderView {
                headerView.text = headerTitle
            }

            return supplementaryView
        }

        return source
    }()

    private let style: Style
    private let header: String?
    private let manager: ContactSelectionManager
    private lazy var collectionView: UICollectionView = {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(ContactSelectionViewController.rowHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: BackgroundDecorationView.elementKind)
        backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: HeaderView.elementKind, alignment: .top)

        let section = NSCollectionLayoutSection(group: group)

        if header != nil {
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 16, bottom: 0, trailing: 16)
            section.boundarySupplementaryItems = [sectionHeader]
        }

        section.decorationItems = [backgroundDecoration]
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.register(BackgroundDecorationView.self, forDecorationViewOfKind: BackgroundDecorationView.elementKind)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        collectionView.register(SelectableContactCell.self, forCellWithReuseIdentifier: SelectableContactReuse)
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: HeaderView.elementKind, withReuseIdentifier: HeaderView.elementKind)

        return collectionView
    }()
    private var searchController: UISearchController?

    private let saveAction: ((ContactSelectionViewController, Set<UserID>) -> Void)?
    private let dismissAction: (() -> Void)?

    private var cancellableSet = Set<AnyCancellable>()

    private lazy var selectedAvatarsRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ groupMemberAvatars ])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.feedBackground
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        let topBorder = UIView(frame: view.bounds)
        topBorder.frame.size.height = 1
        topBorder.backgroundColor = UIColor.secondarySystemGroupedBackground
        topBorder.autoresizingMask = [.flexibleWidth]
        view.insertSubview(topBorder, at: 1)

        return view
    }()

    private lazy var groupMemberAvatars: GroupMemberAvatars = {
        let view = GroupMemberAvatars()
        view.delegate = self
        return view
    }()

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ collectionView, selectedAvatarsRow ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private func makeDataSnapshot(searchString: String?) -> NSDiffableDataSourceSnapshot<Int, SelectableContact> {
        var snapshot = NSDiffableDataSourceSnapshot<Int, SelectableContact>()

        let contacts = manager.contacts(searchString: searchString)
        snapshot.appendSections([0])
        snapshot.appendItems(contacts, toSection: 0)

        return snapshot
    }

    private func update(selection: Set<UserID>) {
        let added = selection.subtracting(groupMemberAvatars.avatarUserIDs)
        groupMemberAvatars.insert(with: Array(added))

        let removed = Set(groupMemberAvatars.avatarUserIDs).subtracting(selection)
        for toRemove in removed {
            groupMemberAvatars.removeUser(toRemove)
        }

        selectedAvatarsRow.isHidden = selection.isEmpty
        collectionView.reloadData()
    }

    // MARK: Top Nav Button Actions

    @objc private func didTapDone() {
        saveAction?(self, manager.selectedUserIDs)
    }

    @objc private func didTapCancel() {
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
        let color = UIColor.separator
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

    func configure(with contact: SelectableContact, isSelected: Bool, style: ContactSelectionViewController.Style) {
        contactView.configure(with: contact, isSelected: isSelected, style: style)
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

    func configure(with contact: SelectableContact, isSelected: Bool, style: ContactSelectionViewController.Style) {
        nameLabel.text = contact.name
        subtitleLabel.text = contact.phoneNumber ?? ""
        avatarView.configure(with: contact.userID, using: MainAppContext.shared.avatarStore)
        accessoryImageView.image = isSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked

        if isSelected {
            switch style {
            case .`default`:
                accessoryImageView.tintColor = .primaryBlue
                accessoryImageView.image = Self.checkmarkChecked
            case .destructive:
                accessoryImageView.tintColor = .lavaOrange
                accessoryImageView.image = Self.xmarkChecked
            }
        } else {
            accessoryImageView.tintColor = .primaryBlackWhite.withAlphaComponent(0.2)
            accessoryImageView.image = Self.checkmarkUnchecked
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
}

extension ContactSelectionViewController {
    static func forPrivacyList(_ privacyList: PrivacyList, in privacySettings: PrivacySettings, doneAction: (() -> Void)? = nil, dismissAction: (() -> Void)?) -> ContactSelectionViewController {
        return ContactSelectionViewController(
            manager: ContactSelectionManager(initialSelection: Set(privacyList.userIds)),
            title: PrivacyList.title(forPrivacyListType: privacyList.type),
            header: PrivacyList.details(forPrivacyListType: privacyList.type),
            style: privacyList.type == .blacklist ? .destructive : .default,
            saveAction: { vc, userIDs in

                if privacyList.type == .whitelist, userIDs.isEmpty {
                    vc.presentNoContactSelectedAlert()
                    return
                }

                privacySettings.replaceUserIDs(in: privacyList, with: userIDs)

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
            .allRegisteredContacts(sorted: true)
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
        let namesForUnknownContacts = MainAppContext.shared.contactStore.fullNames(forUserIds: unknownUserIDs)
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

        return allContacts.filter { contact in
            let allTokens = [contact.name] + contact.searchTokens
            for token in allTokens {
                for item in searchItems {
                    if token.localizedCaseInsensitiveContains(item) { return true }
                }
            }
            return false
        }
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
}
