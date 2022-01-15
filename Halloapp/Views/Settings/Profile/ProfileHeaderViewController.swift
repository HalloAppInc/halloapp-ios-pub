//
//  ProfileHeaderViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreMedia
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 34
}

protocol ProfileHeaderDelegate: AnyObject {
    func profileHeaderDidTapUnblock(_ profileHeader: ProfileHeaderViewController)
}

final class ProfileHeaderViewController: UIViewController {
    var isEditingAllowed: Bool = false {
        didSet {
            if let view = viewIfLoaded as? ProfileHeaderView {
                view.isEditingAllowed = isEditingAllowed
            }
        }
    }
    
    var name: String? { headerView.name }
    weak var delegate: ProfileHeaderDelegate?

    private var cancellableSet: Set<AnyCancellable> = []
    
    private var headerView: ProfileHeaderView {
        view as! ProfileHeaderView
    }

    override func loadView() {
        let screenWidth = UIScreen.main.bounds.width
        let headerView = ProfileHeaderView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenWidth))
        headerView.isEditingAllowed = isEditingAllowed
        headerView.messageButton.addTarget(self, action: #selector(openChatView), for: .touchUpInside)
        headerView.callButton.addTarget(self, action: #selector(callButtonTapped), for: .touchUpInside)
        headerView.unblockButton.addTarget(self, action: #selector(unblockButtonTappedprofile), for: .touchUpInside)
        view = headerView
    }

    // MARK: Configuring View

    func configureForCurrentUser(withName name: String) {
        headerView.avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        headerView.name = name
        headerView.phoneLabel.text = MainAppContext.shared.userData.formattedPhoneNumber

        headerView.avatarViewButton.addTarget(self, action: #selector(editProfilePhoto), for: .touchUpInside)
        headerView.nameButton.addTarget(self, action: #selector(editName), for: .touchUpInside)
        
        headerView.phoneLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(editName)))
    }

    func configureOrRefresh(userID: UserID) {
        headerView.userID = userID
        headerView.avatarViewButton.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
        headerView.name = MainAppContext.shared.contactStore.fullName(for: userID)

        let isContactInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID)

        headerView.isBlocked = isBlocked(userId: userID)
        headerView.isInAddressBook = isContactInAddressBook
        var showPhoneLabel = false

        if isContactInAddressBook {
            if let contact = MainAppContext.shared.contactStore.contact(withUserId: userID), let phoneNumber = contact.phoneNumber {
                headerView.phoneLabel.text = phoneNumber.formattedPhoneNumber
                showPhoneLabel = true
            }
        } else {
            if let pushNumber = MainAppContext.shared.contactStore.pushNumber(userID) {
                headerView.phoneLabel.text = pushNumber.formattedPhoneNumber
                showPhoneLabel = true
            }
        }

        if showPhoneLabel {
            headerView.phoneLabel.isUserInteractionEnabled = true
            headerView.phoneLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyPhoneNumber)))
        }

        headerView.phoneLabel.isHidden = !showPhoneLabel

        headerView.avatarViewButton.addTarget(self, action: #selector(avatarViewTapped), for: .touchUpInside)
    }
          
    func isBlocked(userId: UserID) -> Bool {
        guard let blockedList = MainAppContext.shared.privacySettings.blocked else {
            return false
        }
        return blockedList.userIds.contains(userId)
    }

    func configureAsHorizontal() {
        headerView.configureAsHorizontal()
    }
    
    @objc func unblockButtonTappedprofile() {
        guard let userID = headerView.userID else { return }

        let unBlockMessage = Localizations.unBlockMessage(username: MainAppContext.shared.contactStore.fullName(for: userID))

        let alert = UIAlertController(title: nil, message: unBlockMessage, preferredStyle: .actionSheet)
        let button = UIAlertAction(title: Localizations.unBlockButton, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let privacySettings = MainAppContext.shared.privacySettings
            guard let blockedList = privacySettings.blocked else { return }
            
            var newBlockList = blockedList.userIds
            newBlockList.removeAll { $0 == userID }
            privacySettings.replaceUserIDs(in: blockedList, with: newBlockList)
            
            self.headerView.isBlocked = false
            self.delegate?.profileHeaderDidTapUnblock(self)
        }
        alert.addAction(button)

        let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
        alert.addAction(cancel)
        
        present(alert, animated: true)
    }
    
    // MARK: Profile Name Editing

    @objc private func editName() {
        DDLogInfo("profile/edit-name Presenting editor")
        let viewController = NameEditViewController { (controller, nameOrNil) in
            if let name = nameOrNil, name != MainAppContext.shared.userData.name {
                DDLogInfo("profile/edit-name Changing name to [\(name)]")

                MainAppContext.shared.userData.name = name
                MainAppContext.shared.userData.save()
                MainAppContext.shared.service.updateUsername(name)
            }
            controller.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
    
    private func copyNumber() {
        UIPasteboard.general.string = headerView.phoneLabel.text
    }
    
    @objc private func copyPhoneNumber() {
        let alert = UIAlertController(title: MainAppContext.shared.contactStore.fullName(for: headerView.userID ?? ""), message: nil, preferredStyle: .actionSheet)

        let copyNumberAction = UIAlertAction(title: Localizations.userOptionCopyPhoneNumber, style: .default) { [weak self] _ in
            self?.copyNumber()
        }
        alert.addAction(copyNumberAction)

        let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
        alert.view.tintColor = .systemBlue
        alert.addAction(cancel)

        present(alert, animated: true)
    }
    

    // MARK: Profile Photo Editing

    @objc private func editProfilePhoto() {
        guard headerView.avatarViewButton.avatarView.hasImage else {
            presentPhotoPicker()
            return
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.takeOrChoosePhoto, style: .default, handler: { _ in
            self.presentPhotoPicker()
        }))
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePhoto, style: .destructive, handler: { _ in
            self.promptToDeleteProfilePhoto()
        }))
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil))
        present(actionSheet, animated: true)
    }
    
    @objc private func avatarViewTapped() {
        guard headerView.avatarViewButton.avatarView.hasImage, let userID = headerView.userID else { return }
        
        guard let image = MainAppContext.shared.avatarStore.userAvatar(forUserId: userID).image else { return }
        
        let mediaController = MediaExplorerController(avatarImage: maskRoundedImage(image: image, radius: image.size.width / 2))
        mediaController.delegate = self

        present(mediaController, animated: true)
    }
    
    /// - Author: [StackOverflow](https://stackoverflow.com/a/29046647)
    private func maskRoundedImage(image: UIImage, radius: CGFloat) -> UIImage {
        let imageView: UIImageView = UIImageView(image: image)
        let layer = imageView.layer
        layer.masksToBounds = true
        layer.cornerRadius = radius
        UIGraphicsBeginImageContext(imageView.bounds.size)
        layer.render(in: UIGraphicsGetCurrentContext()!)
        let roundedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return roundedImage!
    }
    
    @objc private func dismissFullscreenImage(_ sender: UITapGestureRecognizer) {
        navigationController?.isNavigationBarHidden = false
        tabBarController?.tabBar.isHidden = false
        sender.view?.removeFromSuperview()
    }

    @objc private func openChatView() {
        guard let userID = headerView.userID else { return }

        navigationController?.pushViewController(ChatViewController(for: userID), animated: true)
    }

    @objc private func callButtonTapped() {
        guard let peerUserID = headerView.userID else {
            DDLogInfo("ProfileHeader/callButtonTapped/peerUserID is empty")
            return
        }
        if peerUserID == MainAppContext.shared.userData.userId {
            DDLogInfo("ProfileHeader/callButtonTapped/cannot call oneself")
            return
        }
        MainAppContext.shared.callManager.startCall(to: peerUserID) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    DDLogInfo("ProfileHeader/startCall/success")
                case .failure:
                    DDLogInfo("ProfileHeader/startCall/failure")
                    let alert = self.getFailedCallAlertController()
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func getFailedCallAlertController() -> UIAlertController {
        let alert = UIAlertController(
            title: Localizations.failedCallTitle,
            message: Localizations.failedCallNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
            self.dismiss(animated: true, completion: nil)
        }))
        return alert
    }
    
    func openGroupsCommonPage() {
        guard let userID = headerView.userID else { return }

        let commonGroupsVC = GroupsInCommonViewController(userID: userID)
        let controller = UINavigationController(rootViewController: commonGroupsVC)
        controller.modalPresentationStyle = .fullScreen

        navigationController?.present(controller, animated:true)
    }
    
    private func presentPhotoPicker() {
        DDLogInfo("profile/edit-photo Presenting photo picker")

        let photoPickerViewController = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { (controller, media, canceled) in
            guard !canceled && !media.isEmpty else {
                DDLogInfo("profile/edit-photo Photo picker canceled")
                controller.dismiss(animated: true)
                return
            }

            DDLogInfo("profile/edit-photo Presenting photo cropper")
            let photoCropperViewController = MediaEditViewController(cropRegion: .circle, mediaToEdit: media, selected: 0) { (controller, media, index, canceled) in
                guard let selected = media.first, !canceled else {
                    DDLogInfo("profile/edit-photo Photo cropper canceled")
                    controller.dismiss(animated: true)
                    return
                }

                if selected.ready.value {
                    guard let image = selected.image else { return }
                    self.uploadProfilePhoto(image)
                } else {
                    self.cancellableSet.insert(
                        media[0].ready.sink { [weak self] ready in
                            guard let self = self else { return }
                            guard ready else { return }
                            guard let image = media[0].image else { return }
                            self.uploadProfilePhoto(image)
                        }
                    )
                }

                self.dismiss(animated: true)
            }.withNavigationController()

            controller.present(photoCropperViewController, animated: true)
        }
        present(UINavigationController(rootViewController: photoPickerViewController), animated: true)
    }

    private func uploadProfilePhoto(_ image: UIImage) {
        guard let resizedImage = image.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
            DDLogError("profile/edit-photo/error Image resizing failed")
            return
        }

        DDLogInfo("profile/edit-photo Will upload new photo")
        if let avatarData = MainAppContext.shared.avatarStore.save(image: resizedImage, forUserId: MainAppContext.shared.userData.userId, avatarId: "self") {
            MainAppContext.shared.service.updateAvatar(avatarData)
        }
        
        // need to configure again as avatar listens to cached objects and they get evicted once app goes to the background
        headerView.avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
    }

    private func promptToDeleteProfilePhoto() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePhoto, style: .destructive, handler: { _ in
            self.deleteProfilePhoto()
        }))
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil))
        present(actionSheet, animated: true)
    }

    private func deleteProfilePhoto() {
        DDLogInfo("profile/edit-photo Deleting photo")
        MainAppContext.shared.avatarStore.save(avatarId: "", forUserId: MainAppContext.shared.userData.userId)
        MainAppContext.shared.service.updateAvatar(nil)
        // need to configure again as avatar listens to cached objects and they get evicted once app goes to the background
        headerView.avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
    }
}

private final class ProfileHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private(set) var avatarViewButton: AvatarViewButton!
    private(set) var nameButton: UIButton!
    private var nameLabel: UILabel!
    private(set) var phoneLabel: UILabel!

    var isEditingAllowed: Bool = false {
        didSet {
            if isEditingAllowed {
                addCameraOverlayToAvatarViewButton()
                nameButton.isHidden = false
                nameLabel.isHidden = true
            } else {
                avatarViewButton.avatarView.placeholderOverlayView = nil
                nameButton.isHidden = true
                nameLabel.isHidden = false
            }
        }
    }
    
    var isBlocked: Bool = false {
        didSet {
            updateActions()
        }
    }

    var isInAddressBook: Bool = false {
        didSet {
            updateActions()
        }
    }
    
    var userID: UserID? = nil
    
    var name: String? {
        get {
            nameLabel.text
        }
        set {
            nameLabel.text = newValue
            nameButton.setTitle(newValue, for: .normal)
        }
    }
    
    func configureAsHorizontal() {
        backgroundColor = .secondarySystemGroupedBackground
        vStack.axis = .horizontal
        vStackTopAnchorConstraint?.constant = 16
        vStackBottomAnchorConstraint?.constant = -16
        avatarViewButtonHeightAnchor?.constant = 80
        nameColumn.alignment = .leading
    }

    private func updateActions() {
        actionPanel.isHidden = isBlocked || !isInAddressBook
        unblockButton.isHidden = !isBlocked
        callButton.isHidden = !ServerProperties.isAudioCallsEnabled
    }
    
    private func addCameraOverlayToAvatarViewButton() {
        let overlayViewDiameter: CGFloat = 27
        let cameraOverlayView = UIButton(type: .custom)
        cameraOverlayView.bounds.size = CGSize(width: overlayViewDiameter, height: overlayViewDiameter)
        cameraOverlayView.translatesAutoresizingMaskIntoConstraints = false
        cameraOverlayView.setBackgroundColor(.systemBlue, for: .normal)
        cameraOverlayView.setImage(UIImage(named: "ProfileHeaderCamera")?.withRenderingMode(.alwaysTemplate), for: .normal)
        cameraOverlayView.tintColor = .white
        cameraOverlayView.layer.cornerRadius = 0.5 * overlayViewDiameter
        cameraOverlayView.layer.masksToBounds = true
        avatarViewButton.avatarView.placeholderOverlayView = cameraOverlayView
        avatarViewButton.addConstraints([
            cameraOverlayView.widthAnchor.constraint(equalToConstant: overlayViewDiameter),
            cameraOverlayView.heightAnchor.constraint(equalTo: cameraOverlayView.widthAnchor),
            cameraOverlayView.bottomAnchor.constraint(equalTo: avatarViewButton.avatarView.bottomAnchor),
            cameraOverlayView.trailingAnchor.constraint(equalTo: avatarViewButton.avatarView.trailingAnchor, constant: 8)
        ])
        
    }

    private var vStackTopAnchorConstraint: NSLayoutConstraint?
    private var vStackBottomAnchorConstraint: NSLayoutConstraint?
    private var avatarViewButtonHeightAnchor: NSLayoutConstraint?
    
    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        
        avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        
        avatarViewButtonHeightAnchor = avatarViewButton.heightAnchor.constraint(equalToConstant: 100)
        avatarViewButton.widthAnchor.constraint(equalTo: avatarViewButton.heightAnchor).isActive = true
        avatarViewButtonHeightAnchor?.isActive = true
        
        let nameFont = UIFont.gothamFont(forTextStyle: .headline, pointSizeChange: 1, weight: .medium, maximumPointSize: Constants.MaxFontPointSize)

        nameLabel = UILabel()
        nameLabel.textColor = UIColor.label.withAlphaComponent(0.8)
        nameLabel.numberOfLines = 1
        nameLabel.textAlignment = .center
        nameLabel.font = nameFont
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.isHidden = isEditingAllowed

        nameButton = UIButton(type: .system)
        nameButton.tintColor = nameLabel.textColor
        nameButton.titleLabel?.numberOfLines = 1
        nameButton.titleLabel?.textAlignment = .left
        nameButton.titleLabel?.font = nameFont
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nameButton.isHidden = !isEditingAllowed
        
        nameButton.titleEdgeInsets = UIEdgeInsets(top: .leastNormalMagnitude, left: .leastNormalMagnitude, bottom: .leastNormalMagnitude, right: .leastNormalMagnitude)
        nameButton.contentEdgeInsets = UIEdgeInsets(top: .leastNormalMagnitude, left: .leastNormalMagnitude, bottom: .leastNormalMagnitude, right: .leastNormalMagnitude)

        phoneLabel = UILabel()
        phoneLabel.numberOfLines = 1
        phoneLabel.textColor = .secondaryLabel
        phoneLabel.textAlignment = .left
        phoneLabel.font = .systemFont(forTextStyle: .callout, maximumPointSize: Constants.MaxFontPointSize - 2)
        phoneLabel.adjustsFontForContentSizeCategory = true

        addSubview(vStack)
        vStackTopAnchorConstraint = vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 32)
        vStackBottomAnchorConstraint = vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -20)
        vStackTopAnchorConstraint?.isActive = true
        vStackBottomAnchorConstraint?.isActive = true
        
        vStack.constrainMargins([ .leading, .trailing ], to: self)

        updateActions()
    }
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ avatarViewButton, nameColumn ])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, nameButton, phoneLabel, actionPanel, unblockButton ])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 5
        
        view.translatesAutoresizingMaskIntoConstraints = false
    
        return view
    }()

    private(set) lazy var actionPanel: UIView = {
        let view = UIStackView(arrangedSubviews: [messageButton, callButton])
        view.axis = .horizontal
        view.spacing = 8
        return view
    }()
    
    private(set) lazy var messageButton: UIControl = {
        let button = Self.makeActionButton(
            image: .init(systemName: "message.fill")?.withRenderingMode(.alwaysTemplate),
            title: Localizations.profileHeaderMessageUser)
        return button
    }()

    private(set) lazy var callButton: UIControl = {
        let button = Self.makeActionButton(
            image: .init(systemName: "phone.fill")?.withRenderingMode(.alwaysTemplate),
            title: Localizations.profileHeaderCallUser)
        return button
    }()
    
    private(set) lazy var unblockButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 10)
        button.tintColor = .primaryBlue
        
        button.titleLabel?.font = UIFont.systemFont(forTextStyle: .headline, weight: .medium)
        button.setTitle(Localizations.unBlockedUser, for: .normal)
        return button
    }()

    static func makeActionButton(image: UIImage?, title: String) -> UIControl {
        let button = LabeledIconButton(image: image, title: title)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 55).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 65).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .feedPostBackground
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.primaryBlackWhite.withAlphaComponent(0.1).cgColor
        return button
    }
}

extension ProfileHeaderViewController: MediaExplorerTransitionDelegate {
    func getTransitionView(atPostion index: Int) -> UIView? {
        return headerView.avatarViewButton
    }
    
    func scrollMediaToVisible(atPostion index: Int) {
        return
    }
    
    func currentTimeForVideo(atPostion index: Int) -> CMTime? {
        return nil
    }

    func shouldTransitionScaleToFit() -> Bool {
        return true
    }
}

extension Localizations {
    static var takeOrChoosePhoto: String {
        NSLocalizedString("profile.take.choose.photo", value: "Take or Choose Photo", comment: "Title for the button allowing to select a new profile photo.")
    }

    static var deletePhoto: String {
        NSLocalizedString("profile.delete.photo", value: "Delete Photo", comment: "Title for the button allowing to delete current profile photo.")
    }
    
    static var profileHeaderMessageUser: String {
        NSLocalizedString("profile.header.message.user", value: "message", comment: "This is a verb.  The text is clickable, under a contact name and takes the user to the chat screen with that contact. It should not be translated as a noun.")
    }

    static var profileHeaderCallUser: String {
        NSLocalizedString("profile.header.call.user", value: "call", comment: "This is a verb.  The text is clickable, under a contact name and starts a voice call with that contact. It should not be translated as a noun.")
    }
    
    static var unBlockedUser: String {
        NSLocalizedString("profile.header.unblock.user", value: "Unblock", comment: "Text for unblocking user under profile header")
    }
  
    static var groupsInCommonButtonLabel: String {
        NSLocalizedString("profile.groups.in.common", value: "Groups In Common", comment: "A label for the button which leads to the page showing groups in common")
    }
}

final class LabeledIconButton: UIControl {

    init(image: UIImage?, title: String) {
        super.init(frame: .zero)
        imageView.image = image
        label.text = title
        addSubview(contentView)
        contentView.isUserInteractionEnabled = false
        contentView.constrain([.centerX, .centerY], to: self)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            contentView.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .systemBlue
        return imageView
    }()
    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .caption2, weight: .medium)
        label.textColor = .systemBlue
        return label
    }()
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(label)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.constrain([.top, .centerX], to: view)
        imageView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor).isActive = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.constrain([.bottom, .leading, .trailing], to: view)
        label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4).isActive = true
        return view
    }()
}
