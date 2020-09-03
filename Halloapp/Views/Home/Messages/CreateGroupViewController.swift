//
//  HalloApp
//
//  Created by Tony Jiang on 8/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import UIKit
import SwiftUI


protocol CreateGroupViewControllerDelegate: AnyObject {
    func createGroupViewController(_ createGroupViewController: CreateGroupViewController)
}

class CreateGroupViewController: UIViewController {

    weak var delegate: CreateGroupViewControllerDelegate?
    
    private var selectedMembers: [UserID] = []
    
    private var placeholderText = "Group Name"
    
    var canCreate: Bool {
        return !textView.text.isEmpty && selectedMembers.count > 0
    }

    init(selectedMembers: [UserID]) {
        self.selectedMembers = selectedMembers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    
    override func viewDidLoad() {
        DDLogInfo("CreateGroupViewController/viewDidLoad")

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Create", style: .plain, target: self, action: #selector(createAction))
        self.navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        self.navigationItem.rightBarButtonItem?.isEnabled = canCreate
        
        self.navigationItem.title = "New Group"
        self.navigationItem.standardAppearance = .transparentAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6
        
        self.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CreateGroupViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("CreateGroupViewController/viewDidAppear")
        super.viewDidAppear(animated)
        
    }

    deinit {
        DDLogDebug("CreateGroupViewController/deinit ")
    }

    // MARK: Top Nav Button Actions

    @objc(createAction)
    private func createAction() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        MainAppContext.shared.chatData.createGroup(name: textView.text, members: selectedMembers) { [weak self] error in
            guard let self = self else { return }
            
            if error == nil {
                
                self.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
                
            } else {
                let alert = UIAlertController(title: "No Internet Connection", message: "Please check if you have internet connectivity, then try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }
        }

    }
    
    func setup() {
        view.addSubview(mainView)
        view.backgroundColor = UIColor.systemGray6
        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        textView.text = placeholderText
        textView.textColor = .placeholderText
        textView.becomeFirstResponder()
        textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
    }
    

    
    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ textView, membersRow, spacer ])
        
        view.axis = .vertical
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var membersRow: UIStackView = {

        let view = UIStackView(arrangedSubviews: [ membersLabel ])
        
        view.axis = .horizontal
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self
        
        
        view.backgroundColor = UIColor.clear
        
        view.textContainerInset.right = 8
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.tintColor = .lavaOrange
        
        view.translatesAutoresizingMaskIntoConstraints = false
        

        return view
    }()

    private lazy var membersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = "Members: \(String(selectedMembers.count))"
      
        label.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
      
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        
        return label
    }()
    
    
}


extension CreateGroupViewController: UITextViewDelegate {
    
    // Delegates
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {

        let currentText:String = textView.text
        let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)

        if updatedText.isEmpty {
            textView.text = placeholderText
            textView.textColor = .placeholderText
            textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
            navigationItem.rightBarButtonItem?.isEnabled = false
        } else if textView.textColor == .placeholderText && !text.isEmpty {
            textView.textColor = .label
            textView.text = text
            navigationItem.rightBarButtonItem?.isEnabled = canCreate
        } else {
            return true
        }

        return false
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        if view.window != nil {
            if textView.textColor == .placeholderText {
                textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
            }
        }
    }
    
}
