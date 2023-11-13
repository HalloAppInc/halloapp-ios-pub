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
import SwiftUI

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 34
}

protocol ProfileHeaderDelegate: AnyObject {
    func profileHeaderDidTapUnblock(_ profileHeader: ProfileHeaderViewController)
}

extension ProfileHeaderViewController {

    struct Configuration {
        let isEditable: Bool
        let displayFriendActions: Bool
        let displayLinkActions: Bool
        fileprivate let avatarDiameter: CGFloat

        static let `default`: Self = Configuration(isEditable: false,
                                                   displayFriendActions: true,
                                                   displayLinkActions: false,
                                                   avatarDiameter: 115)
        
        static let ownProfile: Self = Configuration(isEditable: false,
                                                    displayFriendActions: false,
                                                    displayLinkActions: false,
                                                    avatarDiameter: 115)

        static let ownProfileEditable: Self = Configuration(isEditable: true, 
                                                            displayFriendActions: false,
                                                            displayLinkActions: true,
                                                            avatarDiameter: 165)
    }
}

final class ProfileHeaderViewController: UIViewController, UserActionHandler {

    private let configuration: Configuration
    private var cancellableSet: Set<AnyCancellable> = []

    private var profile: DisplayableProfile?
    private var userID: UserID?
    weak var delegate: ProfileHeaderDelegate?

    private var headerView: ProfileHeaderView {
        view as! ProfileHeaderView
    }

    var name: String? {
        headerView.nameLabel.text
    }

    var isOwnProfile: Bool {
        userID == MainAppContext.shared.userData.userId
    }

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("ProfileHeaderViewController coder init not implemented...")
    }

    override func loadView() {
        let headerView = ProfileHeaderView(configuration: configuration)

        headerView.messageButton.addTarget(self, action: #selector(openChatView), for: .touchUpInside)
        headerView.audioCallButton.addTarget(self, action: #selector(audioCallButtonTapped), for: .touchUpInside)
        headerView.videoCallButton.addTarget(self, action: #selector(videoCallButtonTapped), for: .touchUpInside)
        headerView.linksButton.addTarget(self, action: #selector(linksButtonTapped), for: .touchUpInside)

        headerView.onEditTap = { [weak self] in
            let viewController = UIHostingController(rootView: ProfileEditor())
            self?.present(viewController, animated: true)
        }
        headerView.onAvatarTap = { [weak self] in
            self?.presentAvatar()
        }

        let template = { [weak self] (status: UserProfile.FriendshipStatus, block: @escaping ((UserID) async throws -> Void)) in
            guard let self, let header = self.view as? ProfileHeaderView, let id = self.userID else {
                return
            }

            let currentStatus = header.friendshipStatus
            header.friendshipStatus = status

            Task(priority: .userInitiated) {
                do {
                    try await block(id)
                } catch {
                    header.friendshipStatus = currentStatus
                    let alert = UIAlertController(title: Localizations.genericError, message: nil, preferredStyle: .alert)
                    self.present(alert, animated: true)
                }
            }
        }

        headerView.friendshipToggle.onAdd = {
            template(.outgoingPending) { id in
                try await MainAppContext.shared.userProfileData.addFriend(userID: id)
            }
        }

        headerView.friendshipToggle.onConfirm = {
            template(.friends) { id in
                try await MainAppContext.shared.userProfileData.acceptFriend(userID: id)
            }
        }
        headerView.friendshipToggle.onCancel = {
            template(.none) { id in
                try await MainAppContext.shared.userProfileData.cancelRequest(userID: id)
            }
        }
        headerView.friendshipToggle.onIgnore = {
            template(.none) { id in
                try await MainAppContext.shared.userProfileData.ignoreRequest(userID: id)
            }
        }
        headerView.friendshipToggle.onRemove = { [weak self] in
            guard let self, let name = self.name else {
                return
            }
            let alert = UIAlertController(title: Localizations.removeFriendTitle(name: name),
                                          message: Localizations.removeFriendBody(name: name),
                                          preferredStyle: .alert)
            let removeAction = UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { _ in
                template(.none) { id in
                    try await MainAppContext.shared.userProfileData.removeFriend(userID: id)
                }
            }
            let cancelAction = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)

            alert.addAction(removeAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true)
        }
        headerView.friendshipToggle.onUnblock = { [weak self] in
            guard let self, let name = self.name else {
                return
            }
            let alert = UIAlertController(title: Localizations.unblockTitle(name: name),
                                          message: Localizations.unBlockMessage(username: name),
                                          preferredStyle: .alert)
            let removeAction = UIAlertAction(title: Localizations.unBlockButton, style: .default) { _ in
                template(.none) { id in
                    try await MainAppContext.shared.userProfileData.unblock(userID: id)
                }
            }
            let cancelAction = UIAlertAction(title: Localizations.buttonCancel, style: .cancel)

            alert.addAction(removeAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true)
        }

        headerView.linksPanel.onTapAdd = { [weak self] in
            guard let self else {
                return
            }

            let viewController = UIHostingController(rootView: ProfileEditor())
            self.present(viewController, animated: true)
        }
        headerView.linksPanel.onTapShow = { [weak self] linkType in
            guard let self else {
                return
            }

            let links = MainAppContext.shared.userData.links
                .filter { $0.type == linkType }
                .sorted()
            let viewController = ProfileLinksViewController(links: links)
            self.present(viewController, animated: true)
        }

        view = headerView
    }

    // MARK: Configuring View

    func configure(with profile: AnyPublisher<DisplayableProfile, Never>) {
        cancellableSet = []

        profile
            .sink { [weak self] profile in
                guard let self else {
                    return
                }
                let usernameText = profile.username.isEmpty ? "" : "@\(profile.username)"
                self.userID = profile.id
                self.profile = profile

                self.headerView.nameLabel.text = profile.name
                self.headerView.usernameLabel.text = usernameText
                self.headerView.links = profile.profileLinks
                self.headerView.friendshipStatus = profile.friendshipStatus
                self.headerView.isFavorite = profile.isFavorite
                self.headerView.isBlocked = profile.isBlocked
            }
            .store(in: &cancellableSet)

        if let userID {
            headerView.avatarView.configure(with: userID, using: MainAppContext.shared.avatarStore)
        }
    }
    
    @objc private func avatarViewTapped() {
        presentAvatar()
    }
    
    private func presentAvatar() {
        guard let userID, headerView.avatarView.hasImage else {
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
        guard let userID else { return }
        Task {
            try await handle(.message, for: userID)
        }
    }

    @objc private func audioCallButtonTapped() {
        guard let userID else { return }
        Task {
            try await handle(.call(type: .audio), for: userID)
        }
    }

    @objc private func videoCallButtonTapped() {
        guard let userID else { return }
        Task {
            try await handle(.call(type: .video), for: userID)
        }
    }

    @objc private func linksButtonTapped() {
        guard let links = profile?.profileLinks else {
            return
        }

        let viewController = ProfileLinksViewController(links: links.sorted())
        present(viewController, animated: true)
    }
}

private final class ProfileHeaderView: UIView {

    let configuration: ProfileHeaderViewController.Configuration

    var onAvatarTap: (() -> Void)?
    var onEditTap: (() -> Void)?

    let nameLabel: UILabel = {
        let label = UILabel()
        label.tintColor = UIColor.label.withAlphaComponent(0.8)
        label.numberOfLines = 1
        label.textAlignment = .left
        label.font = UIFont.scaledGothamFont(ofSize: 17, weight: .medium)
        label.isUserInteractionEnabled = true
        return label
    }()

    let avatarView: AvatarView = {
        let view = AvatarView()
        return view
    }()

    let usernameLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .scaledSystemFont(ofSize: 16)
        return label
    }()

    let friendshipToggle: ProfileFriendshipToggle = {
        let toggle = ProfileFriendshipToggle()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    let linksPanel: ProfileLinksPanel = {
        let view = ProfileLinksPanel()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var favoriteButton: LargeHitButton = {
        var favoriteButtonConfiguration = UIButton.Configuration.plain()
        favoriteButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0)

        let button = LargeHitButton(type: .system)
        button.targetIncrease = 7
        button.configuration = favoriteButtonConfiguration
        button.setImage(UIImage(named: "PrivacySettingFavoritesWithBackground")?.withRenderingMode(.alwaysOriginal), for: .normal)
        // TODO: add functionality
        button.isUserInteractionEnabled = false
        return button
    }()

    private(set) lazy var messageButton: LabeledIconButton = {
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

    private(set) lazy var linksButton: LabeledIconButton = {
        let button = Self.makeActionButton(
            image: .init(systemName: "at")?.withRenderingMode(.alwaysTemplate),
            title: Localizations.linksTitle)
        return button
    }()

    var links: [ProfileLink] = [] {
        didSet { configure() }
    }

    var friendshipStatus: UserProfile.FriendshipStatus = .none {
        didSet { configure() }
    }

    var isFavorite: Bool = false {
        didSet { configure() }
    }

    var isBlocked: Bool = false {
        didSet { configure() }
    }

    var isOwnProfile: Bool = true {
        didSet { configure() }
    }

    private func configure() {
        if friendshipStatus == .friends {
            messageButton.enable()
            audioCallButton.enable()
            videoCallButton.enable()
        } else {
            messageButton.disable()
            audioCallButton.disable()
            videoCallButton.disable()
        }

        if links.isEmpty {
            linksButton.disable()
        } else {
            linksButton.enable()
        }

        favoriteButton.isHidden = !isFavorite
        linksPanel.configure(with: links)
        friendshipToggle.configure(name: nameLabel.text ?? "", status: friendshipStatus, isBlocked: isBlocked)

        setNeedsLayout()
    }

    init(configuration: ProfileHeaderViewController.Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)

        layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, favoriteButton])
        let buttonStack = UIStackView(arrangedSubviews: [messageButton, audioCallButton, videoCallButton, linksButton])
        let stack = UIStackView(arrangedSubviews: [avatarView, nameStack, usernameLabel, linksPanel, friendshipToggle, buttonStack])

        stack.axis = .vertical
        stack.alignment = .center

        nameStack.spacing = 5
        buttonStack.spacing = 8

        stack.setCustomSpacing(10, after: avatarView)
        stack.setCustomSpacing(5, after: nameStack)
        stack.setCustomSpacing(10, after: usernameLabel)
        stack.setCustomSpacing(20, after: friendshipToggle)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            avatarView.heightAnchor.constraint(equalToConstant: 115),
            avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor, multiplier: 1),

            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        buttonStack.arrangedSubviews.forEach { $0.isHidden = !configuration.displayFriendActions }
        linksPanel.isHidden = !configuration.displayLinkActions
        friendshipToggle.isHidden = !configuration.displayFriendActions

        [nameLabel, usernameLabel, avatarView].forEach { $0.isUserInteractionEnabled = true }
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapHandler))
        gesture.cancelsTouchesInView = false
        addGestureRecognizer(gesture)

        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("ProfileHeaderView coder init not implemented...")
    }

    @objc
    private func tapHandler(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: gesture.view)
        let hit = hitTest(location, with: nil)

        if configuration.isEditable, (hit === avatarView || hit === nameLabel || hit === usernameLabel) {
            onEditTap?()
        } else if hit === avatarView {
            onAvatarTap?()
        }
    }

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
        return headerView.avatarView
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

    static var linksTitle: String {
        NSLocalizedString("links.title",
                          value: "Links",
                          comment: "Indicates a user's social media links.")
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
        imageView.preferredSymbolConfiguration = .init(weight: .medium)

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

extension UIImage {
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
