//
//  GroupFeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreData
import UIKit

class GroupFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    private let groupId: GroupID
    
    private var currentUnreadThreadGroupCount = 0
    private var currentUnseenGroupFeedList: [GroupID: Int] = [:]
    
    private var cancellableSet: Set<AnyCancellable> = []

    init(groupId: GroupID) {
        self.groupId = groupId
        super.init(title: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let navAppearance = UINavigationBarAppearance()
        navAppearance.backgroundColor = UIColor.feedBackground
        navAppearance.shadowColor = nil
        navAppearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
        navigationItem.standardAppearance = navAppearance
        navigationItem.scrollEdgeAppearance = navAppearance
        navigationItem.compactAppearance = navAppearance
        
        NSLayoutConstraint.activate([
            titleView.widthAnchor.constraint(equalToConstant: (view.frame.width*0.8))
        ])
        
        navigationItem.titleView = titleView
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        titleView.delegate = self
        
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupFeed.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard groupID != self.groupId else { return }
                
                if self.currentUnseenGroupFeedList[groupID] == nil {
                    self.currentUnseenGroupFeedList[groupID] = 1
                } else {
                    self.currentUnseenGroupFeedList[groupID]? += 1
                }
                
                DispatchQueue.main.async {
                    self.updateBackButtonUnreadCount(num: self.currentUnseenGroupFeedList.count)
                }
            }
        )
        
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        titleView.update(with: groupId, isFeedView: true)
        
        navigationController?.navigationBar.tintColor = .primaryBlue
        
        MainAppContext.shared.chatData.syncGroupIfNeeded(for: groupId)
        UNUserNotificationCenter.current().removeDeliveredChatNotifications(groupId: groupId)
        
        if MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil {
            installFloatingActionMenu()
        } else {
            removeFloatingActionMenu()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.navigationBar.tintColor = .label
        navigationController?.navigationBar.backItem?.backBarButtonItem = UIBarButtonItem()
    }
    
    override func showGroupName() -> Bool {
        return false
    }
    
    private lazy var titleView: GroupTitleView = {
        let titleView = GroupTitleView()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        return titleView
    }()
    
    private func updateBackButtonUnreadCount(num: Int) {
        let backButton = UIBarButtonItem()
        backButton.title = num > 0 ? String(num) : " \u{00a0}"

        navigationController?.navigationBar.backItem?.backBarButtonItem = backButton
    }
    
    // MARK: New post

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                expandedRotation: 45),
            expandedButtons: [
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityCamera,
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityTextPost,
                    action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            ]
        )
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        collectionView.contentInset.bottom = floatingMenu.suggestedContentInsetHeight
    }
    
    private func removeFloatingActionMenu() {
        floatingMenu.removeFromSuperview()
    }
    
    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source, destination: .groupFeed(groupId)) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: FeedCollectionViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "groupId == %@", groupId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

}

// MARK: Title View Delegates
extension GroupFeedViewController: GroupTitleViewDelegate {

    func groupTitleViewRequestsOpenGroupInfo(_ groupTitleView: GroupTitleView) {
        let vc = GroupInfoViewController(for: groupId)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    func groupTitleViewRequestsOpenGroupFeed(_ groupTitleView: GroupTitleView) {
        if MainAppContext.shared.chatData.chatGroup(groupId: groupId) != nil {
            let vc = GroupFeedViewController(groupId: groupId)
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}
