//
//  ReactionListViewController.swift
//  HalloApp
//
//  Created by Vaishvi Patel on 7/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Core

protocol ReactionListViewControllerDelegate: AnyObject {
    func removeReaction(reaction: CommonReaction)
}

class ReactionListViewController: UITableViewController {

    var chatMessage: ChatMessage?
    var feedPostComment: FeedPostComment?
    
    var sortedReactionsList: [CommonReaction]
    
    let contactImage: AvatarView = {
        return AvatarView()
    }()
    
    let cellReuseIdentifier = "ReactionContactCell"
    
    weak var delegate: ReactionListViewControllerDelegate?

    required init(chatMessage: ChatMessage) {
        self.chatMessage = chatMessage
        self.sortedReactionsList = chatMessage.sortedReactionsList
        super.init(style: .insetGrouped)
    }
    
    required init(feedPostComment: FeedPostComment) {
        self.feedPostComment = feedPostComment
        self.sortedReactionsList = feedPostComment.sortedReactionsList
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("title.your.post", value: "Reactions", comment: "Title for the screen with information about who reacted to your post.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))
        
        tableView.register(ReactionTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.backgroundColor = UIColor.primaryBg
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedReactionsList.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ReactionTableViewCell
        cell.selectionStyle = .default
        let reaction = sortedReactionsList[indexPath.row]
        cell.configureWithReaction(reaction, using: MainAppContext.shared.avatarStore)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let delegate = delegate else {
            return
        }
        let reaction = sortedReactionsList[indexPath.row]
        if reaction.fromUserID == AppContext.shared.userData.userId {
            delegate.removeReaction(reaction: reaction)
            dismiss(animated: true)
        }
    }
    
    @objc private func closeAction() {
        dismiss(animated: true)
    }
}

private class ReactionTableViewCell: ContactTableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
        accessoryLabel.font = UIFont.scaledSystemFont(ofSize: 24)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureWithReaction(_ reaction: CommonReaction, using avatarStore: AvatarStore) {
        let contactStore = MainAppContext.shared.contactStore

        contactImage.configure(with: reaction.fromUserID, using: avatarStore)
        
        nameLabel.text = contactStore.fullName(for: reaction.fromUserID, in: contactStore.viewContext)
        if reaction.fromUserID == AppContext.shared.userData.userId {
            subtitleLabel.text = "Tap to remove"
        }
        accessoryLabel.text = reaction.emoji
    }
}
