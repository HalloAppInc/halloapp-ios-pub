//
//  ChangeDestinationViewController.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation
import SwiftUI
import UIKit

private extension Localizations {
    static var title: String {
        return NSLocalizedString("post.privacy.title",
                                 value: "Share With...",
                                 comment: "Controller title for changing destination and privacy")
    }

    static var contactsHeader: String {
        return NSLocalizedString("post.privacy.header.contacts",
                                 value: "Who will see this post",
                                 comment: "Header when selecting all or some contacts to share with")
    }

    static var groupsHeader: String {
        return NSLocalizedString("post.privacy.header.groups",
                                 value: "Share only with a group",
                                 comment: "Header when selecting a group to share with")
    }
}

class ChangeDestinationViewController: UIViewController {

    static let rowHeight = CGFloat(54)

    private lazy var fetchedResultsController: NSFetchedResultsController<ChatThread> = {
        let request = ChatThread.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        request.predicate = NSPredicate(format: "groupID != nil")
        
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: request,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        return fetchedResultsController
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self = self else { return nil }

            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            var groupHeight: NSCollectionLayoutDimension = .absolute(ContactSelectionViewController.rowHeight)

            if !self.isSearching && sectionIndex == 0 {
                item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                groupHeight = .absolute(ContactSelectionViewController.rowHeight + 7)
            }

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: groupHeight)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: HeaderView.elementKind, alignment: .top)

            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [sectionHeader]
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

            if sectionIndex == 1 || self.isSearching {
                let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: BackgroundDecorationView.elementKind)
                backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 16, bottom: 0, trailing: 16)

                section.decorationItems = [backgroundDecoration]
            }

            if sectionIndex == 0 {
                let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: ContactsCellBackgroundDecorationView.elementKind)
                backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 16, bottom: 0, trailing: 16)

                section.decorationItems = [backgroundDecoration]
            }

            return section
        }

        layout.register(ContactsCellBackgroundDecorationView.self, forDecorationViewOfKind: ContactsCellBackgroundDecorationView.elementKind)
        layout.register(BackgroundDecorationView.self, forDecorationViewOfKind: BackgroundDecorationView.elementKind)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        collectionView.register(ContactsCell.self, forCellWithReuseIdentifier: ContactsCell.reuseIdentifier)
        collectionView.register(GroupCell.self, forCellWithReuseIdentifier: GroupCell.reuseIdentifier)
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: HeaderView.elementKind, withReuseIdentifier: HeaderView.elementKind)
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag

        return collectionView
    }()

    private lazy var bottomConstraint: NSLayoutConstraint = {
        collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    } ()

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))

        return item
    }()

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.definesPresentationContext = true
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchBar.autocapitalizationType = .none
        controller.searchBar.delegate = self

        return controller
    }()

    private var isSearching: Bool {
        !(searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty ?? true)
    }

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, ShareDestination> = {
        let source = UICollectionViewDiffableDataSource<Int, ShareDestination>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return nil }

            let isSelected = self.destination == item

            switch item {
            case .feed(let privacyListType):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ContactsCell.reuseIdentifier, for: indexPath) as? ContactsCell else { return nil }
                let privacySettings = MainAppContext.shared.privacySettings

                switch privacyListType {
                case .all:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .all),
                        subtitle: Localizations.feedPrivacyShareWithAllContacts,
                        privacyListType: .all,
                        isSelected: isSelected,
                        hasNext: true)
                case .whitelist:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .whitelist),
                        subtitle: isSelected ? privacySettings.longFeedSetting : Localizations.feedPrivacyShareWithSelected,
                        privacyListType: .whitelist,
                        isSelected: isSelected,
                        hasNext: true)
                default:
                    return nil
                }

                return cell
            case .group(let groupID, let name):
                guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GroupCell.reuseIdentifier, for: indexPath) as? GroupCell else { return nil }
                cell.configure(groupId: groupID, title: name, isSelected: isSelected)

                return cell
            default:
                return nil
            }
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeaderView.elementKind, for: indexPath)

            if let self = self, let headerView = view as? HeaderView {
                headerView.text = indexPath.section == 0 && !self.isSearching ? Localizations.contactsHeader : Localizations.groupsHeader
            }

            return view
        }

        return source
    }()

    private var cancellableSet: Set<AnyCancellable> = []
    private var destination: ShareDestination
    private var completion: (ChangeDestinationViewController, ShareDestination) -> Void

    init(destination: ShareDestination, completion: @escaping (ChangeDestinationViewController, ShareDestination) -> Void) {
        self.destination = destination
        self.completion = completion

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        view.backgroundColor = .primaryBg

        navigationItem.title = Localizations.titlePrivacy
        navigationItem.leftBarButtonItem = leftBarButtonItem
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        view.addSubview(collectionView)

        collectionView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bottomConstraint.isActive = true

        try? fetchedResultsController.performFetch()

        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) {
                self.bottomConstraint.constant = -$0
            }
        })

        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) { _ in
                self.bottomConstraint.constant = 0
            }
        })

        dataSource.apply(makeSnapshot())
    }

    private func animateWithKeyboard(notification: Notification, animations: @escaping (CGFloat) -> Void) {
        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        guard let duration = notification.userInfo?[durationKey] as? Double else { return }

        let frameKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameValue = notification.userInfo?[frameKey] as? NSValue else { return }

        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        guard let curveValue = notification.userInfo?[curveKey] as? Int else { return }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return }

        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            animations(keyboardFrameValue.cgRectValue.height)
            self.view?.layoutIfNeeded()
        }

        animator.startAnimation()
    }

    @objc func backAction() {
        if searchController.isActive {
            dismiss(animated: true)
        }

        completion(self, destination)
    }

    private func makeSnapshot(searchString: String? = nil) -> NSDiffableDataSourceSnapshot<Int, ShareDestination> {
        var snapshot = NSDiffableDataSourceSnapshot<Int, ShareDestination>()
        let threads = fetchedResultsController.fetchedObjects

        if let searchString = searchString?.trimmingCharacters(in: CharacterSet.whitespaces).lowercased(), !searchString.isEmpty {
            snapshot.appendSections([1])

            let searchItems = searchString.components(separatedBy: " ")
            threads?.forEach {
                guard let groupId = $0.groupId, let title = $0.title else { return }

                let titleLowercased = title.lowercased()
                for item in searchItems {
                    if titleLowercased.contains(item) {
                        snapshot.appendItems([.group(id: groupId, name: title)], toSection: 1)
                    }
                }
            }
        } else {
            snapshot.appendSections([0])
            snapshot.appendItems([.feed(.all), .feed(.whitelist)], toSection: 0)

            if let threads = threads, threads.count > 0 {
                snapshot.appendSections([1])
                snapshot.appendItems(threads.compactMap {
                    guard let groupId = $0.groupId, let title = $0.title else { return nil }
                    return .group(id: groupId, name: title)
                }, toSection: 1)
            }
        }

        return snapshot
    }
}

// MARK: UICollectionViewDelegate
extension ChangeDestinationViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selected = dataSource.itemIdentifier(for: indexPath) else { return }
        self.destination = selected

        if searchController.isActive {
            dismiss(animated: true)
        }

        if case .feed(let privacyListType) = selected {
            let privacySettings = MainAppContext.shared.privacySettings

            if privacyListType == .all {
                privacySettings.setFeedSettingToAllContacts()
                setConfigToAllContacts()
                backAction()
            } else if privacyListType == .whitelist {
                // if favorites list is empty.. open up edit flow with edit mode on
                if privacySettings.whitelist.userIds.isEmpty {
                    let controller = ContactSelectionViewController.forPrivacyList(privacySettings.whitelist, in: privacySettings, setActiveType: true, doneAction: { [weak self] in
                        self?.dismiss(animated: false)
                        self?.setConfigToFavorites()
                        self?.backAction()
                    }, dismissAction: nil)

                    present(UINavigationController(rootViewController: controller), animated: true)
                } else {
                    setConfigToFavorites()
                    backAction()
                }
            }
        } else {
            backAction()
        }
    }
}

// MARK: UISearchBarDelegate
extension ChangeDestinationViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            self.dataSource.apply(self.makeSnapshot())
            self.collectionView.scrollToItem(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
    }
}

// MARK: UISearchResultsUpdating
extension ChangeDestinationViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        dataSource.apply(makeSnapshot(searchString: searchController.searchBar.text))
    }
}

extension ChangeDestinationViewController: ContactsCellDelegate {
    fileprivate func didTapViewList(_ contactsCell: ContactsCell, privacyListType: PrivacyListType) {
        let privacySettings = MainAppContext.shared.privacySettings
        switch privacyListType {
        case .all:
            privacySettings.setFeedSettingToAllContacts()
            if searchController.isActive {
                dismiss(animated: true)
            }

            let controller = ContactSelectionViewController.forAllContacts(PrivacyListType.all, in: privacySettings, doneAction: { [weak self] in
                self?.dismiss(animated: false)
                self?.setConfigToAllContacts()
                self?.backAction()
                privacySettings.setFeedSettingToAllContacts()
            }, dismissAction: nil)

            present(UINavigationController(rootViewController: controller), animated: true)
        case .whitelist:
            if searchController.isActive {
                dismiss(animated: true)
            }

            let controller = ContactSelectionViewController.forPrivacyList(privacySettings.whitelist, in: privacySettings, setActiveType: true, doneAction: { [weak self] in
                self?.dismiss(animated: false)
                self?.setConfigToFavorites()
                self?.backAction()
            }, dismissAction: nil)

            present(UINavigationController(rootViewController: controller), animated: true)
        default:
            return
        }
    }

    private func setConfigToAllContacts() {
        destination = .feed(.all)
        MainAppContext.shared.privacySettings.activeType = .all
    }

    private func setConfigToFavorites() {
        destination = .feed(.whitelist)
        MainAppContext.shared.privacySettings.activeType = .whitelist
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

fileprivate class ContactsCellBackgroundDecorationView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: ContactsCellBackgroundDecorationView.self)
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
        let height = ContactSelectionViewController.rowHeight + 7
        let color = UIColor.separator
        let count = Int(bounds.height / height)

        if count > 0 {
            for i in 1..<count {
                let position = height * CGFloat(i)
                let separatorView = UIView(frame: CGRect(x: 0, y: position, width: bounds.width, height: 0.5))
                separatorView.backgroundColor = color

                addSubview(separatorView)
            }
        }
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
        let inset = CGFloat(44)
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

fileprivate protocol ContactsCellDelegate: AnyObject {
    func didTapViewList(_ contactsCell: ContactsCell, privacyListType: PrivacyListType)
}

fileprivate class ContactsCell: UICollectionViewCell {
    var delegate:ContactsCellDelegate?
    var privacyListType: PrivacyListType?
    static var reuseIdentifier: String {
        return String(describing: ContactsCell.self)
    }

    private lazy var titleView: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label

        return label
    }()

    private lazy var subtitleView: UILabel = {
        let label = UILabel()
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        
        return label
    }()

    private lazy var nextView: UIButton = {
        let nextViewButton = UIButton()
        nextViewButton.addTarget(self, action: #selector(didTapViewList), for: .touchUpInside)
        nextViewButton.translatesAutoresizingMaskIntoConstraints = false
        let imageConf = UIImage.SymbolConfiguration(pointSize: 18)
        let image = UIImage(systemName: "chevron.right", withConfiguration: imageConf)!.withRenderingMode(.alwaysTemplate)
        nextViewButton.setImage(image, for: .normal)
        nextViewButton.layer.cornerRadius = 11
        nextViewButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        nextViewButton.tintColor = .primaryBlackWhite.withAlphaComponent(0.3)
        return nextViewButton
    }()

    @objc func didTapViewList(_ sender: UITapGestureRecognizer) {
        if let privacyListType = privacyListType {
            delegate?.didTapViewList(self, privacyListType: privacyListType)
        }
    }

    private lazy var selectedView: UIView = {
        let imageConf = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: imageConf)!.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .primaryBlue
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return imageView
    }()

    private lazy var settingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.contentMode = .scaleAspectFit

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
        ])
        return imageView
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
        subtitleView.text = MainAppContext.shared.privacySettings.composerIndicator
    }

    private func setup() {
        layer.cornerRadius = 10
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        layer.masksToBounds = false

        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true

        let vStack = UIStackView(arrangedSubviews: [ titleView, subtitleView ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.isUserInteractionEnabled = false
        vStack.axis = .vertical
        vStack.alignment = .leading
        vStack.distribution = .fillProportionally
        vStack.spacing = 1

        let hStack = UIStackView(arrangedSubviews: [selectedView, settingImageView, vStack, nextView])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10

        contentView.addSubview(hStack)
        nextView.topAnchor.constraint(equalTo: hStack.topAnchor).isActive = true
        nextView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 11).isActive = true
        hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
    }

    func configure(title: String, subtitle: String, privacyListType: PrivacyListType, isSelected: Bool, hasNext: Bool) {
        titleView.text = title
        subtitleView.text = subtitle
        selectedView.tintColor = isSelected ? .primaryBlue : .clear
        nextView.isHidden = !hasNext
        self.privacyListType = privacyListType
        configureSettingsImage(for: privacyListType)
    }

    func configureSettingsImage(for privacyListType: PrivacyListType) {
        switch privacyListType {
        case .all:
            settingImageView.image = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.primaryBlue)
        case .whitelist:
            settingImageView.image = UIImage(named: "PrivacySettingFavoritesWithBackground")
        default:
            break
        }
    }
}

fileprivate class GroupCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: GroupCell.self)
    }

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.widthAnchor.constraint(equalToConstant: 32).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        return view
    }()

    private lazy var titleView: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .label

        return label
    }()

    private lazy var selectedView: UIView = {
        let imageConf = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: imageConf)!.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .clear
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layoutMargins = UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 0)
        preservesSuperviewLayoutMargins = false

        let hStack = UIStackView(arrangedSubviews: [selectedView, avatarView, titleView])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10

        contentView.addSubview(hStack)

        hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11).isActive = true
        hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11).isActive = true
        hStack.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 11).isActive = true
        hStack.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -11).isActive = true
    }

    func configure(groupId: GroupID, title: String, isSelected: Bool) {
        titleView.text = title
        avatarView.configure(groupId: groupId, squareSize: 32, using: MainAppContext.shared.avatarStore)
        selectedView.tintColor = isSelected ? .primaryBlue : .clear
    }
}
