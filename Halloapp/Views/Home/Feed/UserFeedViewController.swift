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

    private let dataSource: ProfileDataSource

    init(userId: UserID, showHeader: Bool = true) {
        self.userId = userId
        self.isUserBlocked = false
        self.dataSource = ProfileDataSource(id: userId)

        if showHeader {
            let configuration: ProfileHeaderViewController.Configuration = userId == MainAppContext.shared.userData.userId ? .ownProfile : .default
            headerViewController = ProfileHeaderViewController(configuration: configuration)
        } else {
            headerViewController = nil
        }

        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    init(profile: DisplayableProfile) {
        userId = profile.id
        isUserBlocked = profile.isBlocked
        dataSource = ProfileDataSource(profile: profile)

        let configuration: ProfileHeaderViewController.Configuration = userId == MainAppContext.shared.userData.userId ? .ownProfile : .default
        headerViewController = ProfileHeaderViewController(configuration: configuration)

        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userId: UserID
    private var profile: DisplayableProfile?
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

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()
        let profile = UserProfile.find(with: userId, in: MainAppContext.shared.mainDataStore.viewContext)

        if isOwnFeed {
            title = Localizations.titleMyPosts
        }

        let publisher = dataSource.$profile
            .compactMap { $0 }
            .eraseToAnyPublisher()
        headerViewController?.configure(with: publisher)
        setupMoreButton()

        dataSource.$profile
            .dropFirst()
            .sink { [weak self] in
                guard let self else {
                    return
                }
                self.profile = $0
                self.feedDataSource.refresh()
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Analytics.openScreen(.userFeed)
    }

    override func setupCollectionView() {
        super.setupCollectionView()
        
        headerViewController?.delegate = self

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
            HAMenu.menu(for: userId, options: [.commonGroups, .favorite, .block, .report]) { [weak self] action, userID in
                try? await self?.handle(action, for: userID)
            }
        }
    }

    override func showGroupName() -> Bool {
        return true
    }

    private var isOwnFeed: Bool {
        return MainAppContext.shared.userData.userId == userId
    }
    
    // MARK: FeedCollectionViewController

    override func shouldOpenFeed(for userId: UserID) -> Bool {
        return userId != self.userId
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
            let header = headerViewController
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

    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var items = super.modifyItems(items)
        if !isOwnFeed, items.isEmpty, let name = profile?.name, let links = profile?.profileLinks, !links.isEmpty {
            items.insert(.profileLinks(name: name, links.sorted()), at: 0)
        } else if isOwnFeed, MainAppContext.shared.feedData.validMoment.value == nil {
            items.insert(.momentStack([.prompt]), at: 0)
        }

        return items
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
