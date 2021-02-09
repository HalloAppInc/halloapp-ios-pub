//
//  ProfileHeaderViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

private extension Localizations {

    static var takeOrChoosePhoto: String {
        NSLocalizedString("profile.take.choose.photo", value: "Take or Choose Photo", comment: "Title for the button allowing to select a new profile photo.")
    }

    static var deletePhoto: String {
        NSLocalizedString("profile.delete.photo", value: "Delete Photo", comment: "Title for the button allowing to delete current profile photo.")
    }
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
    
    private var headerView: ProfileHeaderView {
        view as! ProfileHeaderView
    }

    override func loadView() {
        let screenWidth = UIScreen.main.bounds.width
        let headerView = ProfileHeaderView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenWidth))
        headerView.isEditingAllowed = isEditingAllowed
        view = headerView
    }

    // MARK: Configuring View

    func configureForCurrentUser(withName name: String) {
        headerView.avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        headerView.name = name
        headerView.secondaryLabel.text = MainAppContext.shared.userData.formattedPhoneNumber

        headerView.avatarViewButton.addTarget(self, action: #selector(editProfilePhoto), for: .touchUpInside)
        headerView.nameButton.addTarget(self, action: #selector(editName), for: .touchUpInside)
        
        headerView.secondaryLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(editName)))
        headerView.secondaryLabel.isUserInteractionEnabled = true
    }

    func configureWith(userId: UserID) {
        headerView.userID = userId
        headerView.avatarViewButton.avatarView.configure(with: userId, using: MainAppContext.shared.avatarStore)
        headerView.name = MainAppContext.shared.contactStore.fullName(for: userId)
        if let contact = MainAppContext.shared.contactStore.contact(withUserId: userId),
           let phoneNumber = contact.phoneNumber {
            headerView.secondaryLabel.text = phoneNumber.formattedPhoneNumber
        } else {
            headerView.messageButton.isHidden = true
            headerView.secondaryLabel.isHidden = true
        }
        headerView.messageButton.addTarget(self, action: #selector(openChatView), for: .touchUpInside)
    }

    func configureAsHorizontal() {
        headerView.configureAsHorizontal()
    }
    
    // MARK: Profile Name Editing

    @objc private func editName() {
        DDLogInfo("profile/edit-name Presenting editor")
        let viewController = NameEditViewController { (controller, nameOrNil) in
            if let name = nameOrNil, name != MainAppContext.shared.userData.name {
                DDLogInfo("profile/edit-name Changing name to [\(name)]")

                MainAppContext.shared.userData.name = name
                MainAppContext.shared.userData.save()
                MainAppContext.shared.service.sendCurrentUserNameIfPossible()
            }
            controller.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: viewController), animated: true)
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

    @objc private func openChatView() {
        guard let userID = headerView.userID else { return }

        navigationController?.pushViewController(ChatViewController(for: userID), animated: true)

        // special case to prevent user from chaining a loop-like navigation stack
        guard let nc = navigationController else { return }
        var viewControllers = nc.viewControllers
        guard viewControllers.count >= 5 else { return }
        let thirdLast = viewControllers.count - 3
        let fourthLast = viewControllers.count - 4
        guard viewControllers[fourthLast].isKind(of: UserFeedViewController.self),
              viewControllers[thirdLast].isKind(of: ChatViewController.self) else { return }
        viewControllers.remove(at: thirdLast)
        viewControllers.remove(at: fourthLast)
        navigationController?.viewControllers = viewControllers
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
            let photoCropperViewController = MediaEditViewController(cropToCircle: true, mediaToEdit: media, selected: 0) { (controller, media, index, canceled) in
                guard let selectedPhoto = media.first?.image, !canceled else {
                    DDLogInfo("profile/edit-photo Photo cropper canceled")
                    controller.dismiss(animated: true)
                    return
                }
                self.uploadProfilePhoto(selectedPhoto)
                self.dismiss(animated: true)
            }

            photoCropperViewController.modalPresentationStyle = .fullScreen // required for pinch dragging
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
        MainAppContext.shared.avatarStore.save(image: resizedImage, forUserId: MainAppContext.shared.userData.userId, avatarId: "self")
        MainAppContext.shared.service.sendCurrentAvatarIfPossible()
        
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
        MainAppContext.shared.service.sendCurrentAvatarIfPossible()
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
    private(set) var secondaryLabel: UILabel!

    var isEditingAllowed: Bool = false {
        didSet {
            if isEditingAllowed {
                addCameraOverlayToAvatarViewButton()
                avatarViewButton.isUserInteractionEnabled = true
                nameButton.isHidden = false
                nameLabel.isHidden = true
            } else {
                avatarViewButton.avatarView.placeholderOverlayView = nil
                avatarViewButton.isUserInteractionEnabled = false
                nameButton.isHidden = true
                nameLabel.isHidden = false
                messageButton.isHidden = false
            }
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
        avatarViewButton.isUserInteractionEnabled = isEditingAllowed
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        
        avatarViewButtonHeightAnchor = avatarViewButton.heightAnchor.constraint(equalToConstant: 100)
        avatarViewButton.widthAnchor.constraint(equalTo: avatarViewButton.heightAnchor).isActive = true
        avatarViewButtonHeightAnchor?.isActive = true
        
        let nameFont = UIFont.gothamFont(forTextStyle: .headline, pointSizeChange: 1, weight: .medium)

        nameLabel = UILabel()
        nameLabel.textColor = UIColor.label.withAlphaComponent(0.8)
        nameLabel.numberOfLines = 0
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.font = nameFont
        nameLabel.isHidden = isEditingAllowed

        nameButton = UIButton(type: .system)
        nameButton.tintColor = nameLabel.textColor
        nameButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        nameButton.titleLabel?.numberOfLines = 0
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nameButton.titleLabel?.font = nameFont
        nameButton.isHidden = !isEditingAllowed

        secondaryLabel = UILabel()
        secondaryLabel.numberOfLines = 0
        secondaryLabel.textColor = .secondaryLabel
        secondaryLabel.textAlignment = .center
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.font = .preferredFont(forTextStyle: .callout)

        addSubview(vStack)
        vStackTopAnchorConstraint = vStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 32)
        vStackBottomAnchorConstraint = vStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -20)
        vStackTopAnchorConstraint?.isActive = true
        vStackBottomAnchorConstraint?.isActive = true
        
        vStack.constrainMargins([ .leading, .trailing ], to: self)
    }
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ avatarViewButton, nameColumn ])
        view.spacing = 8
        view.axis = .vertical
        view.alignment = .center
        view.setCustomSpacing(12, after: avatarViewButton)
        view.setCustomSpacing(view.spacing - nameButton.contentEdgeInsets.bottom, after: nameButton)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var nameColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, nameButton, secondaryLabel, messageButton ])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
    
        return view
    }()
    
    private(set) lazy var messageButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 10)
        button.tintColor = .primaryBlue
        
        button.titleLabel?.font = UIFont.systemFont(forTextStyle: .headline, weight: .medium)
        button.setTitle("Message", for: .normal)
        
        button.isHidden = true
        return button
        
    }()
}
