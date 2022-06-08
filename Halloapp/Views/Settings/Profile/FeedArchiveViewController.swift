//
//  FeedArchiveViewController.swift
//  HalloApp
//
//  Created by Tanveer on 4/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class FeedArchiveViewController: UIViewController {
    
    enum State: Int {
        case feed = 0, archive = 1
    }
    
    var state: State = .feed {
        didSet {
            if oldValue != state { updateState() }
        }
    }
    
    let userID = MainAppContext.shared.userData.userId
    private lazy var container: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var segmentedControl: UISegmentedControl = {
        let images = [UIImage(named: "Posts"), UIImage(systemName: "clock.arrow.circlepath")]
        let control = UISegmentedControl(items: images as [Any])
        
        control.setWidth(100, forSegmentAt: 0)
        control.setWidth(100, forSegmentAt: 1)
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        
        return control
    }()
    
    private lazy var feedViewController = UserFeedViewController(userId: MainAppContext.shared.userData.userId, showHeader: false)
    private lazy var archiveViewController = ArchiveViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
                
        installControl()
        installFeed()
        installArchive()
        
        updateState()
    }

    private func installControl() {
        view.addSubview(container)
        container.backgroundColor = .primaryBg
        
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(segmentedControl)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            segmentedControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
    }
    
    private func installFeed() {
        view.addSubview(feedViewController.view)
        
        feedViewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(feedViewController)
        feedViewController.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            feedViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedViewController.view.topAnchor.constraint(equalTo: container.bottomAnchor),
            feedViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func installArchive() {
        view.addSubview(archiveViewController.view)
        
        archiveViewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(archiveViewController)
        archiveViewController.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            archiveViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            archiveViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            archiveViewController.view.topAnchor.constraint(equalTo: container.bottomAnchor),
            archiveViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    @objc
    private func segmentChanged(_ control: UISegmentedControl) {
        if let newState = State(rawValue: control.selectedSegmentIndex) {
            state = newState
        }
    }
    
    private func updateState() {
        switch state {
        case .feed:
            title = Localizations.titleMyPosts
            feedViewController.view.isHidden = false
            archiveViewController.view.isHidden = true
        case .archive:
            title = Localizations.archive
            feedViewController.view.isHidden = true
            archiveViewController.view.isHidden = false
        }
        
        segmentedControl.selectedSegmentIndex = state.rawValue
    }
}

// MARK: - localization

extension Localizations {
    static var archive: String {
        NSLocalizedString("profile.row.archive",
                   value: "Archive",
                 comment: "Row in Profile screen.")
    }
}
