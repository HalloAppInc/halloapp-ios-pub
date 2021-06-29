//
//  EditGroupViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Foundation
import UIKit

fileprivate struct Constants {
    static let MaxNameLength = 25
    static let AvatarSize: CGFloat = UIScreen.main.bounds.height * 0.25
}

protocol EditGroupViewControllerDelegate: AnyObject {
    func editGroupViewController(_ editGroupViewController: EditGroupViewController)
}

class EditGroupViewController: UIViewController {
    weak var delegate: EditGroupViewControllerDelegate?
    
    private var chatGroup: ChatGroup
    private let originalName: String
    
    init(chatGroup: ChatGroup) {
        self.chatGroup = chatGroup
        self.originalName = chatGroup.name
        super.init(nibName: nil, bundle: nil)
        self.textView.text = self.originalName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("EditGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonSave, style: .plain, target: self, action: #selector(updateAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
        
        navigationItem.title = Localizations.chatEditGroupTitle
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        
        setupView()
    }

    deinit {
        DDLogDebug("EditGroupViewController/deinit ")
    }

    private var canUpdate: Bool {
        return !textView.text.isEmpty && textView.text != originalName
    }
    
    func setupView() {
        view.addSubview(mainView)
        view.backgroundColor = UIColor.feedBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))
        
        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        textView.becomeFirstResponder()
        
        updateCount()
    }
    
    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ groupNameLabelRow, textView, spacer ])
        
        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var groupNameLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupNameLabel])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 50, left: 20, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.chatGroupNameLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self
        
        view.textAlignment = .left
        view.backgroundColor = .secondarySystemGroupedBackground
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.tintColor = .systemBlue
        
        view.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var countRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [characterCounter])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var characterCounter: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    
    // MARK: Actions

    @objc private func closeAction() {
        dismiss(animated: true)
    }
    
    @objc private func updateAction() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        let name = textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        MainAppContext.shared.chatData.changeGroupName(groupID: chatGroup.groupId, name: name) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.delegate?.editGroupViewController(self)
                DispatchQueue.main.async {
                    self.dismiss(animated: true)
                }
            case .failure(let error):
                DDLogError("EditGroupViewController/updateAction/error \(error)")
            }
        }
    }
    
    // MARK: Helpers
    private func updateCount() {
        textView.text = String(textView.text.prefix(Constants.MaxNameLength))
        let label = String(textView.text.count)
        characterCounter.text = "\(label)/\(Constants.MaxNameLength)"
    }
    
}

extension EditGroupViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateCount()
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
    }
}

private extension Localizations {

    static var chatEditGroupTitle: String {
        NSLocalizedString("chat.edit.group.title", value: "Edit", comment: "Title of group name edit screen")
    }
    
}
