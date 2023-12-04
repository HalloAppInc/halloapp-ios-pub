//
//  SegmentedFriendsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

extension SegmentedFriendsViewController {

    enum State {
        case requests
        case friends
        case search

        fileprivate static var segmentedCases: [Self] {
            [.requests, .friends]
        }
    }
}

class SegmentedFriendsViewController: UIViewController {

    private var state: State = .requests {
        didSet { stateChanged() }
    }

    private let existingFriendsViewController: FriendsViewController = {
        let viewController = FriendsViewController(type: .existing)
        return viewController
    }()

    private let friendRequestsViewController: FriendsViewController = {
        let viewController = FriendsViewController(type: .incomingRequests)
        return viewController
    }()

    private let friendSearchViewController: FriendsViewController = {
        let viewController = FriendsViewController(type: .search)
        return viewController
    }()

    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl()
        return control
    }()

    init(initialState: State = .requests) {
        state = initialState
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("SegmentedFriendsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        for viewController in [existingFriendsViewController, friendRequestsViewController] {
            addChild(viewController)

            view.addSubview(viewController.view)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                viewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])

            viewController.didMove(toParent: self)
        }

        for (index, state) in State.segmentedCases.enumerated() {
            let title: String
            switch state {
            case .friends:
                title = Localizations.friendsTitle
            case .requests:
                title = Localizations.requestsTitle
            default:
                continue
            }

            segmentedControl.insertSegment(withTitle: title, at: index, animated: false)
        }

        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.selectedSegmentIndex = State.segmentedCases.firstIndex(of: state) ?? 0

        let controller = UISearchController(searchResultsController: friendSearchViewController)
        controller.delegate = self
        controller.searchBar.delegate = self

        let inviteButtonItem = UIBarButtonItem(title: Localizations.buttonInvite, primaryAction: .init { [weak self] _ in
            guard let self, ContactStore.contactsAccessAuthorized else {
                self?.present(UINavigationController(rootViewController: InvitePermissionDeniedViewController()), animated: true)
                return
            }

            InviteManager.shared.requestInvitesIfNecessary()
            let viewController = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
            self.present(UINavigationController(rootViewController: viewController), animated: true)
        })

        navigationItem.titleView = segmentedControl
        navigationItem.searchController = controller
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationController?.navigationBar.tintColor = .primaryBlue
        navigationItem.rightBarButtonItem = inviteButtonItem

        stateChanged()
    }

    @objc
    private func segmentChanged(_ control: UISegmentedControl) {
        guard control.selectedSegmentIndex < State.segmentedCases.count else {
            return
        }

        let selectedPage = State.segmentedCases[control.selectedSegmentIndex]
        state = selectedPage
    }

    private func stateChanged() {
        var hideRequests = true
        var hideFriends = true

        switch state {
        case .requests:
            hideRequests = false
        case .friends:
            hideFriends = false
        case .search:
            break
        }

        friendRequestsViewController.view.isHidden = hideRequests
        existingFriendsViewController.view.isHidden = hideFriends
    }
}

// MARK: - SegmentedFriendsViewController + UISearchControllerDelegate

extension SegmentedFriendsViewController: UISearchControllerDelegate, UISearchBarDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        state = .search
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        guard segmentedControl.selectedSegmentIndex < State.segmentedCases.count else {
            return
        }

        let selectedPage = State.segmentedCases[segmentedControl.selectedSegmentIndex]
        state = selectedPage
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.delegate?.searchBar?(searchBar, textDidChange: "")
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        friendSearchViewController.dataSource.search(using: searchText)
    }
}

// MARK: - Localization

extension Localizations {

    static var friendsTitle: String {
        NSLocalizedString("friends.title",
                          value: "Friends",
                          comment: "Indicating the user's friends.")
    }

    static var requestsTitle: String {
        NSLocalizedString("requests.title",
                          value: "Requests",
                          comment: "Indicating the user's friend requests.")
    }
}
