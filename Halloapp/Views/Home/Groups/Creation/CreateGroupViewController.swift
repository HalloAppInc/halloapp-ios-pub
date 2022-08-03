//
//  HalloApp
//
//  Created by Tony Jiang on 8/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 100
    static let PhotoIconSize: CGFloat = 40
    static let MaxNameLength = 25
    static let NearMaxNameLength = 5
    static let MaxDescriptionLength = 500
}

class CreateGroupViewController: UIViewController {

    private var cancellableSet: Set<AnyCancellable> = []

    private var avatarData: Data? = nil

    private var selectedMembers: [UserID] = []

    private var expirationType: Group.ExpirationType = .expiresInSeconds
    private var expirationTime: Int64 = ServerProperties.enableGroupExpiry ? .thirtyDays : Int64(FeedPost.defaultExpiration)

    private var completion: (GroupID) -> Void

    init(completion: @escaping (GroupID) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("CreateGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = nextBarButtonItem

        navigationItem.title = Localizations.createGroupTitle

        view.backgroundColor = UIColor.feedBackground

        view.addSubview(avatarImageView)

        view.addSubview(cameraIconView)

        let groupNameStackView = UIStackView(arrangedSubviews: [groupNameLabel, groupNameTextField, groupNameLengthLabel])
        groupNameStackView.axis = .vertical
        groupNameStackView.spacing = 8
        groupNameStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(groupNameStackView)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cameraIconView.centerXAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: -6),
            cameraIconView.centerYAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: -6),

            groupNameStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            groupNameStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            groupNameStackView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 32),
        ])

        if MainAppContext.shared.nux.state == .zeroZone {
            groupNameTextField.text = Localizations.createGroupDefaultNameMyNewGroup
        }

        groupNameChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        groupNameTextField.becomeFirstResponder()
    }

    deinit {
        DDLogDebug("CreateGroupViewController/deinit ")
    }

    private lazy var nextBarButtonItem: UIBarButtonItem = {
        let nextBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext,
                                                style: .done,
                                                target: self,
                                                action: #selector(nextAction))
        nextBarButtonItem.tintColor = .systemBlue
        return nextBarButtonItem
    }()

    private lazy var avatarImageView: UIImageView = {
        let avatarImageView = UIImageView(image: AvatarView.defaultGroupImage)
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chooseAvatar)))
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.layer.cornerRadius = 20
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: Constants.AvatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Constants.AvatarSize),
        ])

        return avatarImageView
    }()

    private lazy var cameraIconView: UIView = {
        let cameraIconBackground = UIView()
        cameraIconBackground.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chooseAvatar)))
        cameraIconBackground.backgroundColor = .systemBlue
        cameraIconBackground.isUserInteractionEnabled = true
        cameraIconBackground.layer.cornerRadius = 0.5 * Constants.PhotoIconSize
        cameraIconBackground.translatesAutoresizingMaskIntoConstraints = false

        let cameraIconImageView = UIImageView()
        cameraIconImageView.contentMode = .scaleAspectFill
        cameraIconImageView.image = UIImage(named: "ProfileHeaderCamera")?.withRenderingMode(.alwaysTemplate)
        cameraIconImageView.tintColor = .secondarySystemGroupedBackground
        cameraIconImageView.translatesAutoresizingMaskIntoConstraints = false
        cameraIconBackground.addSubview(cameraIconImageView)

        NSLayoutConstraint.activate([
            cameraIconImageView.widthAnchor.constraint(equalToConstant: 0.5 * Constants.PhotoIconSize),
            cameraIconImageView.heightAnchor.constraint(equalToConstant: 0.5 * Constants.PhotoIconSize),
            cameraIconImageView.centerXAnchor.constraint(equalTo: cameraIconBackground.centerXAnchor),
            cameraIconImageView.centerYAnchor.constraint(equalTo: cameraIconBackground.centerYAnchor),

            cameraIconBackground.widthAnchor.constraint(equalToConstant: Constants.PhotoIconSize),
            cameraIconBackground.heightAnchor.constraint(equalToConstant: Constants.PhotoIconSize),
        ])

        return cameraIconBackground
    }()

    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.text = Localizations.chatGroupNameLabel.uppercased()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var groupNameTextField: UITextField = {
        class GroupNameTextField: UITextField {

            var borderColor: UIColor? {
                didSet {
                    updateBorderColor()
                }
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                let cornerRadius = min(bounds.height, bounds.width) / 2.0
                layer.cornerRadius = cornerRadius
                layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
            }

            override func textRect(forBounds bounds: CGRect) -> CGRect {
                return bounds.insetBy(dx: 20, dy: 12)
            }

            override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
                return textRect(forBounds: bounds)
            }

            override func editingRect(forBounds bounds: CGRect) -> CGRect {
                return textRect(forBounds: bounds)
            }

            override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                super.traitCollectionDidChange(previousTraitCollection)

                if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                    updateBorderColor()
                }
            }

            private func updateBorderColor() {
                layer.borderColor = borderColor?.resolvedColor(with: traitCollection).cgColor
            }
        }

        let groupNameTextField = GroupNameTextField()
        groupNameTextField.addTarget(self, action: #selector(groupNameChanged), for: .editingChanged)
        groupNameTextField.backgroundColor = .systemGray6
        groupNameTextField.delegate = self
        groupNameTextField.font = UIFont.preferredFont(forTextStyle: .body)
        groupNameTextField.borderColor = UIColor.label.withAlphaComponent(0.24)
        groupNameTextField.layer.borderWidth = 0.5
        groupNameTextField.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.04).cgColor
        groupNameTextField.layer.shadowOpacity = 1
        groupNameTextField.layer.shadowRadius = 1
        groupNameTextField.layer.shadowOffset = CGSize(width: 0, height: 1)
        groupNameTextField.placeholder = Localizations.createGroupNamePlaceholder
        groupNameTextField.tintColor = .systemBlue
        groupNameTextField.translatesAutoresizingMaskIntoConstraints = false
        return groupNameTextField
    }()

    private lazy var groupNameLengthLabel: UILabel = {
        let groupNameLengthLabel = UILabel()
        groupNameLengthLabel.textAlignment = .right
        groupNameLengthLabel.textColor = .secondaryLabel
        groupNameLengthLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        groupNameLengthLabel.translatesAutoresizingMaskIntoConstraints = false
        return groupNameLengthLabel
    }()

    // MARK: Actions

    @objc private func groupNameChanged() {
        let groupNameCharacterCount = groupNameTextField.text?.lengthOfBytes(using: .utf8) ?? 0

        nextBarButtonItem.isEnabled = groupNameCharacterCount > 0

        groupNameLengthLabel.isHidden = groupNameCharacterCount < (Constants.MaxNameLength - Constants.NearMaxNameLength)
        if !groupNameLengthLabel.isHidden {
            groupNameLengthLabel.text = "\(groupNameCharacterCount)/\(Constants.MaxNameLength)"
        }
    }

    @objc private func nextAction() {
        let viewController = NewGroupMembersViewController(isNewCreationFlow: true,
                                                           currentMembers: selectedMembers,
                                                           completion: { [weak self] (groupMembersViewController, didComplete, userIds) in
            guard let self = self else {
                return
            }
            // always save selectedMembers to repopulate NewGroupMembersViewController
            self.selectedMembers = userIds
            if didComplete {
                self.createAction(groupMembersViewController: groupMembersViewController, userIds: userIds)
            }
        })
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func createAction(groupMembersViewController: NewGroupMembersViewController, userIds: [UserID]) {
        guard proceedIfConnected() else { return }

        groupMembersViewController.disableCreateOrAddAction = true

        let name = groupNameTextField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        MainAppContext.shared.chatData.createGroup(name: name,
                                                   description: "",
                                                   members: userIds,
                                                   avatarData: avatarData,
                                                   expirationType: expirationType,
                                                   expirationTime: expirationTime) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupID):
                DispatchQueue.main.async { [weak self] in
                    self?.completion(groupID)
                }
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
                let alert = UIAlertController(title: nil, message: Localizations.createGroupError, preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)

                groupMembersViewController.disableCreateOrAddAction = false
            }
        }
    }

    @objc private func chooseAvatar() {
        let actionSheet = UIAlertController(title: Localizations.chatGroupPhotoTitle, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue

        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupTakeOrChoosePhoto, style: .default) { [weak self] _ in
            self?.presentPhotoLibraryPicker()
        })

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }

    // MARK: Helpers

    private func presentPhotoLibraryPicker() {
        let pickerController = MediaPickerViewController(config: .image) { [weak self] controller, _, _, media, cancel in
            guard let self = self else { return }

            if cancel || media.count == 0 {
                controller.dismiss(animated: true)
            } else {
                let edit = MediaEditViewController(config: .groupAvatar, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        if media[0].ready.value {
                            guard let image = media[0].image else { return }
                            self.setAvatar(image: image)
                        } else {
                            self.cancellableSet.insert(
                                media[0].ready.sink { [weak self] ready in
                                    guard let self = self else { return }
                                    guard ready else { return }
                                    guard let image = media[0].image else { return }
                                    self.setAvatar(image: image)
                                }
                            )
                        }
                        
                        self.dismiss(animated: true)
                    }
                }.withNavigationController()
                
                controller.present(edit, animated: true)
            }
        }

        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func setAvatar(image: UIImage) {
        guard let resizedImage = image.fastResized(to: AvatarStore.thumbnailSize) else {
            DDLogError("CreateGroupViewController/resizeImage error resize failed")
            return
        }

        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!

        avatarImageView.image =  UIImage(data: data)
        avatarData = data
    }
}

extension CreateGroupViewController: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let length = (textField.text as NSString?)?.replacingCharacters(in: range, with: string).lengthOfBytes(using: .utf8) ?? 0
        return length <= Constants.MaxNameLength
    }
}

private extension Localizations {

    static var createGroupTitle: String {
        NSLocalizedString("create.group.title", value: "Group Info", comment: "Title of group creation screen")
    }

    static var createGroupDefaultNameMyNewGroup: String {
        NSLocalizedString("create.group.default.name.my.new.group", value: "My new group", comment: "The default name given to new groups when the user is in Zero Zone (no contacts)")
    }

    static var createGroupNamePlaceholder: String {
        NSLocalizedString("create.group.name.placeholder", value: "Name your group", comment: "Placeholder text shown inside the group name input box when it's empty")
    }

    static var createGroupDescriptionPlaceholder: String {
        NSLocalizedString("create.group.description.placeholder", value: "Add a description (optional)", comment: "Placeholder text shown inside the group description input box when it's empty")
    }
    
    static var createGroupError: String {
        NSLocalizedString("create.group.error", value: "There was an error creating the group, please try again", comment: "Alert message telling the user to try creating the group again after an error")
    }
}
