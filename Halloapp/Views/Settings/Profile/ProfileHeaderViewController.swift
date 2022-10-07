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
import CoreCommon
import CoreMedia
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 34
}

protocol ProfileHeaderDelegate: AnyObject {
    func profileHeaderDidTapUnblock(_ profileHeader: ProfileHeaderViewController)
}

final class ProfileHeaderViewController: UIViewController, UserActionHandler {
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
    private var favoritesCancellable: AnyCancellable?
    
    private var headerView: ProfileHeaderView {
        view as! ProfileHeaderView
    }

    private lazy var editTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(editName))
        return tap
    }()

    override func loadView() {
        let screenWidth = UIScreen.main.bounds.width
        let headerView = ProfileHeaderView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenWidth))
        headerView.isEditingAllowed = isEditingAllowed
        headerView.messageButton.addTarget(self, action: #selector(openChatView), for: .touchUpInside)
        headerView.audioCallButton.addTarget(self, action: #selector(audioCallButtonTapped), for: .touchUpInside)
        headerView.videoCallButton.addTarget(self, action: #selector(videoCallButtonTapped), for: .touchUpInside)
        headerView.unblockButton.addTarget(self, action: #selector(unblockButtonTappedprofile), for: .touchUpInside)
        headerView.nameLabel.addGestureRecognizer(editTapGesture)
        view = headerView
    }

    // MARK: Configuring View

    func configureForCurrentUser(withName name: String) {
        headerView.avatarViewButton.avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        headerView.name = name
        headerView.phoneNumberButton.setTitle(MainAppContext.shared.userData.formattedPhoneNumber, for: .normal)
        headerView.userID = MainAppContext.shared.userData.userId

        headerView.avatarViewButton.configureWithMenu {
            HAMenu.lazy { [weak self] in
                self?.editProfilePhotoMenu()
            }
        }
        
        headerView.phoneNumberButton.configureWithMenu {
            HAMenu {
                HAMenuButton(title: Localizations.userOptionCopyPhoneNumber, image: UIImage(systemName: "doc.on.doc")) { [weak self] in
                    self?.copyNumber()
                }
            }
        }

        favoritesCancellable = nil
        if !headerView.favoriteButton.isHidden {
            headerView.favoriteButton.isHidden = true
        }

        editTapGesture.isEnabled = true
    }

    func configureOrRefresh(userID: UserID) {
        headerView.userID = userID
        headerView.avatarViewButton.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
        headerView.name = MainAppContext.shared.contactStore.fullName(for: userID, in: MainAppContext.shared.contactStore.viewContext)

        let isContactInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: userID, in: MainAppContext.shared.contactStore.viewContext)

        headerView.isBlocked = MainAppContext.shared.privacySettings.isBlocked(userID)
        headerView.isInAddressBook = isContactInAddressBook
        headerView.isOwnProfile = userID == MainAppContext.shared.userData.userId
        var showPhoneButton = false

        if let phoneNumber = MainAppContext.shared.contactStore.normalizedPhoneNumber(for: userID, using: MainAppContext.shared.contactStore.viewContext) {
            headerView.phoneNumberButton.setTitle(phoneNumber.formattedPhoneNumber, for: .normal)
            showPhoneButton = true
        }

        if showPhoneButton {
            headerView.phoneNumberButton.configureWithMenu {
                HAMenu {
                    HAMenuButton(title: Localizations.userOptionCopyPhoneNumber, image: UIImage(systemName: "doc.on.doc")) { [weak self] in
                        self?.copyNumber()
                    }
                }
            }
        }

        headerView.phoneNumberButton.isHidden = !showPhoneButton
        headerView.avatarViewButton.addTarget(self, action: #selector(avatarViewTapped), for: .touchUpInside)

        favoritesCancellable = MainAppContext.shared.privacySettings.favoriteStatus(for: userID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFavorite in
                if self?.headerView.favoriteButton.isHidden != !isFavorite {
                    self?.headerView.favoriteButton.isHidden = !isFavorite
                }
            }

        editTapGesture.isEnabled = userID == MainAppContext.shared.userData.userId
    }

    func configureAsHorizontal() {
        headerView.configureAsHorizontal()
    }

    func changeAvatarHeight(to: CGFloat) {
        headerView.avatarViewButtonHeightAnchor?.constant = max(100, to)
        view.setNeedsLayout()
    }
    
    @objc func unblockButtonTappedprofile() {
        guard let userID = headerView.userID else { return }
        handle(action: .unblock(userID))
    }
    
    // MARK: Profile Name Editing

    @objc private func editName(_ gesture: UITapGestureRecognizer) {
        DDLogInfo("profile/edit-name Presenting editor")
        let viewController = NameEditViewController { (controller, nameOrNil) in
            if let name = nameOrNil, name != MainAppContext.shared.userData.name {
                DDLogInfo("profile/edit-name Changing name to [\(name)]")

                MainAppContext.shared.userData.name = name
                MainAppContext.shared.userData.save(using: MainAppContext.shared.userData.viewContext)
                MainAppContext.shared.service.updateUsername(name)
            }
            controller.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
    
    private func copyNumber() {
        UIPasteboard.general.string = headerView.phoneNumberButton.title(for: .normal)
    }

    // MARK: Profile Photo Editing

    @HAMenuContentBuilder
    private func editProfilePhotoMenu() -> HAMenu.Content {
        if headerView.avatarViewButton.avatarView.hasImage {
            HAMenuButton(title: Localizations.viewPhoto) { [weak self] in
                self?.presentAvatar()
            }
        }
        
        HAMenuButton(title: Localizations.takeOrChoosePhoto) { [weak self] in
            self?.presentPhotoPicker()
        }
        
        if headerView.avatarViewButton.avatarView.hasImage {
            HAMenuButton(title: Localizations.deletePhoto) { [weak self] in
                self?.promptToDeleteProfilePhoto()
            }.destructive()
        }
    }
    
    @objc private func avatarViewTapped() {
        presentAvatar()
    }
    
    private func presentAvatar() {
        guard let userID = headerView.userID, headerView.avatarViewButton.avatarView.hasImage else {
            // TODO: Support opening avatar view while avatar is being downloaded
            return
        }
        let avatarStore = MainAppContext.shared.avatarStore
        let avatar = avatarStore.userAvatar(forUserId: userID)

        guard !avatar.isEmpty else {
            DDLogError("ProfileHeaderViewController/avatarViewTapped/error [unknown-avatar-id]")
            return
        }

        let imagePublisher = Future<(URL?, UIImage?, CGSize), Never> { promise in
            avatarStore.loadFullSizeImage(for: avatar) { fullSizeImage in
                // TODO Support waiting for avatar thumbnail if it isn't available yet
                guard let image = fullSizeImage ?? MainAppContext.shared.avatarStore.userAvatar(forUserId: userID).image else {
                    // TODO This publisher should accept errors!
                    promise(.success((nil, nil, .zero)))
                    return
                }
                
                promise(.success((nil, image.circularImage(), image.size)))
            }
        }.eraseToAnyPublisher()

        let mediaController = MediaExplorerController(imagePublisher: imagePublisher, progress: nil)
        mediaController.animatorDelegate = self

        present(mediaController, animated: true)
    }

    @objc private func openChatView() {
        guard let userID = headerView.userID else { return }
        handle(action: .message(userID))
    }

    @objc private func audioCallButtonTapped() {
        guard let userID = headerView.userID else { return }
        handle(action: .call(userID, .audio))
    }

    @objc private func videoCallButtonTapped() {
        guard let userID = headerView.userID else { return }
        handle(action: .call(userID, .video))
    }

    private func presentPhotoPicker() {
        DDLogInfo("profile/edit-photo Presenting photo picker")

        let photoPickerViewController = MediaPickerViewController(config: .avatar) { (controller, _, media, canceled) in
            guard !canceled && !media.isEmpty else {
                DDLogInfo("profile/edit-photo Photo picker canceled")
                controller.dismiss(animated: true)
                return
            }

            DDLogInfo("profile/edit-photo Presenting photo cropper")
            let photoCropperViewController = MediaEditViewController(config: .profile, mediaToEdit: media, selected: 0) { (controller, media, index, canceled) in
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

            controller.reset(destination: nil, selected: [])
            controller.present(photoCropperViewController, animated: true)
        }
        present(UINavigationController(rootViewController: photoPickerViewController), animated: true)
    }

    private func uploadProfilePhoto(_ image: UIImage) {
        let userID = MainAppContext.shared.userData.userId
        MainAppContext.shared.avatarStore.uploadAvatar(image: image, for: userID, using: MainAppContext.shared.service)

        // need to configure again as avatar listens to cached objects and they get evicted once app goes to the background
        headerView.avatarViewButton.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
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
        let userID = MainAppContext.shared.userData.userId
        MainAppContext.shared.avatarStore.removeAvatar(for: userID, using: MainAppContext.shared.service)

        // need to configure again as avatar listens to cached objects and they get evicted once app goes to the background
        headerView.avatarViewButton.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
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
    private(set) var phoneNumberButton: UIButton!

    var isEditingAllowed: Bool = false {
        didSet {
            if isEditingAllowed {
                addCameraOverlayToAvatarViewButton()
            } else {
                avatarViewButton.avatarView.placeholderOverlayView = nil
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

    var isOwnProfile: Bool = true {
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
        actionPanel.isHidden = isBlocked || isOwnProfile
        unblockButton.isHidden = !isBlocked
        audioCallButton.isHidden = false
        videoCallButton.isHidden = false

        if isInAddressBook {
            audioCallButton.enable()
            videoCallButton.enable()
        } else {
            audioCallButton.disable()
            videoCallButton.disable()
        }
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
    var avatarViewButtonHeightAnchor: NSLayoutConstraint?
    
    private func commonInit() {
        preservesSuperviewLayoutMargins = true
        
        avatarViewButton = AvatarViewButton(type: .custom)
        avatarViewButton.translatesAutoresizingMaskIntoConstraints = false
        
        avatarViewButtonHeightAnchor = avatarViewButton.heightAnchor.constraint(equalToConstant: 100)
        avatarViewButton.widthAnchor.constraint(equalTo: avatarViewButton.heightAnchor).isActive = true
        avatarViewButtonHeightAnchor?.isActive = true

        phoneNumberButton = UIButton(type: .system)
        phoneNumberButton.setTitleColor(.secondaryLabel, for: .normal)
        phoneNumberButton.titleLabel?.numberOfLines = 1
        phoneNumberButton.titleLabel?.textAlignment = .left
        phoneNumberButton.titleLabel?.font = .systemFont(forTextStyle: .callout, maximumPointSize: Constants.MaxFontPointSize - 2)
        phoneNumberButton.titleLabel?.adjustsFontForContentSizeCategory = true

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
        let view = UIStackView(arrangedSubviews: [nameHStack, phoneNumberButton, actionPanel, unblockButton])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 5
        view.setCustomSpacing(22, after: phoneNumberButton)
        
        view.translatesAutoresizingMaskIntoConstraints = false
    
        return view
    }()

    private(set) lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.tintColor = UIColor.label.withAlphaComponent(0.8)
        label.numberOfLines = 1
        label.textAlignment = .left
        label.font = UIFont.gothamFont(forTextStyle: .headline, pointSizeChange: 1, weight: .medium, maximumPointSize: Constants.MaxFontPointSize)
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = true

        return label
    }()

    private(set) lazy var favoriteButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 7
        button.setImage(UIImage(named: "PrivacySettingFavoritesWithBackground")?.withRenderingMode(.alwaysOriginal), for: .normal)
        button.contentEdgeInsets.bottom = 2
        // TODO: add functionality
        button.isUserInteractionEnabled = false
        return button
    }()

    private lazy var nameHStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nameLabel, favoriteButton])
        stack.axis = .horizontal
        stack.spacing = 7
        return stack
    }()

    private(set) lazy var actionPanel: UIView = {
        let view = UIStackView(arrangedSubviews: [messageButton, audioCallButton, videoCallButton])
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

    private(set) lazy var audioCallButton: LabeledIconButton = {
        let button = Self.makeActionButton(
            image: .init(systemName: "phone.fill")?.withRenderingMode(.alwaysTemplate),
            title: Localizations.profileHeaderAudioCallUser)
        return button
    }()

    private(set) lazy var videoCallButton: LabeledIconButton = {
        let button = Self.makeActionButton(
            image: .init(systemName: "video.fill")?.withRenderingMode(.alwaysTemplate),
            title: Localizations.profileHeaderVideoCallUser)
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

    static func makeActionButton(image: UIImage?, title: String) -> LabeledIconButton {
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

// MARK: MediaListAnimatorDelegate
extension ProfileHeaderViewController: MediaListAnimatorDelegate {
    func getTransitionView(at index: MediaIndex) -> UIView? {
        return headerView.avatarViewButton
    }

    func scrollToTransitionView(at index: MediaIndex) {
    }
}

extension Localizations {
    static var takeOrChoosePhoto: String {
        NSLocalizedString("profile.take.choose.photo", value: "Take or Choose Photo", comment: "Title for the button allowing to select a new profile photo.")
    }

    static var deletePhoto: String {
        NSLocalizedString("profile.delete.photo", value: "Delete Photo", comment: "Title for the button allowing to delete current profile photo.")
    }
    
    static var viewPhoto: String {
        NSLocalizedString("profile.view.photo", value: "View Photo", comment: "Title for the button allowing the user to view their own profile photo.")
    }
    
    static var profileHeaderMessageUser: String {
        NSLocalizedString("profile.header.message.user", value: "message", comment: "This is a verb.  The text is clickable, under a contact name and takes the user to the chat screen with that contact. It should not be translated as a noun.")
    }

    static var profileHeaderAudioCallUser: String {
        NSLocalizedString("profile.header.call.user", value: "voice", comment: "This is a verb.  The text is clickable, under a contact name and starts a voice call with that contact. It should not be translated as a noun.")
    }

    static var profileHeaderVideoCallUser: String {
        NSLocalizedString("profile.header.video.call.user", value: "video", comment: "This is a verb.  The text is clickable, under a contact name and starts a video call with that contact. It should not be translated as a noun.")
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
        layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
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

    public func disable() {
        imageView.tintColor = .secondaryLabel
        label.textColor = .secondaryLabel
        self.isEnabled = false
    }

    public func enable() {
        imageView.tintColor = .systemBlue
        label.textColor = .systemBlue
        self.isEnabled = true
    }
}

private extension UIImage {
    /// - Author: [StackOverflow](https://stackoverflow.com/a/29046647)
    func circularImage() -> UIImage {
        let minEdge = min(size.height, size.width)
        let size = CGSize(width: minEdge, height: minEdge)

        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            DDLogError("UIImage/circularImage/error [could-not-get-context]")
            return self
        }

        self.draw(in: CGRect(origin: CGPoint.zero, size: size), blendMode: .copy, alpha: 1.0)

        context.setBlendMode(.copy)
        context.setFillColor(UIColor.clear.cgColor)

        let rectPath = UIBezierPath(rect: CGRect(origin: CGPoint.zero, size: size))
        let circlePath = UIBezierPath(ovalIn: CGRect(origin: CGPoint.zero, size: size))
        rectPath.append(circlePath)
        rectPath.usesEvenOddFillRule = true
        rectPath.fill()

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result ?? self
    }
}
