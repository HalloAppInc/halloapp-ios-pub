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
    private var headerView: GroupFeedHeaderView?
    
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

//        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
//            let headerView = GroupFeedHeaderView(frame: CGRect(origin: .zero, size: CGSize(width: collectionView.frame.width, height: collectionView.frame.width)))
//            headerView.configure(withGroup: group)
//            headerView.action = { [weak self] in
//                guard let self = self else { return }
//                self.navigationController?.pushViewController(GroupInfoViewController(for: self.groupId), animated: true)
//            }
//            self.headerView = headerView
//        }
//        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier)

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
        
        installFloatingActionMenu()
        
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

    // MARK: Collection View Header

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard let headerView = headerView, kind == UICollectionView.elementKindSectionHeader && indexPath.section == 0 else {
            return UICollectionReusableView()
        }

        let sectionHeaderView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier, for: indexPath)
        if let superView = headerView.superview, superView != sectionHeaderView {
            headerView.removeFromSuperview()
        }
        if headerView.superview == nil {
            sectionHeaderView.addSubview(headerView)
            sectionHeaderView.preservesSuperviewLayoutMargins = true
            headerView.translatesAutoresizingMaskIntoConstraints = false
            headerView.constrain(to: sectionHeaderView)
        }
        return sectionHeaderView
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard let headerView = headerView, section == 0 else {
            return .zero
        }
        let targetSize = CGSize(width: collectionView.frame.width, height: UIView.layoutFittingCompressedSize.height)
        let headerSize = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return headerSize
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        var inset = layout.sectionInset
        if section == 0 {
            inset.top = 20
            inset.bottom = 20
        }
        return inset
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

private class GroupFeedHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var avatarView: AvatarView!
    private var groupNameLabel: UILabel!
    private var groupParticipantCountLabel: UILabel!

    private var buttonIsHighlightedObservation: NSKeyValueObservation?

    var action: (() -> ())?

    private func commonInit() {
        preservesSuperviewLayoutMargins = true

        avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addConstraints([
            avatarView.widthAnchor.constraint(equalToConstant: 100),
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor)
        ])

        groupNameLabel = UILabel()
        groupNameLabel.numberOfLines = 0
        groupNameLabel.textAlignment = .center
        let headlineFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        groupNameLabel.font = UIFont(descriptor: headlineFontDescriptor, size: headlineFontDescriptor.pointSize + 1)

        groupParticipantCountLabel = UILabel()
        groupParticipantCountLabel.numberOfLines = 0
        groupParticipantCountLabel.textColor = .secondaryLabel
        groupParticipantCountLabel.textAlignment = .center
        groupParticipantCountLabel.font = .preferredFont(forTextStyle: .callout)

        let vStack = UIStackView(arrangedSubviews: [ avatarView, groupNameLabel, groupParticipantCountLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 8
        vStack.alignment = .center
        vStack.axis = .vertical
        vStack.isUserInteractionEnabled = false
        vStack.setCustomSpacing(12, after: avatarView)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(vStack)
        vStack.constrain(to: button)

        addSubview(button)
        let constraints = [
            button.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            button.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor) ]
        constraints.forEach({ $0.priority = .defaultHigh })
        addConstraints(constraints)

        button.addTarget(self, action: #selector(handleButtonTap(button:)), for: .touchUpInside)
        buttonIsHighlightedObservation = button.observe(\UIButton.isHighlighted) { (button, _) in
            vStack.alpha = button.isHighlighted ? 0.2 : 1
        }
    }

    func configure(withGroup group: ChatGroup) {
        avatarView.configure(groupId: group.groupId, using: MainAppContext.shared.avatarStore)
        groupNameLabel.text = group.name
        groupParticipantCountLabel.text = String.localizedStringWithFormat(NSLocalizedString("group.feed.n.members", comment: "Displays current group size in group feed screen"),
                                                                           group.members?.count ?? 0)
    }

    @objc private func handleButtonTap(button: UIButton) {
        button.isHighlighted = true
        DispatchQueue.main.async {
            self.action?()
            DispatchQueue.main.async {
                button.isHighlighted = false
            }
        }
    }
}
