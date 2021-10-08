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
    static let NearMaxLength = 100
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
        navigationItem.rightBarButtonItem?.tintColor = UIColor.primaryBlue
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
        
        navigationItem.title = Localizations.groupDescriptionLabel
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.primaryBg
        
        setupView()
    }

    deinit {
        DDLogDebug("EditGroupViewController/deinit ")
    }

    private var canUpdate: Bool {
        return textView.text != originalDesc
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
        updateWithMarkdown()
    }
    
    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [textView, countRow, spacer])
        
        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()

    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self

        view.textAlignment = .left
        view.backgroundColor = .secondarySystemGroupedBackground
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.tintColor = .systemBlue
        view.layer.cornerRadius = 10

        view.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var countRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [characterCounter])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        view.isLayoutMarginsRelativeArrangement = true

        view.isHidden = true
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
        let count = textView.text.count
        if count >= Constants.MaxLength - Constants.NearMaxLength {
            let countStr = String(count)
            characterCounter.text = "\(countStr)/\(Constants.MaxLength)"
            countRow.isHidden = false
        } else {
            countRow.isHidden = true
        }
    }
    
    private func updateWithMarkdown() {
        guard textView.markedTextRange == nil else { return } // account for IME
        let font = UIFont.preferredFont(forTextStyle: .body)
        let color = UIColor.label

        let ham = HAMarkdown(font: font, color: color)
        if let text = textView.text {
            if let selectedRange = textView.selectedTextRange {
                textView.attributedText = ham.parseInPlace(text)
                textView.selectedTextRange = selectedRange
            }
        }
    }

}

extension EditGroupDescViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updateCount()
        updateWithMarkdown()
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let isTextTooLong = textView.text.count + (text.count - range.length) > Constants.MaxLength
        return isTextTooLong ? false : true
    }
}

