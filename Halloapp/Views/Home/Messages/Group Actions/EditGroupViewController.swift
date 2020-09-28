//
//  EditGroupViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/17/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import UIKit

fileprivate struct Constants {
    static let MaxNameLength = 25
    static let AvatarSize: CGFloat = UIScreen.main.bounds.height * 0.30
}

protocol EditGroupViewControllerDelegate: AnyObject {
    func createGroupViewController(_ createGroupViewController: CreateGroupViewController)
}

class EditGroupViewController: UIViewController {

    weak var delegate: EditGroupViewControllerDelegate?
    
    private var chatGroup: ChatGroup
    private let originalName: String
    
    var canUpdate: Bool {
        return !textView.text.isEmpty && textView.text != originalName
    }

    init(chatGroup: ChatGroup) {
        self.chatGroup = chatGroup
        self.originalName = chatGroup.name
        super.init(nibName: nil, bundle: nil)
        self.textView.text = self.originalName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("EditGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Update", style: .plain, target: self, action: #selector(updateAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
        
        navigationItem.title = "Edit Group"
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6
        
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("EditGroupViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("EditGroupViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }
    
    deinit {
        DDLogDebug("CreateGroupViewController/deinit ")
    }

    // MARK: Top Nav Button Actions

    @objc private func updateAction() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        let name = textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        MainAppContext.shared.chatData.changeGroupName(groupID: chatGroup.groupId, name: name) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0) {
                    self.navigationController?.popViewController(animated: true)
                }
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
            }
        }

    }
    
    @objc private func openEditAvatarOptions() {
        
        let actionSheet = UIAlertController(title: "Edit Group Photo", message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: "Take or Choose Photo", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.presentPhotoLibraryPickerNew()
        })
        
//        actionSheet.addAction(UIAlertAction(title: "Delete Photo", style: .destructive) { _ in
//
//        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
        
    }

    private func presentPhotoLibraryPickerNew() {
        let pickerController = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }

            if cancel || media.count == 0 {
                controller.dismiss(animated: true)
            } else {
                let edit = MediaEditViewController(cropToCircle: true, allowMore: false, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
//                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        
                        guard let image = media[0].image else { return }
                        
                        guard let resizedImage = image.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
                            DDLogError("EditGroupViewController/resizeImage error resize failed")
                            return
                        }

                        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!
                        
                        MainAppContext.shared.chatData.changeGroupAvatar(groupID: self.chatGroup.groupId, data: data) { [weak self] result in
                            guard let self = self else { return }
                            switch result {
                            case .success:
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                DispatchQueue.main.async() {
                                    self.avatarView.configureGroupAvatar(for: self.chatGroup.groupId, using: MainAppContext.shared.avatarStore)
                                    controller.dismiss(animated: true)
                                }
                            case .failure(let error):
                                DDLogError("CreateGroupViewController/createAction/error \(error)")
                            }
                        }
                        
                        self.dismiss(animated: true)
                    }
                }
                controller.present(edit, animated: true)
            }
        }
        
        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }
    
    func setupView() {
        view.addSubview(mainView)
        view.backgroundColor = UIColor.systemGray6
        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        textView.becomeFirstResponder()
        
        updateCount()
        avatarView.configureGroupAvatar(for: chatGroup.groupId, using: MainAppContext.shared.avatarStore)
    }
    
    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ avatarRow, textView, countRow, spacer ])
        
        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var avatarRow: UIStackView = {
        let leftSpacer = UIView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
    
        let rightSpacer = UIView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ leftSpacer, avatarView, rightSpacer ])

        view.axis = .horizontal
        view.distribution = .equalCentering
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        avatarView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openEditAvatarOptions))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        return view
    }()
    
    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        return view
    }()
    
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self
        
        view.textAlignment = .center
        view.backgroundColor = UIColor.lightText
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.tintColor = .lavaOrange
        
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
    
    func updateCount() {
        
        textView.text = String(textView.text.prefix(Constants.MaxNameLength))
        let label = String(textView.text.count)
        characterCounter.text = "\(label)/\(Constants.MaxNameLength)"
    }
}


extension EditGroupViewController: UITextViewDelegate {
    
    // Delegates
    
    func textViewDidChange(_ textView: UITextView) {
        updateCount()
        navigationItem.rightBarButtonItem?.isEnabled = canUpdate
        
    }
    
}
