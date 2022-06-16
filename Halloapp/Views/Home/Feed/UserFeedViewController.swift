//
//  UserFeedViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import ContactsUI
import Core
import CoreCommon
import CoreData
import SwiftUI
import UIKit

class UserFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    override var collectionViewSupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] {
        return headerViewController == nil ? [] : [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                                                          heightDimension: .estimated(44)),
                                                        elementKind: UICollectionView.elementKindSectionHeader,
                                                        alignment: .top)
        ]
    }

    override class var collectionViewSectionInsets: NSDirectionalEdgeInsets {
        return NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 20, trailing: 0)
    }

    init(userId: UserID, showHeader: Bool = true) {
        self.userId = userId
        self.isUserBlocked = false
        headerViewController = showHeader ? ProfileHeaderViewController() : nil
        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userId: UserID
    private let headerViewController: ProfileHeaderViewController?
    private var cancellables = Set<AnyCancellable>()
    
    var isUserBlocked: Bool {
        didSet {
            guard isUserBlocked != oldValue else { return }
            DispatchQueue.main.async {
                // Header may need to change size
                self.collectionView.reloadData()
            }
        }
    }

    private lazy var exchangeNumbersView: UIView = {
        let image = UIImage(named: "FeedExchangeNumbers")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.exchangePhoneNumbersToConnect
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        return stackView
    }()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        installExchangeNumbersView()

        isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(userId)

        if !isOwnFeed {
            // need to refresh when user is not in address book but gets added via the More menu
            MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] (newUserIDs) in
                guard let self = self else { return }
                if newUserIDs.contains(self.userId) {
                    self.headerViewController?.configureOrRefresh(userID: self.userId)
                    self.collectionView.reloadData()
                    self.updateExchangeNumbersView(isFeedEmpty: self.collectionView.numberOfItems(inSection: 0) == 0)
                    self.setupMoreButton()
                }
            }.store(in: &cancellables)
            
            MainAppContext.shared.didPrivacySettingChange.sink { [weak self] changedID in
                // update views if block setting changed
                if changedID == self?.userId {
                    self?.isUserBlocked = MainAppContext.shared.privacySettings.blocked.userIds.contains(changedID)
                    self?.headerViewController?.configureOrRefresh(userID: changedID)
                    self?.setupMoreButton()
                }
            }.store(in: &cancellables)
        }
    }

    override func setupCollectionView() {
        super.setupCollectionView()
        
        headerViewController?.delegate = self
        if isOwnFeed {
            title = Localizations.titleMyPosts

            headerViewController?.isEditingAllowed = true
            cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
                guard let self = self else { return }
                self.headerViewController?.configureForCurrentUser(withName: userName)
                self.viewIfLoaded?.setNeedsLayout()
            }))
        } else {
            headerViewController?.configureOrRefresh(userID: userId)
            setupMoreButton()
        }

        collectionViewDataSource?.supplementaryViewProvider = { [weak self] (collectionView, kind, path) -> UICollectionReusableView? in
            guard let self = self else {
                return UICollectionReusableView()
            }
            return self.collectionView(collectionView, viewForSupplementaryElementOfKind: kind, at: path)
        }
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier)
    }
    
    private func setupMoreButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis")) {
            HAMenu.actionsForUser(id: userId, options: [.utilityActions, .blockAction]) { [weak self] action in
                self?.handle(action: action)
            }
        }
    }

    override func showGroupName() -> Bool {
        return true
    }

    private func installExchangeNumbersView() {
        view.addSubview(exchangeNumbersView)

        exchangeNumbersView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true
        exchangeNumbersView.constrain([.centerX, .centerY], to: view)
    }

    private func updateExchangeNumbersView(isFeedEmpty: Bool) {
        let viewContext = MainAppContext.shared.contactStore.viewContext
        let isKnownContact = MainAppContext.shared.contactStore.contact(withUserId: userId, in: viewContext) != nil

        exchangeNumbersView.isHidden = !isFeedEmpty || isKnownContact || isOwnFeed
    }

    private var isOwnFeed: Bool {
        return MainAppContext.shared.userData.userId == userId
    }
    
    // MARK: FeedCollectionViewController

    override func shouldOpenFeed(for userId: UserID) -> Bool {
        return userId != self.userId
    }

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateExchangeNumbersView(isFeedEmpty: items.isEmpty)
    }

    // MARK: Collection View Header

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader && indexPath.section == 0 {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier, for: indexPath)
            if let superView = headerViewController?.view.superview, superView != headerView {
                headerViewController?.willMove(toParent: nil)
                headerViewController?.view.removeFromSuperview()
                headerViewController?.removeFromParent()
            }
            if let header = headerViewController, header.view.superview == nil {
                addChild(header)
                headerView.addSubview(header.view)
                headerView.preservesSuperviewLayoutMargins = true
                headerViewController?.view.translatesAutoresizingMaskIntoConstraints = false
                headerViewController?.view.constrain(to: headerView)
                headerViewController?.didMove(toParent: self)
            }
            return headerView
        }
        return UICollectionReusableView()
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        guard
            let header = headerViewController,
            !header.isEditingAllowed
        else {
            return
        }
        
        let offset = scrollView.contentOffset.y
        let scrolledLimit:CGFloat = header.view.frame.size.height/3.5
        var titleText = ""

        if offset > scrolledLimit {
            titleText = header.name ?? ""
        }
        
        if title != titleText {
            title = titleText
        }
    }
}

extension UserFeedViewController: CNContactViewControllerDelegate, ProfileHeaderDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        navigationController?.popViewController(animated: true)
    }
    func profileHeaderDidTapUnblock(_ profileHeader: ProfileHeaderViewController) {
        isUserBlocked = false
    }
}

extension Localizations {
    static var exchangePhoneNumbersToConnect: String {
        NSLocalizedString(
            "exchange.phone.numbers.to.connect",
            value: "To connect you must exchange phone numbers",
            comment: "Text to show on profile for users you are not connected with")
    }
    
    static var addToContactBook: String {
        NSLocalizedString(
            "add.to.contact.book",
            value: "Add to Contact Book",
            comment: "Text label for action button to add the contact to the address book")
    }
    
}
