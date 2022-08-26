//
//  ReactionViewController.swift
//  HalloApp
//
//  Created by Vaishvi Patel on 6/17/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Core
import CoreCommon
import CocoaLumberjackSwift

protocol ReactionViewControllerChatDelegate: AnyObject {
    func handleMessageSave(_ reactionViewController: ReactionViewController, chatMessage: ChatMessage)
    func handleQuotedReply(msg chatMessage: ChatMessage)
    func handleForwarding(msg chatMessage: ChatMessage)
    func showDeletionConfirmationMenu(for chatMessage: ChatMessage)
    func sendReaction(chatMessage: ChatMessage, reaction: String)
    func removeReaction(chatMessage: ChatMessage, reaction: CommonReaction)
}

protocol ReactionViewControllerCommentDelegate: AnyObject {
    func handleQuotedReply(comment: FeedPostComment)
    func showDeletionConfirmationMenu(for feedPostComment: FeedPostComment)
    func sendReaction(feedPostComment: FeedPostComment, reaction: String)
    func removeReaction(feedPostComment: FeedPostComment, reaction: CommonReaction)
}

public class ReactionViewController: UIViewController {
    
    var chatMessage: ChatMessage?
    var feedPostComment: FeedPostComment?
    
    var messageViewCell: UIView
    var isOwnMessage: Bool
    var currentReaction: CommonReaction?
    
    weak var chatDelegate: ReactionViewControllerChatDelegate?
    weak var commentDelegate: ReactionViewControllerCommentDelegate?
    
    let iconConfig = UIImage.SymbolConfiguration(pointSize: 25, weight: .light)
    
    private lazy var backgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTap)))
        backgroundView.backgroundColor = .black.withAlphaComponent(0.3)
        backgroundView.alpha = 0
        return backgroundView
    }()
    
    private lazy var toolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.backgroundColor = .primaryBg
        toolbar.translatesAutoresizingMaskIntoConstraints = false;
        return toolbar
    }()
    
    private lazy var emojiStack: UIStackView = {
        let emojiStack = UIStackView()
        let defaultReactions = ["👍", "❤️", "👏", "🙏", "😢", "😮", "😂"]

        for reaction in defaultReactions {
            var selected = false
            if let currentReaction = currentReaction {
                selected = currentReaction.emoji == reaction
            }
            
            let emojiView = EmojiView(reaction: reaction, selected: selected)
            emojiView.translatesAutoresizingMaskIntoConstraints = false
            emojiView.alpha = 0
            emojiView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            let emojiTap = UITapGestureRecognizer(target: self, action: #selector(emojiTap(_:)))
            emojiView.addGestureRecognizer(emojiTap)
            emojiStack.addArrangedSubview(emojiView)
        }
        emojiStack.distribution = .fillEqually
        emojiStack.axis = .horizontal
        emojiStack.spacing = 3
        emojiStack.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        emojiStack.isLayoutMarginsRelativeArrangement = true
        emojiStack.layer.cornerRadius = 24
        emojiStack.alpha = 0
        return emojiStack
    }()
    
    private lazy var gradientLayer: CAGradientLayer = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.reactionGradientBgTop.cgColor, UIColor.reactionGradientBgBottom.cgColor]
        gradientLayer.cornerRadius = emojiStack.layer.cornerRadius
        emojiStack.layer.insertSublayer(gradientLayer, at: 0)
        return gradientLayer
    }()
    
    init(messageViewCell: UIView, chatMessage: ChatMessage) {
        self.messageViewCell = messageViewCell
        self.chatMessage = chatMessage
        self.isOwnMessage = chatMessage.fromUserID == MainAppContext.shared.userData.userId
        self.currentReaction = chatMessage.sortedReactionsList.filter { $0.fromUserID == MainAppContext.shared.userData.userId }.last
        
        super.init(nibName: nil, bundle: nil)
        
        configureMessageToolbar(chatMessage: chatMessage)
    }
    
    init(messageViewCell: UIView, feedPostComment: FeedPostComment) {
        self.messageViewCell = messageViewCell
        self.feedPostComment = feedPostComment
        self.isOwnMessage = feedPostComment.userID == MainAppContext.shared.userData.userId
        self.currentReaction = feedPostComment.sortedReactionsList.filter { $0.fromUserID == MainAppContext.shared.userData.userId }.last
        
        super.init(nibName: nil, bundle: nil)

        configureCommentToolbar(feedPostComment: feedPostComment)

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createMenuButton(imageName: String, labelName: String) -> UIControl {
        let config = UIImage.SymbolConfiguration(pointSize: 25, weight: .light)
        let image = UIImage(systemName: imageName, withConfiguration: config)
        let button = LabeledIconButton(image: image, title: labelName)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 55).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 65).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = true
        return button
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.constrain(to: view)
        
        view.addSubview(messageViewCell)
        messageViewCell.alpha = 0
        messageViewCell.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        
        let isChatReaction = chatMessage != nil && ServerProperties.chatReactions
        let isCommentReaction = feedPostComment != nil && ServerProperties.commentReactions
        if (isChatReaction || isCommentReaction) {
            view.addSubview(emojiStack)
            emojiStack.translatesAutoresizingMaskIntoConstraints = false
            if(isOwnMessage) {
                emojiStack.trailingAnchor.constraint(equalTo: messageViewCell.trailingAnchor).isActive = true
            } else {
                emojiStack.leadingAnchor.constraint(equalTo: messageViewCell.leadingAnchor).isActive = true
            }
            if(messageViewCell.frame.maxY < messageViewCell.frame.height + 80) {
                emojiStack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 20).isActive = true
            } else {
                emojiStack.bottomAnchor.constraint(equalTo: messageViewCell.topAnchor, constant: -8).isActive = true
            }
        }
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 75)
        ])

    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut, animations: {
            self.backgroundView.alpha = 1
            self.messageViewCell.alpha = 1
            self.messageViewCell.transform = .identity
            self.emojiStack.alpha = 1
            for i in 0...6 {
                self.emojiStack.arrangedSubviews[i].alpha = 1
                self.emojiStack.arrangedSubviews[i].transform = .identity
            }
        }, completion: nil)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = emojiStack.bounds
    }
    
    private func configureMessageToolbar(chatMessage: ChatMessage) {
        var items = [UIBarButtonItem]()
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if chatMessage.incomingStatus != .retracted {
            items.append(space)
            if let media = chatMessage.media, !media.isEmpty {
                let saveAllButton = createMenuButton(imageName: "square.and.arrow.down", labelName: Localizations.buttonSave)
                saveAllButton.addTarget(self, action: #selector(handleSaveAll), for: .touchUpInside)
                items.append(UIBarButtonItem(customView: saveAllButton))
                items.append(space)
            }
            
            let replyButton = createMenuButton(imageName: "arrowshape.turn.up.left", labelName: Localizations.messageReply)
            replyButton.addTarget(self, action: #selector(handleReply), for: .touchUpInside)
            items.append(UIBarButtonItem(customView: replyButton))
            items.append(space)

            let forwardButton = createMenuButton(imageName: "arrowshape.turn.up.right", labelName: Localizations.messageForward)
            forwardButton.addTarget(self, action: #selector(handleForwarding), for: .touchUpInside)
            if AppContext.shared.userDefaults.bool(forKey: "enableChatForwarding") {
                items.append(UIBarButtonItem(customView: forwardButton))
                items.append(space)
            }

            if let messageText = chatMessage.rawText, !messageText.isEmpty {
                let copyButton = createMenuButton(imageName: "doc.on.doc", labelName: Localizations.messageCopy)
                copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
                items.append(UIBarButtonItem(customView: copyButton))
                items.append(space)
            }

            let deleteButton = createMenuButton(imageName: "trash", labelName: Localizations.messageDelete)
            deleteButton.addTarget(self, action: #selector(handleDelete), for: .touchUpInside)
            items.append(UIBarButtonItem(customView: deleteButton))
            items.append(space)
        }
        guard items.count > 0 else { return }
        toolbar.setItems(items, animated: false)
    }
    
    private func configureCommentToolbar(feedPostComment: FeedPostComment) {
        var items = [UIBarButtonItem]()
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if feedPostComment.status != .retracted {
            items.append(space)
            
            let replyButton = createMenuButton(imageName: "arrowshape.turn.up.left", labelName: Localizations.commentReply)
            replyButton.addTarget(self, action: #selector(handleReply), for: .touchUpInside)
            items.append(UIBarButtonItem(customView: replyButton))
            items.append(space)
            
            if isOwnMessage {
                let deleteButton = createMenuButton(imageName: "trash", labelName: Localizations.messageDelete)
                deleteButton.addTarget(self, action: #selector(handleDelete), for: .touchUpInside)
                items.append(UIBarButtonItem(customView: deleteButton))
                items.append(space)
            }
        }
        guard items.count > 0 else { return }
        toolbar.setItems(items, animated: false)
    }
    
    @objc
    private func dismissTap(_ gesture: UITapGestureRecognizer) {
        dismiss(animated: true)
    }
    
    @objc
    private func emojiTap(_ gesture: UITapGestureRecognizer) {
        guard let emojiView = gesture.view as? EmojiView else {
            return
        }
        if let delegate = chatDelegate, let chatMessage = chatMessage {
            guard let currentReaction = currentReaction else {
                emojiView.selectEmoji()
                dismiss(animated:true)
                delegate.sendReaction(chatMessage: chatMessage, reaction: emojiView.reaction)
                return
            }
            if emojiView.reaction == currentReaction.emoji {
                emojiView.deselectEmoji()
                dismiss(animated:true)
                delegate.removeReaction(chatMessage: chatMessage, reaction: currentReaction)
            } else {
                emojiView.selectEmoji()
                dismiss(animated:true)
                delegate.removeReaction(chatMessage: chatMessage, reaction: currentReaction)
                delegate.sendReaction(chatMessage: chatMessage, reaction: emojiView.reaction)
            }
        } else if let delegate = commentDelegate, let feedPostComment = feedPostComment {
            guard let currentReaction = currentReaction else {
                emojiView.selectEmoji()
                dismiss(animated:true)
                delegate.sendReaction(feedPostComment: feedPostComment, reaction: emojiView.reaction)
                return
            }
            if emojiView.reaction == currentReaction.emoji {
                emojiView.deselectEmoji()
                dismiss(animated:true)
                delegate.removeReaction(feedPostComment: feedPostComment, reaction: currentReaction)
            } else {
                emojiView.selectEmoji()
                dismiss(animated:true)
                delegate.removeReaction(feedPostComment: feedPostComment, reaction: currentReaction)
                delegate.sendReaction(feedPostComment: feedPostComment, reaction: emojiView.reaction)
            }
        } else {
            DDLogError("ReactionViewController/emojiTap/ no comment or chat messsage")
            return
        }
    
        
    }

    @objc
    private func handleSaveAll() {
        guard let delegate = chatDelegate, let chatMessage = chatMessage else {
            return
        }
        dismiss(animated: true)
        delegate.handleMessageSave(self, chatMessage: chatMessage)
    }
    
    @objc
    private func handleReply() {

        if let chatMessage = chatMessage {
            guard let delegate = chatDelegate else {
                return
            }
            dismiss(animated: true)
            delegate.handleQuotedReply(msg: chatMessage)
        } else if let feedPostComment = feedPostComment {
            guard let delegate = commentDelegate else {
                return
            }
            dismiss(animated: true)
            delegate.handleQuotedReply(comment: feedPostComment)
        } else {
            DDLogError("ReactionViewController/handleReply/ no comment or chat messsage")
            return
        }
    }

    @objc
    private func handleForwarding() {
        guard let chatMessage = chatMessage, let delegate = chatDelegate else {
            return
        }
        dismiss(animated: true)
        delegate.handleForwarding(msg: chatMessage)
    }
    
    @objc
    private func handleCopy() {
        guard let chatMessage = chatMessage else {
            return
        }
        if let messageText = chatMessage.rawText, !messageText.isEmpty {
            let pasteboard = UIPasteboard.general
            pasteboard.string = messageText
        }
        dismiss(animated: true)
    }
    
    @objc
    private func handleDelete() {
        if let chatMessage = chatMessage {
            guard let delegate = chatDelegate else {
                return
            }
            dismiss(animated: true)
            delegate.showDeletionConfirmationMenu(for: chatMessage)
        } else if let feedPostComment = feedPostComment {
            guard let delegate = commentDelegate else {
                return
            }
            dismiss(animated: true)
            delegate.showDeletionConfirmationMenu(for: feedPostComment)
        } else {
            DDLogError("ReactionViewController/handleDelete/ no comment or chat messsage")
            return
        }
    }
}


private class EmojiView: CircleView {
    var reaction: String
    var selected: Bool
    
    private lazy var emojiLabel: UILabel = {
        let emojiLabel = UILabel()
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.text = reaction
        emojiLabel.numberOfLines = 1
        emojiLabel.font = .systemFont(ofSize: 30)
        return emojiLabel
    }()

    private lazy var emojiContainer: CircleView = {
        let emojiContainer = CircleView()
        emojiContainer.translatesAutoresizingMaskIntoConstraints = false
        emojiContainer.isUserInteractionEnabled = true
        emojiContainer.fillColor = .clear
        return emojiContainer
    }()
    
    init(reaction: String, selected: Bool) {
        self.reaction = reaction
        self.selected = selected
        
        super.init(frame: .zero)
        
        if (selected) {
            fillColor = .reactionSelected
        } else {
            fillColor = .clear
        }
        addSubview(emojiLabel)
        
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }
    
    func selectEmoji() {
        selected = true
        fillColor = .reactionSelected
    }
    
    func deselectEmoji() {
        selected = false
        fillColor = .clear
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
    
