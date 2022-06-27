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
    
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    
    private var toolbar : UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.backgroundColor = .primaryBg
        toolbar.translatesAutoresizingMaskIntoConstraints = false;

        return toolbar
    }()

    init(messageViewCell: UIView, chatMessage: ChatMessage){
        self.messageViewCell = messageViewCell
        self.chatMessage = chatMessage
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let backgroundDuration: TimeInterval = 0.1
        UIView.animate(withDuration: backgroundDuration) {
            self.view.backgroundColor = UIColor.clear.withAlphaComponent(0.2)
        }
        view.addSubview(messageViewCell)
        view.addGestureRecognizer(tap)
        
        var items = [UIBarButtonItem]()
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if chatMessage.incomingStatus != .retracted {
            if let media = chatMessage.media, !media.isEmpty {
                items.append(UIBarButtonItem(title: Localizations.saveAllButton,
                                             style: .plain,
                                             target: self,
                                             action: #selector(handleSaveAll))) // ChatViewControllerNew.saveAllMedia
                items.append(space)
            }
            
            items.append(UIBarButtonItem(title: Localizations.messageReply,
                                         style: .plain,
                                         target: self,
                                         action: #selector(handleReply))) // ChatViewControllerNew.handleQuotedReply
            items.append(space)
            
            if let messageText = chatMessage.rawText, !messageText.isEmpty {
                items.append(UIBarButtonItem(title: Localizations.messageCopy,
                                             style: .plain,
                                             target: self,
                                             action: #selector(handleCopy))) // UIPasteboard.general.string = messageText
                items.append(space)
            }
            items.append(UIBarButtonItem(title: Localizations.messageDelete,
                                         style: .plain,
                                         target: self,
                                         action: #selector(handleDelete))) // ChatViewControllerNew.getDeletionConfirmationMenu
        }
        guard items.count > 0 else { return }
        
        toolbar.setItems(items, animated: false)
        
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
        ])

    }
    
    @objc
    private func handleTap(_ gesture: UITapGestureRecognizer) {
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
