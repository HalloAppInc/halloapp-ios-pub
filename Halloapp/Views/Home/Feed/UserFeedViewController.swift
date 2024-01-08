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

    private let dataSource: ProfileDataSource
    private let showHeader: Bool

    init(userId: UserID, showHeader: Bool = true) {
        self.userId = userId
        self.dataSource = ProfileDataSource(id: userId)
        self.showHeader = showHeader

        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    init(profile: DisplayableProfile) {
        userId = profile.displayable.id
        dataSource = ProfileDataSource(profile: profile)
        showHeader = true

        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userId: UserID
    private var profile: DisplayableProfile?
    private var cancellables = Set<AnyCancellable>()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        if isOwnFeed {
            title = Localizations.titleMyPosts
        }

        dataSource.$mutuals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.feedDataSource.refresh()
            }
            .store(in: &cancellables)

        setupMoreButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Analytics.openScreen(.userFeed)
    }

    override func setupCollectionView() {
        super.setupCollectionView()
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

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        guard let headerCell = collectionView.cellForItem(at: .init(row: 0, section: 0)) as? ProfileHeaderCollectionViewCell else {
            return
        }

        let offset = scrollView.contentOffset.y
        let scrolledLimit = headerCell.profileHeader.view.frame.size.height / 3.5
        var titleText = ""

        if offset > scrolledLimit {
            titleText = headerCell.profileHeader.name ?? ""
        }

        if title != titleText {
            title = titleText
        }
    }

    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var items = super.modifyItems(items)

        if !isOwnFeed, items.isEmpty, let name = profile?.displayable.name, let links = profile?.displayable.profileLinks, !links.isEmpty {
            items.insert(.profileLinks(name: name, links.sorted()), at: 0)
        } else if isOwnFeed, MainAppContext.shared.feedData.validMoment.value == nil {
            items.insert(.momentStack([.prompt]), at: 0)
        }

        if showHeader, let profile = dataSource.profile {
            if isOwnFeed {
                items.insert(.ownProfile(profile), at: 0)
            } else {
                items.insert(.profile(profile, dataSource.mutuals.friends, dataSource.mutuals.groups), at: 0)
            }
        }

        return items
    }
}

extension UserFeedViewController: CNContactViewControllerDelegate, ProfileHeaderDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        navigationController?.popViewController(animated: true)
    }

    func profileHeaderDidTapUnblock(_ profileHeader: ProfileHeaderViewController) {

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
