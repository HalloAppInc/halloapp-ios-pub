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

        var rightBarButtonItems = [ UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(presentSettingsScreen)) ]
        #if INTERNAL
        rightBarButtonItems.insert(UIBarButtonItem(image: UIImage(systemName: "hammer"), style: .plain, target: self, action: #selector(presentDeveloperMenu)), at: 0)
        #endif

        self.navigationItem.rightBarButtonItems = rightBarButtonItems
        self.navigationItem.largeTitleDisplayMode = .automatic

        let tableWidth = self.view.frame.size.width
        let headerView = FeedTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableWidth, height: tableWidth))
        headerView.frame.size.height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        self.tableView.tableHeaderView = headerView
        
        let headerTapGesture = UITapGestureRecognizer(target: self, action: #selector(presentProfileEditScreen))
        headerView.addGestureRecognizer(headerTapGesture)
    }

    // MARK: UI Actions

    @objc(presentDeveloperMenu)
    private func presentDeveloperMenu() {
        let developerMenuView = DeveloperMenuView(useTestServer: AppContext.shared.userData.useTestServer, dismiss: { self.dismiss(animated: true) })
        self.present(UIHostingController(rootView: developerMenuView), animated: true)
    }

    @objc(presentSettingsScreen)
    private func presentSettingsScreen() {
        var settingsView = SettingsView()
        settingsView.dismiss = { self.dismiss(animated: true) }
        self.present(UIHostingController(rootView: settingsView), animated: true)
    }
    
    @objc(presentProfileEditScreen)
    private func presentProfileEditScreen() {
        var profileEditView = ProfileEditView()
        profileEditView.dismiss = {
            (self.tableView.tableHeaderView as! FeedTableHeaderView).updateNameLabelAndEditProfileIcon()
            self.dismiss(animated: true)
        }
        
        self.present(UIHostingController(rootView: profileEditView), animated: true)
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
        label.text = AppContext.shared.userData.formattedPhoneNumber 
        return label
    }()
    
    private lazy var editProfileIconImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "pencil"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()
    
    private var iconHorizontalConstraint: NSLayoutConstraint?
    
    public func updateNameLabelAndEditProfileIcon() {
        if (nameLabel.text! != AppContext.shared.userData.name) {
            nameLabel.text = AppContext.shared.userData.name
        }
        
        /*
         nameLabel is wider than the text inside.
         We need to get the actual width of the text and calculate the relative distance.
         */
        let iconDistanceToNameLabelCenterX = nameLabel.intrinsicContentSize.width / 2 + 8
        
        if let hConstraint = iconHorizontalConstraint {
            hConstraint.constant = iconDistanceToNameLabelCenterX
        } else {
            iconHorizontalConstraint = NSLayoutConstraint(item: editProfileIconImageView, attribute: .leading, relatedBy: .equal, toItem: nameLabel, attribute: .centerX, multiplier: 1, constant: iconDistanceToNameLabelCenterX)
            let iconVerticalConstraint = NSLayoutConstraint(item: editProfileIconImageView, attribute: .centerY, relatedBy: .equal, toItem: nameLabel, attribute: .centerY, multiplier: 1, constant: 0)
            
            self.addConstraints([iconHorizontalConstraint!, iconVerticalConstraint])
        }
    }

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
        
        self.addSubview(editProfileIconImageView)
        self.updateNameLabelAndEditProfileIcon()
    }
}
