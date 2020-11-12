//
//  GroupFeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

class GroupFeedViewController: FeedTableViewController {

    private let groupId: GroupID

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

        if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
            let tableHeaderView = GroupFeedTableHeaderView(frame: CGRect(origin: .zero, size: CGSize(width: tableView.frame.width, height: tableView.frame.width)))
            tableHeaderView.configure(withGroup: group)
            tableHeaderView.action = { [weak self] in
                guard let self = self else { return }
                self.navigationController?.pushViewController(GroupInfoViewController(for: self.groupId), animated: true)
            }
            tableView.tableHeaderView = tableHeaderView
        }

        installFloatingActionMenu()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let tableHeaderView = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.frame.width, height: UIView.layoutFittingCompressedSize.height)
            let headerSize = tableHeaderView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            if tableHeaderView.frame.size != headerSize {
                tableHeaderView.frame.size = headerSize
                tableView.tableHeaderView = tableHeaderView
            }
        }
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

        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: floatingMenu.suggestedContentInsetHeight, right: 0)
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source, destination: .groupFeed(groupId)) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "groupId == %@", groupId)
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

}

private class GroupFeedTableHeaderView: UIView {

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
            button.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
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
