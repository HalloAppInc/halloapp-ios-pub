//
//  ProfileView.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CoreData
import SwiftUI
import UIKit

class ProfileViewController: FeedTableViewController {

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "hammer"), style: .plain, target: self, action: #selector(presentDeveloperMenu)),
            UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(presentSettingsScreen)) ]
        self.navigationItem.largeTitleDisplayMode = .automatic

        let tableWidth = self.view.frame.size.width
        let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.frame.size.height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        self.tableView.tableHeaderView = headerView
    }

    // MARK: UI Actions

    @objc(presentDeveloperMenu)
    private func presentDeveloperMenu() {
        var developerMenuView = DeveloperMenuView()
        developerMenuView.dismiss = { self.dismiss(animated: true) }
        self.present(UIHostingController(rootView: developerMenuView), animated: true)
    }

    @objc(presentSettingsScreen)
    private func presentSettingsScreen() {
        var settingsView = SettingsView()
        settingsView.dismiss = { self.dismiss(animated: true) }
        self.present(UIHostingController(rootView: settingsView), animated: true)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", AppContext.shared.userData.userId)
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

    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = AppContext.shared.userData.name
        return label
    }()

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = AppContext.shared.userData.phone
        return label
    }()

    private func setupView() {
        self.layoutMargins.top = 16

        let vStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.nameLabel, self.textLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 8
        vStack.axis = .vertical
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true

        contactImageView.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }
}
