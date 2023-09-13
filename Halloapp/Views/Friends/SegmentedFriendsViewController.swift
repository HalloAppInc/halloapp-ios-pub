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

    private enum State {
        case requests
        case friends
        case search

        static var segmentedCases: [Self] {
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

    private lazy var searchButtonItem: UIBarButtonItem = {
        UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"),
                        style: .plain,
                        target: self,
                        action: #selector(searchButtonTapped))
    }()

    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.showsCancelButton = true
        searchBar.tintColor = .primaryBlue
        return searchBar
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        for viewController in [friendSearchViewController ,existingFriendsViewController, friendRequestsViewController] {
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
        segmentedControl.selectedSegmentIndex = 0

        navigationController?.navigationBar.tintColor = .primaryBlue
        searchBar.delegate = self

        state = .requests
    }

    @objc
    private func segmentChanged(_ control: UISegmentedControl) {
        guard control.selectedSegmentIndex < State.segmentedCases.count else {
            return
        }

        let selectedPage = State.segmentedCases[control.selectedSegmentIndex]
        state = selectedPage
    }

    @objc
    private func searchButtonTapped(_ buttonItem: UIBarButtonItem) {
        state = .search
        searchBar.becomeFirstResponder()
    }

    private func stateChanged() {
        var titleView: UIView = segmentedControl
        var rightButtonItem: UIBarButtonItem? = searchButtonItem

        var hideRequests = true
        var hideFriends = true
        var hideSearch = true

        switch state {
        case .requests:
            hideRequests = false
        case .friends:
            hideFriends = false
        case .search:
            hideSearch = false
            titleView = searchBar
            rightButtonItem = nil
        }

        navigationItem.titleView = titleView
        navigationItem.rightBarButtonItem = rightButtonItem

        friendRequestsViewController.view.isHidden = hideRequests
        existingFriendsViewController.view.isHidden = hideFriends
        friendSearchViewController.view.isHidden = hideSearch
    }
}

// MARK: - UISearchbarDelegate methods

extension SegmentedFriendsViewController: UISearchBarDelegate {

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        guard segmentedControl.selectedSegmentIndex < State.segmentedCases.count else {
            return
        }

        searchBar.text = ""
        searchBar.delegate?.searchBar?(searchBar, textDidChange: "")

        let selectedPage = State.segmentedCases[segmentedControl.selectedSegmentIndex]
        state = selectedPage
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
