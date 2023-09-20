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
    static let formStackBottomPadding: CGFloat = 12
}

class CreateGroupViewController: UIViewController {

    private var cancellableSet: Set<AnyCancellable> = []

    private var avatarData: Data? = nil

    private var groupType: GroupType

    private var selectedMembers: [UserID] = []

    private var expirationType: Group.ExpirationType = .expiresInSeconds
    private var expirationTime: Int64 = ServerProperties.enableGroupExpiry ? .thirtyDays : Int64(FeedPost.defaultExpiration)

    private var completion: (GroupID) -> Void

    private var formStackBottomAnchor: NSLayoutConstraint?
    private var didPerformInitialLayout = false

    init(groupType: GroupType, completion: @escaping (GroupID) -> Void) {
        self.completion = completion
        self.groupType = groupType
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("CreateGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = nextBarButtonItem

        navigationItem.title = Localizations.createGroupTitle

        navigationItem.compactAppearance = .transparentAppearance
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.scrollEdgeAppearance = .transparentAppearance

        view.backgroundColor = .createGroupBackground

        view.addSubview(avatarImageView)

        view.addSubview(cameraIconView)

        let groupNameContainer = UIView()

        groupNameLabel.translatesAutoresizingMaskIntoConstraints = false
        groupNameContainer.addSubview(groupNameLabel)

        NSLayoutConstraint.activate([
            groupNameLabel.leadingAnchor.constraint(equalTo: groupNameContainer.leadingAnchor, constant: 5),
            groupNameLabel.topAnchor.constraint(equalTo: groupNameContainer.topAnchor),
            groupNameLabel.trailingAnchor.constraint(equalTo: groupNameContainer.trailingAnchor),
            groupNameLabel.bottomAnchor.constraint(equalTo: groupNameContainer.bottomAnchor),
        ])

        let groupNameStackView = UIStackView(arrangedSubviews: [groupNameContainer, groupNameTextField, groupNameLengthLabel])
        groupNameStackView.axis = .vertical
        groupNameStackView.spacing = 8
        groupNameStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(groupNameStackView)


        let formStackField = UIStackView(arrangedSubviews: [groupNameStackView])
        formStackField.axis = .vertical
        formStackField.spacing = 20
        formStackField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formStackField)


        if ServerProperties.enableGroupExpiry, groupType == .groupFeed {
            formStackField.addArrangedSubview(groupExpirationField)
        }

        let avatarTopAnchor = avatarImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100)
        avatarTopAnchor.priority = UILayoutPriority(500)

        let formStackBottomAnchor = formStackField.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.formStackBottomPadding)
        self.formStackBottomAnchor = formStackBottomAnchor
        
        NSLayoutConstraint.activate([
            avatarTopAnchor,
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cameraIconView.centerXAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            cameraIconView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),

            formStackField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            formStackField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            formStackField.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 32),
            formStackBottomAnchor,
        ])

        if MainAppContext.shared.nux.state == .zeroZone {
            groupNameTextField.text = Localizations.createGroupDefaultNameMyNewGroup
        }

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] notif in
                guard let keyboardNotificationInfo = KeyboardNotificationInfo(userInfo: notif.userInfo) else {
                    return
                }
                UIView.animate(withKeyboardNotificationInfo: keyboardNotificationInfo) { [weak self] in
                    guard let self = self else {
                        return
                    }
                    let inset = self.view.convert(keyboardNotificationInfo.endFrame, from: nil).intersection(self.view.bounds.inset(by: self.view.safeAreaInsets)).height
                    self.formStackBottomAnchor?.constant = -max(0, inset) - Constants.formStackBottomPadding
                    // prevent intial layout from animating due to keyboard
                    if self.didPerformInitialLayout {
                        self.view.layoutIfNeeded()
                    }
                }
            }
            .store(in: &cancellableSet)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(endEditing)))

        groupNameChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        groupNameTextField.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        didPerformInitialLayout = true
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
        let avatarImageView = UIImageView(image: UIImage(named: "CreateGroupAvatarPlaceholder"))
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chooseAvatar)))
        avatarImageView.backgroundColor = .createGroupAvatarBackground
        avatarImageView.clipsToBounds = true
        avatarImageView.contentMode = .center
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.layer.cornerRadius = 20
        avatarImageView.tintColor = .createGroupAvatarForeground
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
        label.textColor = .primaryBlackWhite.withAlphaComponent(0.5)
        label.font = UIFont.scaledSystemFont(ofSize: 12, weight: .medium)
        label.text = Localizations.createGroupNameTitle.uppercased()
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
                layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
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
        groupNameTextField.backgroundColor = .primaryWhiteBlack
        groupNameTextField.delegate = self
        groupNameTextField.font = UIFont.preferredFont(forTextStyle: .body)
        groupNameTextField.borderColor = UIColor.label.withAlphaComponent(0.24)
        groupNameTextField.layer.borderWidth = 0.5
        groupNameTextField.layer.cornerRadius = 13
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

    private lazy var groupExpirationField: UIView = {
        let groupExpirationBackground = ShadowView()
        groupExpirationBackground.backgroundColor = .primaryWhiteBlack
        groupExpirationBackground.layer.cornerRadius = 13
        groupExpirationBackground.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.15).cgColor
        groupExpirationBackground.layer.shadowOpacity = 1
        groupExpirationBackground.layer.shadowRadius = 0
        groupExpirationBackground.layer.shadowOffset = CGSize(width: 0, height: 1)

        let groupExpirationLabel = UILabel()
        groupExpirationLabel.font = .preferredFont(forTextStyle: .body)
        groupExpirationLabel.text = Localizations.createGroupExpireContent
        groupExpirationLabel.textColor = .label
        groupExpirationLabel.translatesAutoresizingMaskIntoConstraints = false
        groupExpirationBackground.addSubview(groupExpirationLabel)

        groupExpiryButton.translatesAutoresizingMaskIntoConstraints = false
        groupExpirationBackground.addSubview(groupExpiryButton)

        NSLayoutConstraint.activate([
            groupExpirationLabel.leadingAnchor.constraint(equalTo: groupExpirationBackground.leadingAnchor, constant: 20),
            groupExpirationLabel.centerYAnchor.constraint(equalTo: groupExpirationBackground.centerYAnchor),

            groupExpiryButton.leadingAnchor.constraint(greaterThanOrEqualTo: groupExpirationLabel.trailingAnchor, constant: 10),
            groupExpiryButton.topAnchor.constraint(equalTo: groupExpirationBackground.topAnchor, constant: 2),
            groupExpiryButton.trailingAnchor.constraint(equalTo: groupExpirationBackground.trailingAnchor),
            groupExpiryButton.bottomAnchor.constraint(equalTo: groupExpirationBackground.bottomAnchor, constant: -2),
        ])

        return groupExpirationBackground
    }()

    private lazy var groupExpiryButton: UIButton = {
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        buttonConfig.baseForegroundColor = .label.withAlphaComponent(0.5)

        let button = UIButton()
        button.configuration = buttonConfig
        button.titleLabel?.font = .scaledSystemFont(ofSize: 17)

        let attributedTitlePrefix = NSMutableAttributedString()
        attributedTitlePrefix.append(NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "timer")!)))
        attributedTitlePrefix.append(NSAttributedString(string: " "))

        let initialAttributedTitle = NSMutableAttributedString()
        initialAttributedTitle.append(attributedTitlePrefix)
        initialAttributedTitle.append(NSAttributedString(string: Localizations.chatGroupExpiryOption30Days))
        button.setAttributedTitle(initialAttributedTitle, for: .normal)

        button.configureWithMenu {
            HAMenu {
                HAMenuButton(title: Localizations.chatGroupExpiryOption24Hours, image: UIImage(systemName: "timer")) { [weak self, weak button] in
                    let attributedTitle = NSMutableAttributedString()
                    attributedTitle.append(attributedTitlePrefix)
                    attributedTitle.append(NSAttributedString(string: Localizations.chatGroupExpiryOption24Hours))
                    button?.setAttributedTitle(attributedTitle, for: .normal)

                    guard let self = self else {
                        return
                    }
                    self.expirationType = .expiresInSeconds
                    self.expirationTime = .oneDay
                }
                HAMenuButton(title: Localizations.chatGroupExpiryOption30Days, image: UIImage(systemName: "timer")) { [weak self, weak button] in
                    let attributedTitle = NSMutableAttributedString()
                    attributedTitle.append(attributedTitlePrefix)
                    attributedTitle.append(NSAttributedString(string: Localizations.chatGroupExpiryOption30Days))
                    button?.setAttributedTitle(attributedTitle, for: .normal)

                    guard let self = self else {
                        return
                    }
                    self.expirationType = .expiresInSeconds
                    self.expirationTime = .thirtyDays
                }
                HAMenuButton(title: Localizations.chatGroupExpiryOptionNever) { [weak self, weak button] in
                    button?.setAttributedTitle(NSAttributedString(string: Localizations.chatGroupExpiryOptionNever), for: .normal)

                    guard let self = self else {
                        return
                    }
                    self.expirationType = .never
                    self.expirationTime = 0
                }
            }
        }

        return button
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
                                                   groupType: groupType,
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
        let pickerController = MediaPickerViewController(config: .image) { [weak self] controller, _, media, cancel in
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

    @objc private func endEditing() {
        view.endEditing(true)
    }

    // MARK: Helpers

    private func setAvatar(image: UIImage) {
        guard let resizedImage = image.fastResized(to: AvatarStore.thumbnailSize) else {
            DDLogError("CreateGroupViewController/resizeImage error resize failed")
            return
        }

        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!

        avatarImageView.contentMode = .scaleAspectFill
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
        NSLocalizedString("create.group.title", value: "New Group", comment: "Title of group creation screen")
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

    static var createGroupExpireContent: String {
        NSLocalizedString("create.group.expire.content", value: "Expire Content", comment: "Title for form field selecting group content expiry time")
    }

    static var createGroupNameTitle: String {
        NSLocalizedString("create.group.name.title", value: "Name", comment: "Title for group name text field in group creation")
    }
}
