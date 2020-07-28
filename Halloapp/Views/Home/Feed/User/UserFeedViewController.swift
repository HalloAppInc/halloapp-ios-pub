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

        let tableWidth = self.view.frame.size.width
        let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.frame.size.height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        self.tableView.tableHeaderView = headerView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let tableHeaderView = self.tableView.tableHeaderView as? FeedTableHeaderView {
            tableHeaderView.updateProfile(userID: userID)
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
}


fileprivate class FeedTableHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    public func updateProfile(userID: UserID) {
        contactImageView.configure(with: userID, using: MainAppContext.shared.avatarStore)
    }

    private func setupView() {
        self.layoutMargins.top = 16

        let vStack = UIStackView(arrangedSubviews: [ self.contactImageView ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 8
        vStack.axis = .vertical
        vStack.alignment = .center
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        contactImageView.heightAnchor.constraint(equalToConstant: 50).isActive = true
        contactImageView.widthAnchor.constraint(equalToConstant: 50).isActive = true
    }
}
