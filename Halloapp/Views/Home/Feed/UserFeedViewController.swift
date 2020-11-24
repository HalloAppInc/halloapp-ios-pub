//
//  UserFeedViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class UserFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    init(userId: UserID) {
        self.userId = userId
        super.init(title: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userId: UserID
    private var headerViewController: ProfileHeaderViewController!
    private var cancellables = Set<AnyCancellable>()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        headerViewController = ProfileHeaderViewController()
        if userId == MainAppContext.shared.userData.userId {
            title = Localizations.titleMyPosts
            headerViewController.isEditingAllowed = true
            cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
                guard let self = self else { return }
                self.headerViewController.configureForCurrentUser(withName: userName)
                self.viewIfLoaded?.setNeedsLayout()
            }))
        } else {
            headerViewController.configureWith(userId: userId)
        }

        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@ AND groupId == nil", userId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func shouldOpenFeed(for userId: UserID) -> Bool {
        return userId != self.userId
    }

    // MARK: Collection View Header

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader && indexPath.section == 0 {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier, for: indexPath)
            if let superView = headerViewController.view.superview, superView != headerView {
                headerViewController.willMove(toParent: nil)
                headerViewController.view.removeFromSuperview()
                headerViewController.removeFromParent()
            }
            if headerViewController.view.superview == nil {
                addChild(headerViewController)
                headerView.addSubview(headerViewController.view)
                headerView.preservesSuperviewLayoutMargins = true
                headerViewController.view.translatesAutoresizingMaskIntoConstraints = false
                headerViewController.view.constrain(to: headerView)
                headerViewController.didMove(toParent: self)
            }
            return headerView
        }
        return UICollectionReusableView()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard section == 0 else {
            return .zero
        }
        let targetSize = CGSize(width: collectionView.frame.width, height: UIView.layoutFittingCompressedSize.height)
        let headerSize = headerViewController.view.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return headerSize
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        var inset = layout.sectionInset
        if section == 0 {
            inset.top = 8
            inset.bottom = 20
        }
        return inset
    }
}
