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

class UserFeedViewController: FeedTableViewController {

    init(userID: UserID) {
        self.userID = userID
        let displayName = MainAppContext.shared.contactStore.fullName(for: userID)
        super.init(title: displayName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userID: UserID

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        let tableWidth = view.frame.width
        let headerView = UserProfileTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.isDisplayingName = false
        tableView.tableHeaderView = headerView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let tableHeaderView = tableView.tableHeaderView as? UserProfileTableHeaderView {
            tableHeaderView.updateProfile(userID: userID)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update header's height: necessary when user changes text size setting.
        if let headerView = tableView.tableHeaderView {
            var targetSize = UIView.layoutFittingCompressedSize
            targetSize.width = tableView.bounds.width
            let headerViewHeight = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            if headerView.bounds.height != headerViewHeight {
                headerView.bounds.size.height = headerViewHeight
                tableView.tableHeaderView = headerView
            }
        }
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func shouldOpenFeed(for userID: UserID) -> Bool {
        return userID != self.userID
    }
}
