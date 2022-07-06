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

protocol ReactionViewControllerDelegate: AnyObject {
    func handleMessageSave(_ reactionViewController: ReactionViewController, chatMessage: ChatMessage)
    func handleQuotedReply(msg chatMessage: ChatMessage)
    func showDeletionConfirmationMenu(for chatMessage: ChatMessage)
}

public class ReactionViewController: UIViewController {
    
    var messageViewCell: UIView
    var chatMessage: ChatMessage
    
    weak var delegate: ReactionViewControllerDelegate?
    
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
    
    private lazy var saveAllButton: ReactionContextMenuButton = {
        let button = ReactionContextMenuButton()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSaveAll))
        button.addGestureRecognizer(tap)
        button.titleLabel.text = Localizations.buttonSave
        guard let image = UIImage(systemName: "square.and.arrow.down", withConfiguration: iconConfig) else {
            button.titleLabel.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            return button
        }
        button.imageView.image = image
        return button
    }()
    
    private lazy var replyButton: ReactionContextMenuButton = {
        let button = ReactionContextMenuButton()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleReply))
        button.addGestureRecognizer(tap)
        button.titleLabel.text = Localizations.messageReply
        guard let image = UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: iconConfig) else {
            button.titleLabel.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            return button
        }
        button.imageView.image = image
        return button
    }()
    
    private lazy var copyButton: ReactionContextMenuButton = {
        let button = ReactionContextMenuButton()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCopy))
        button.addGestureRecognizer(tap)
        button.titleLabel.text = Localizations.messageCopy
        guard let image = UIImage(systemName: "doc.on.doc", withConfiguration: iconConfig) else {
            button.titleLabel.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            return button
        }
        button.imageView.image = image
        return button
    }()
    
    private lazy var deleteButton: ReactionContextMenuButton = {
        let button = ReactionContextMenuButton()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDelete))
        button.addGestureRecognizer(tap)
        button.titleLabel.text = Localizations.messageDelete
        guard let image = UIImage(systemName: "trash", withConfiguration: iconConfig) else {
            button.titleLabel.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            return button
        }
        button.imageView.image = image
        return button
    }()
    
    init(messageViewCell: UIView, chatMessage: ChatMessage) {
        self.messageViewCell = messageViewCell
        self.chatMessage = chatMessage
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.constrain(to: view)
        
        view.addSubview(messageViewCell)
        messageViewCell.alpha = 0
        messageViewCell.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        var items = [UIBarButtonItem]()
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if chatMessage.incomingStatus != .retracted {
            items.append(space)
            if let media = chatMessage.media, !media.isEmpty {
                items.append(UIBarButtonItem(customView: saveAllButton))
                items.append(space)
            }
            
            items.append(UIBarButtonItem(customView: replyButton))
            items.append(space)
            
            if let messageText = chatMessage.rawText, !messageText.isEmpty {
                items.append(UIBarButtonItem(customView: copyButton))
                items.append(space)
            }
            items.append(UIBarButtonItem(customView: deleteButton))
            items.append(space)
        }
        guard items.count > 0 else { return }
        
        toolbar.setItems(items, animated: false)
        
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 75)
        ])

    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut, animations: {
            self.backgroundView.alpha = 1
            self.messageViewCell.alpha = 1
            self.messageViewCell.transform = .identity
        }, completion: nil)
    }
    
    @objc
    private func dismissTap(_ gesture: UITapGestureRecognizer) {
        dismiss(animated: true)
    }
    
    @objc
    private func handleSaveAll() {
        guard let delegate = delegate else {
            return
        }
        dismiss(animated: true)
        delegate.handleMessageSave(self, chatMessage: chatMessage)
    }
    
    @objc
    private func handleReply() {
        guard let delegate = delegate else {
            return
        }
        dismiss(animated: true)
        delegate.handleQuotedReply(msg: chatMessage)
    }
    
    @objc
    private func handleCopy() {
        if let messageText = chatMessage.rawText, !messageText.isEmpty {
            let pasteboard = UIPasteboard.general
            pasteboard.string = messageText
        }
        dismiss(animated: true)
    }
    
    @objc
    private func handleDelete() {
        guard let delegate = delegate else {
            return
        }
        dismiss(animated: true)
        delegate.showDeletionConfirmationMenu(for: chatMessage)
    }
}

private class ReactionContextMenuButton: UIControl {
    let imageView = UIImageView()
    let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel.font = UIFont.systemFont(ofSize: 12)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(titleLabel)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.constrain(to: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
