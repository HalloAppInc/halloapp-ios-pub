//
//  FeedPermissionDeniedController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import UIKit

class FeedPermissionDeniedController: UIViewController {

    private var cancellables: Set<AnyCancellable> = []
    private var notificationButton: BadgedButton?

    private var notificationCount: Int = 0 {
        didSet {
            updateNotificationCount(notificationCount)
        }
    }

    init(title: String?) {
        super.init(nibName: nil, bundle: nil)
        super.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground
        installLargeTitleUsingGothamFont()

        let contactsPermissionView = UpdateContactsPermissionView()
        view.addSubview(contactsPermissionView)
        contactsPermissionView.translatesAutoresizingMaskIntoConstraints = false
        // Put empty view behind collection view in case it contains NUX header
        view.sendSubviewToBack(contactsPermissionView)
        contactsPermissionView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8).isActive = true
        contactsPermissionView.constrain([.centerX, .centerY], to: view)
        
        let notificationButton = BadgedButton(type: .system)
        notificationButton.centerYConstant = 5
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications")?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal), for: .normal)
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(didTapNotificationButton), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: notificationButton)
        self.notificationButton = notificationButton

        // We need this here to show/hide the badge on the activity center button
        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationCount = feedNotifications.unreadCount
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { [weak self] (unreadCount) in
                self?.notificationCount = unreadCount
            })
        }
    }
    
    private func updateNotificationCount(_ unreadCount: Int) {
        notificationButton?.isBadgeHidden = unreadCount == 0
        //TODO(@dini)Ask if nux is needed in this view: showNUXIfNecessary()
    }

    // MARK: UI Actions

    @objc private func didTapNotificationButton() {
        self.present(UINavigationController(rootViewController: NotificationsViewController()), animated: true)
    }
}
