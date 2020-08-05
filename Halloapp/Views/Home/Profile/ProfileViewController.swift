//
//  ProfileView.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class ProfileViewController: FeedTableViewController {

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()

        var rightBarButtonItems = [ UIBarButtonItem(image: UIImage(named: "NavbarSettings"), style: .plain, target: self, action: #selector(presentSettingsScreen)) ]
        #if DEBUG
        let showDeveloperMenu = true
        #else
        let showDeveloperMenu = ServerProperties.isInternalUser
        #endif
        if showDeveloperMenu {
            rightBarButtonItems.append(UIBarButtonItem(image: UIImage(systemName: "hammer"), style: .plain, target: self, action: #selector(presentDeveloperMenu)))
        }

        self.navigationItem.rightBarButtonItems = rightBarButtonItems

        let tableWidth = self.view.frame.size.width
        let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.frame.size.height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        self.tableView.tableHeaderView = headerView
        
        let headerTapGesture = UITapGestureRecognizer(target: self, action: #selector(presentProfileEditScreen))
        headerView.addGestureRecognizer(headerTapGesture)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let tableHeaderView = self.tableView.tableHeaderView as? FeedTableHeaderView {
            tableHeaderView.updateProfile()
        }
    }

    // MARK: UI Actions

    @objc(presentDeveloperMenu)
    private func presentDeveloperMenu() {
        let developerMenuView = DeveloperMenuView(useTestServer: MainAppContext.shared.userData.useTestServer, dismiss: { self.dismiss(animated: true) })
        self.present(UIHostingController(rootView: developerMenuView), animated: true)
    }

    @objc(presentSettingsScreen)
    private func presentSettingsScreen() {
        let viewController = UIHostingController(rootView: SettingsView())
        viewController.hidesBottomBarWhenPushed = true
        self.navigationController?.pushViewController(viewController, animated: true)
    }
    
    @objc(presentProfileEditScreen)
    private func presentProfileEditScreen() {
        var profileEditView = ProfileEditView()
        profileEditView.dismiss = { self.navigationController?.popViewController(animated: true) }
        self.navigationController?.pushViewController(UIHostingController(rootView: profileEditView), animated: true)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId == %@", MainAppContext.shared.userData.userId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    override func shouldOpenFeed(for userID: UserID) -> Bool {
        return userID != MainAppContext.shared.userData.userId
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

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = MainAppContext.shared.userData.name
        return label
    }()

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = MainAppContext.shared.userData.formattedPhoneNumber
        return label
    }()
    
    private lazy var editProfileIconImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "pencil"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()
    
    private lazy var nameView: UIView = {
        let view = UIView()
        
        view.addSubview(nameLabel)
        view.addSubview(editProfileIconImageView)
        
        view.heightAnchor.constraint(equalTo: editProfileIconImageView.heightAnchor, multiplier: 1).isActive = true
        nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor).isActive = true
        nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        editProfileIconImageView.leadingAnchor.constraint(equalToSystemSpacingAfter: nameLabel.trailingAnchor, multiplier: 1).isActive = true
        editProfileIconImageView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor).isActive = true
        
        return view
    }()
    
    public func updateProfile() {
        nameLabel.text = MainAppContext.shared.userData.name
        contactImageView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
    }

    private func setupView() {
        self.layoutMargins.top = 16

        let vStack = UIStackView(arrangedSubviews: [ self.contactImageView, self.nameView, self.textLabel ])
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
        
        contactImageView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
    }
}
