//
//  EditGroupDescViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/11/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Foundation
import UIKit

fileprivate struct Constants {
    static let MaxLength = 500
}

protocol EditGroupDescViewControllerDelegate: AnyObject {
    func editGroupDescViewController(_ editGroupDescViewController: EditGroupDescViewController)
}

class EditGroupDescViewController: UIViewController {
    weak var delegate: EditGroupDescViewControllerDelegate?
    
    private var chatGroup: ChatGroup
    private let originalDesc: String
    
    init(chatGroup: ChatGroup) {
        self.chatGroup = chatGroup
        self.originalDesc = chatGroup.desc ?? ""
        super.init(nibName: nil, bundle: nil)
        self.textView.text = self.originalDesc
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("EditGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonSave, style: .plain, target: self, action: #selector(updateAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
        
        navigationItem.title = Localizations.groupEditDescTitle
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        
        setupView()
    }

    deinit {
        DDLogDebug("EditGroupViewController/deinit ")
    }

    private var canUpdate: Bool {
        return !textView.text.isEmpty && textView.text != originalDesc
    }
    
    func setupView() {
        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg
        
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
        
        let view = UIStackView(arrangedSubviews: [ groupDescLabelRow, textView, spacer ])
        
        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var groupDescLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupDescLabel])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 50, left: 20, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var groupDescLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.groupDescriptionLabel
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
        
        let description = textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        MainAppContext.shared.chatData.changeGroupDescription(groupID: chatGroup.groupId, description: description) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.delegate?.editGroupDescViewController(self)
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
        textView.text = String(textView.text.prefix(Constants.MaxLength))
        let label = String(textView.text.count)
        characterCounter.text = "\(label)/\(Constants.MaxLength)"
    }

}

extension EditGroupDescViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateCount()
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
    }
}

private extension Localizations {

    static var groupEditDescTitle: String {
        NSLocalizedString("group.edit.desc.title", value: "Edit", comment: "Title of group description edit screen")
    }

}

