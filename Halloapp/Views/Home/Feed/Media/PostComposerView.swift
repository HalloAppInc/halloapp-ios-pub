import AVFoundation
import Core
import CoreCommon
import CocoaLumberjackSwift
import Combine
import PhotosUI
import SwiftUI
import UIKit

protocol PostComposerViewDelegate: AnyObject {
    // TODO: maybe have the configuration encapsulate all the details and pass that in?
    func composerDidTapShare(controller: PostComposerViewController, destination: PostComposerDestination, isMoment: Bool, mentionText: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia: PendingMedia?)
    func composerDidTapBack(controller: PostComposerViewController, destination: PostComposerDestination, media: [PendingMedia], voiceNote: PendingMedia?)
    func willDismissWithInput(mentionInput: MentionInput)
    func composerDidTapLinkPreview(controller: PostComposerViewController, url: URL)
}

enum PostComposerDestination: Equatable {
    case userFeed
    case groupFeed(GroupID)
    case chat(UserID?)
}

class PostComposerViewConfiguration: ObservableObject {
    @Published var destination: PostComposerDestination = .userFeed
    var mediaCarouselMaxAspectRatio: CGFloat
    var mediaEditMaxAspectRatio: CGFloat?
    var imageServerMaxAspectRatio: CGFloat?
    var maxVideoLength: TimeInterval
    let isMoment: Bool
    
    init(
        destination: PostComposerDestination,
        mediaCarouselMaxAspectRatio: CGFloat = 1.25,
        mediaEditMaxAspectRatio: CGFloat? = nil,
        imageServerMaxAspectRatio: CGFloat? = 1.25,
        maxVideoLength: TimeInterval = 500,
        isMoment: Bool = false) {
        
        self.destination = destination
        self.mediaCarouselMaxAspectRatio = mediaCarouselMaxAspectRatio
        self.mediaEditMaxAspectRatio = mediaEditMaxAspectRatio
        self.imageServerMaxAspectRatio = imageServerMaxAspectRatio
        self.maxVideoLength = maxVideoLength
        self.isMoment = isMoment
    }
    
    static var userPost: PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .userFeed,
            maxVideoLength: ServerProperties.maxFeedVideoDuration
        )
    }
    
    static var moment: PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .userFeed,
            maxVideoLength: ServerProperties.maxFeedVideoDuration,
            isMoment: true
        )
    }

    static func groupPost(id groupID: GroupID) -> PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .groupFeed(groupID),
            maxVideoLength: ServerProperties.maxFeedVideoDuration
        )
    }

    static func message(id userId: UserID?) -> PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .chat(userId),
            mediaCarouselMaxAspectRatio: 1.0,
            imageServerMaxAspectRatio: nil,
            maxVideoLength: ServerProperties.maxChatVideoDuration
        )
    }
}

fileprivate class GenericObservable<T>: ObservableObject {
    init(_ value: T) {
        self.value = value
    }

    @Published var value: T
}

fileprivate class ObservableMediaItems: ObservableObject {
    @Published var value: [PendingMedia] = []
    var invalidated = false

    func remove(index: Int) {
        if index < value.count {
            value.remove(at: index)
        }
    }
}

fileprivate class ObservableMediaState: ObservableObject {
    @Published var isReady: Bool = false
    @Published var numberOfFailedItems: Int = 0
}

private extension Localizations {

    static var writeDescription: String {
        NSLocalizedString("composer.placeholder.media.description", value: "Write a description", comment: "Placeholder text for media caption field in post composer.")
    }

    static var writePost: String {
        NSLocalizedString("composer.placeholder.text.post", value: "Write a post", comment: "Placeholder text in text post composer screen.")
    }

    static func mediaPrepareFailed(_ mediaCount: Int) -> String {
        let format = NSLocalizedString("media.prepare.failed.n.count", comment: "Error text displayed in post composer when some of the media selected couldn't be sent.")
        return String.localizedStringWithFormat(format, mediaCount)
    }

    static func maxVideoLengthTitle(_ maxVideoLength: TimeInterval) -> String {
        let format = NSLocalizedString("composer.max.video.length.title", value: "This video is over %.0f seconds long", comment: "Alert title in composer when a video is too long")
        return String.localizedStringWithFormat(format, maxVideoLength)
    }

    static var maxVideoLengthMessage: String {
        NSLocalizedString("composer.max.video.length.message", value: "Please select another video or tap the edit button.", comment: "Alert message in composer when a video is too long")
    }

    static var newPostTitle: String {
        NSLocalizedString("composer.post.title", value: "New Post", comment: "Composer New Post title.")
    }
    
    static var newMomentTitle: String {
        NSLocalizedString("composer.moment.post.title", value: "New Moment", comment: "Composer New Moment Post title.")
    }

    static var newMessageTitle: String {
        NSLocalizedString("composer.message.title", value: "New Message", comment: "Composer New Message title.")
    }

    static func newMessageSubtitle(recipient: String) -> String {
        let format = NSLocalizedString("composer.message.subtitle", value: "Sending to %@", comment: "Composer subtitle for messages.")
        return String.localizedStringWithFormat(format, recipient)
    }

    static var tapToChange: String {
        NSLocalizedString("composer.subtitle.cta", value: "Tap to change", comment: "Show the user that the title is tappable")
    }

    static var addMore: String {
        NSLocalizedString("composer.label.more", value: "Add more", comment: "Label shown when only single media item selected")
    }

    static var edit: String {
        NSLocalizedString("composer.button.edit", value: "Edit", comment: "Title on edit button")
    }

    static var deleteVoiceRecordingTitle: String {
        NSLocalizedString("composer.delete.recording.title", value: "Delete voice recording?", comment: "Title warning that a voice recording will be deleted")
    }
}

class PostComposerViewController: UIViewController {
    let backIcon = UIImage(named: "NavbarBack")
    let closeIcon = UIImage(named: "NavbarClose")

    private var isPosting = false

    private let mediaItems = ObservableMediaItems()
    private var inputToPost: GenericObservable<MentionInput>
    private var link: GenericObservable<String>
    private var linkPreviewData: GenericObservable<LinkPreviewData?>
    private var linkPreviewImage: GenericObservable<UIImage?>
    private var shouldAutoPlay = GenericObservable(false)
    private var postComposerView: PostComposerView?
    private let isMediaPost: Bool
    private var configuration: PostComposerViewConfiguration
    private weak var delegate: PostComposerViewDelegate?
    private let audioComposerRecorder = AudioComposerRecorder()
    private let initialPostType: NewPostMediaSource

    private var cancellableSet: Set<AnyCancellable> = []
    private var mediaItemsReadyCancellableSet: Set<AnyCancellable> = []
    private var changeDestinationAvatarCancellable: AnyCancellable?

    private lazy var backButton: UIButton = {
        let imageColor = UIColor.label.withAlphaComponent(0.9)
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)?.withTintColor(imageColor)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(backAction), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])

        return button
    }()

    private lazy var titleLabel: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.textAlignment = .center
        title.font = .gothamFont(ofFixedSize: 15, weight: .medium)
        title.textColor = .label.withAlphaComponent(0.9)

        return title
    }()

    private var changeDestinationIconConstraint: NSLayoutConstraint?
    private lazy var changeDestinationIcon: UIImageView = {
        let iconImage = UIImage(named: "PrivacySettingMyContacts")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let icon = UIImageView(image: iconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let iconConstraint = icon.widthAnchor.constraint(equalToConstant: 13)
        NSLayoutConstraint.activate([
            iconConstraint,
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
        ])
        changeDestinationIconConstraint = iconConstraint

        return icon
    }()

    private lazy var changeDestinationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)

        return label
    }()

    private lazy var changeDestinationButton: UIButton = {
        let arrowImage = UIImage(named: "ArrowDownSmall")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let arrow = UIImageView(image: arrowImage)
        arrow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [changeDestinationIcon, changeDestinationLabel, arrow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setBackgroundColor(.primaryBlue, for: .normal)
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(changeDestinationAction), for: .touchUpInside)
        // moments posts go to all contacts, for now
        button.isEnabled = !configuration.isMoment
        
        button.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: 28),
            stack.topAnchor.constraint(equalTo: button.topAnchor),
            stack.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
        ])

        return button
    }()

    private lazy var changeDestinationRow: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(changeDestinationButton)

        NSLayoutConstraint.activate([
            changeDestinationButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            changeDestinationButton.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])

        return view
    }()

    private var customNavigationContentTopConstraint: NSLayoutConstraint?
    private lazy var customNavigationBar: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .feedBackground

        let navigationRow = UIView()
        navigationRow.translatesAutoresizingMaskIntoConstraints = false
        navigationRow.addSubview(backButton)
        navigationRow.addSubview(titleLabel)

        let rowsView = UIStackView(arrangedSubviews: [navigationRow, changeDestinationRow])
        rowsView.translatesAutoresizingMaskIntoConstraints = false
        rowsView.axis = .vertical
        rowsView.alignment = .fill
        rowsView.spacing = -4

        container.addSubview(rowsView)

        NSLayoutConstraint.activate([
            navigationRow.heightAnchor.constraint(equalToConstant: 44),
            backButton.leadingAnchor.constraint(equalTo: navigationRow.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: navigationRow.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: navigationRow.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navigationRow.centerYAnchor),
            rowsView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            rowsView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            rowsView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
        ])

        customNavigationContentTopConstraint = rowsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)

        return container
    }()

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        configuration: PostComposerViewConfiguration,
        initialPostType: NewPostMediaSource,
        voiceNote: PendingMedia?,
        delegate: PostComposerViewDelegate)
    {
        self.mediaItems.value = media
        self.isMediaPost = media.count > 0
        self.inputToPost = GenericObservable(initialInput)
        self.link = GenericObservable("")
        self.linkPreviewData = GenericObservable(nil)
        self.linkPreviewImage = GenericObservable(nil)
        self.configuration = configuration
        self.initialPostType = initialPostType
        audioComposerRecorder.voiceNote = voiceNote
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaToPost:standalonePicker:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // handle early processing of media items
        cancellableSet.insert(self.mediaItems.$value.sink { [weak self] items in
            guard let self = self else { return }
            self.mediaItemsReadyCancellableSet.forEach { $0.cancel() }
            self.mediaItemsReadyCancellableSet.removeAll()

            let original = Set(self.mediaItems.value.compactMap { $0.fileURL })
            let current = Set(items.compactMap { $0.fileURL })
            let removed = original.subtracting(current)

            for url in removed {
                ImageServer.shared.clearTask(for: url)
            }

            for item in items {
                let previous = item.fileURL

                let onReady = {
                    guard let url = item.fileURL else { return }

                    if previous != url, let previous = previous {
                        ImageServer.shared.clearTask(for: previous)
                    }

                    ImageServer.shared.prepare(item.type, url: url, shouldStreamVideo: false)
                }

                if item.ready.value {
                    onReady()
                } else {
                    self.mediaItemsReadyCancellableSet.insert(item.ready.sink { ready in
                        guard ready else { return }
                        onReady()
                    })
                }
            }
        })
        
        postComposerView = PostComposerView(
            mediaItems: mediaItems,
            inputToPost: inputToPost,
            link: link,
            linkPreviewData: linkPreviewData,
            linkPreviewImage: linkPreviewImage,
            audioComposerRecorder: audioComposerRecorder,
            initialPostType: initialPostType,
            shouldAutoPlay: shouldAutoPlay,
            configuration: configuration,
            crop: { [weak self] index, completion in
                guard let self = self else { return }

                MediaCarouselView.stopAllPlayback()

                let editController = MediaEditViewController(mediaToEdit: self.mediaItems.value, selected: index, maxAspectRatio: self.configuration.mediaEditMaxAspectRatio) { controller, media, selected, cancel in
                    controller.dismiss(animated: true)

                    completion(media, selected, cancel)

                    guard !cancel else { return }

                    if media.count == 0 {
                        self.backAction()
                    }
                }.withNavigationController()
                
                self.present(editController, animated: true)
            },
            goBack: { [weak self] in self?.backAction() },
            share: { [weak self] in
                self?.isVideoLengthWithinLimit { [weak self] isWithinLimit in
                    guard let self = self else { return }

                    if isWithinLimit {
                        self.share()
                    } else {
                        self.alertVideoLengthOverLimit()
                    }
                }
            },
            previewTapped: { [weak self] in self?.previewTapped() }
        )

        let postComposerViewController = UIHostingController(rootView: postComposerView)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.backgroundColor = .feedBackground

        addChild(postComposerViewController)
        view.addSubview(postComposerViewController.view)
        postComposerViewController.view.constrain(to: view)
        postComposerViewController.didMove(toParent: self)

        view.addSubview(customNavigationBar)
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        customNavigationContentTopConstraint?.isActive = true

        switch configuration.destination {
        case .chat(_):
            titleLabel.text = Localizations.newMessageTitle
        default:
            titleLabel.text = configuration.isMoment ? Localizations.newMomentTitle : Localizations.newPostTitle
        }
        
        MainAppContext.shared.privacySettings.feedPrivacySettingDidChange.sink { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateChangeDestinationBtn()
            }
        }.store(in: &cancellableSet)

        updateChangeDestinationBtn()

        //Show the favorites education modal only once to the user
        if !AppContext.shared.userDefaults.bool(forKey: "hasFavoritesModalBeenShown") {
            AppContext.shared.userDefaults.set(true, forKey: "hasFavoritesModalBeenShown")
            let vc = FavoritesInformationViewController()
            self.present(vc, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Required because UIHostingController and also a custom navigation due to the destination button
        DispatchQueue.main.async {
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        delegate?.willDismissWithInput(mentionInput: inputToPost.value)
    }

    @objc private func backAction() {
        ImageServer.shared.clearUnattachedTasks(keepFiles: false)
        delegate?.composerDidTapBack(controller: self,
                                     destination: configuration.destination,
                                     media: mediaItems.invalidated ? [] : mediaItems.value,
                                     voiceNote: audioComposerRecorder.voiceNote)
    }

    @objc private func previewTapped() {
        if let url = linkPreviewData.value?.url {
            delegate?.composerDidTapLinkPreview(controller: self, url: url)
        }
    }

    @objc private func changeDestinationAction() {
        if case .chat = configuration.destination {
            return
        }

        let controller = ChangeDestinationViewController(destination: configuration.destination) { controller, destination in
            controller.dismiss(animated: true)
            self.configuration.destination = destination
            self.updateChangeDestinationBtn()
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    private func updateChangeDestinationBtn() {
        changeDestinationIcon.isHidden = false
        changeDestinationIcon.layer.cornerRadius = 0
        changeDestinationIcon.layer.masksToBounds = false
        changeDestinationAvatarCancellable?.cancel()

        switch configuration.destination {
        case .userFeed:
            let privacy = MainAppContext.shared.privacySettings.activeType ?? .all

            switch privacy {
            case .all:
                changeDestinationIcon.image = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            case .whitelist:
                changeDestinationIcon.image = UIImage(named: "PrivacySettingFavoritesInversed")
                changeDestinationButton.setBackgroundColor(.favoritesBg, for: .normal)
            default:
                changeDestinationIcon.image = UIImage(named: "settingsSettings")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            }

            changeDestinationIconConstraint?.constant = 13

            changeDestinationLabel.text = PrivacyList.name(forPrivacyListType: privacy)
        case .groupFeed(let groupId):
            changeDestinationButton.setBackgroundColor(.primaryBlue, for: .normal)
            let avatarData = MainAppContext.shared.avatarStore.groupAvatarData(for: groupId)
            if let image = avatarData.image {
                changeDestinationIcon.image = image
                changeDestinationIcon.layer.cornerRadius = 6
                changeDestinationIcon.layer.masksToBounds = true
            } else {
                changeDestinationIcon.image = AvatarView.defaultGroupImage

                if !avatarData.isEmpty {
                    changeDestinationAvatarCancellable = avatarData.imageDidChange.sink { [weak self] image in
                        guard let self = self else { return }
                        guard let image = image else { return }
                        self.changeDestinationIcon.image = image
                    }

                    avatarData.loadImage(using: MainAppContext.shared.avatarStore)
                }
            }

            changeDestinationIconConstraint?.constant = 19

            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                changeDestinationLabel.text = group.name
            }
        case .chat(let userId):
            changeDestinationIcon.isHidden = true

            if let userId = userId {
                let name = MainAppContext.shared.contactStore.fullName(for: userId)
                changeDestinationLabel.text = Localizations.newMessageSubtitle(recipient: name)
            }
        }
    }

    private func share() {
        isPosting = true
        let mentionText = MentionText(expandedText: inputToPost.value.text, mentionRanges: inputToPost.value.mentions).trimmed()

        var allMediaItems = mediaItems.value
        if let voiceNote = audioComposerRecorder.voiceNote {
            allMediaItems.append(voiceNote)
        }

        // if no link preview or link preview not yet loaded, send without link preview.
        // if the link preview does not have an image... send immediately
        if link.value == "" || linkPreviewData.value == nil ||  linkPreviewImage.value == nil {
            delegate?.composerDidTapShare(controller: self,
                                         destination: configuration.destination,
                                            isMoment: configuration.isMoment,
                                         mentionText: mentionText,
                                               media: allMediaItems,
                                     linkPreviewData: linkPreviewData.value,
                                    linkPreviewMedia: nil)
        } else {
            // if link preview has an image, load the image before sending.
            loadLinkPreviewImageAndShare(mentionText: mentionText, mediaItems: allMediaItems)
        }
    }
    
    private func loadLinkPreviewImageAndShare(mentionText: MentionText, mediaItems: [PendingMedia]) {
        // Send link preview with image in it
        let linkPreviewMedia = PendingMedia(type: .image)
        linkPreviewMedia.image = linkPreviewImage.value
        if linkPreviewMedia.ready.value {
            self.delegate?.composerDidTapShare(controller: self,
                                              destination: configuration.destination,
                                                 isMoment: false,
                                              mentionText: mentionText,
                                                    media: mediaItems,
                                          linkPreviewData: linkPreviewData.value,
                                         linkPreviewMedia: linkPreviewMedia)
        } else {
            self.cancellableSet.insert(
                linkPreviewMedia.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }
                    self.delegate?.composerDidTapShare(controller: self,
                                                      destination: self.configuration.destination,
                                                         isMoment: false,
                                                      mentionText: mentionText,
                                                            media: mediaItems,
                                                  linkPreviewData: self.linkPreviewData.value,
                                                 linkPreviewMedia: linkPreviewMedia)
                }
            )
        }
    }

    private func alertVideoLengthOverLimit() {
        let alert = UIAlertController(title: Localizations.maxVideoLengthTitle(configuration.maxVideoLength),
                                      message: Localizations.maxVideoLengthMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default))
        self.present(alert, animated: true)
    }

    private func isVideoLengthWithinLimit(action: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for item in self.mediaItems.value {
                guard item.type == .video else { continue }
                guard let url = item.fileURL else { continue }

                if AVURLAsset(url: url).duration.seconds > self.configuration.maxVideoLength {
                    DispatchQueue.main.async {
                        action(false)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                action(true)
            }
        }
    }
}

fileprivate struct PostComposerLayoutConstants {
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let controlSpacing: CGFloat = 9
    static let controlRadius: CGFloat = 17
    static let controlSize: CGFloat = 34
    static let backgroundRadius: CGFloat = 20

    static let postTextHorizontalPadding: CGFloat = 16
    static let postTextVerticalPadding: CGFloat = 10

    static let sendButtonHeight: CGFloat = 52
    static let postTextNoMediaMinHeight: CGFloat = 265 - 2 * postTextVerticalPadding
    static let postTextWithMeidaHeight: CGFloat = sendButtonHeight - 2 * postTextVerticalPadding
    static let postTextMaxHeight: CGFloat = 118 - 2 * postTextVerticalPadding
    static let postTextRadius: CGFloat = 26
    static let postLinkPreviewHeight: CGFloat = 250

    static let fontSize: CGFloat = 16
    static let fontSizeLarge: CGFloat = 20

    static let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    static let smallFont = UIFont(descriptor: fontDescriptor, size: fontSize)
    static let largeFont = UIFont(descriptor: fontDescriptor, size: fontSizeLarge)

    static let mainScrollCoordinateSpace = "MainScrollView"

    static func getFontSize(textSize: Int, isPostWithMedia: Bool) -> UIFont {
        return isPostWithMedia || textSize > 180 ? smallFont : largeFont
    }
}

fileprivate struct PostComposerView: View {
    @ObservedObject var configuration: PostComposerViewConfiguration
    private let mediaCarouselMaxAspectRatio: CGFloat
    private let maxVideoLength: TimeInterval
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    @ObservedObject private var link: GenericObservable<String>
    @ObservedObject private var linkPreviewData: GenericObservable<LinkPreviewData?>
    @ObservedObject private var linkPreviewImage: GenericObservable<UIImage?>
    @ObservedObject private var audioComposerRecorder: AudioComposerRecorder
    private let initialPostType: NewPostMediaSource
    @ObservedObject private var shouldAutoPlay: GenericObservable<Bool>
    @ObservedObject private var isPosting = GenericObservable<Bool>(false)
    private let crop: (Int, @escaping ([PendingMedia], Int, Bool) -> Void) -> Void
    private let goBack: () -> Void
    private let share: () -> Void
    private let previewTapped: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = GenericObservable(0)
    @ObservedObject private var postTextHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var postTextComputedHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var privacySettings: PrivacySettings
    @State private var pendingMention: PendingMention? = nil
    @State private var presentPicker = false
    @State private var presentDeleteVoiceNote = false
    @State private var videoTooLong = false
    @State private var isReadyToShare = false
    private var mediaItemsBinding = Binding.constant([PendingMedia]())
    private var mediaIsReadyBinding = Binding.constant(false)
    private var numberOfFailedItemsBinding = Binding.constant(0)
    private var linkBinding = Binding.constant("")
    private var linkPreviewDataBinding = Binding.constant([LinkPreviewData]())
    private var linkPreviewImageBinding = Binding.constant(UIImage())
    private var shouldAutoPlayBinding = Binding.constant(false)

    private var readyToSharePublisher: AnyPublisher<Bool, Never>!
    private var pageChangedPublisher: AnyPublisher<Bool, Never>!
    private var postTextComputedHeightPublisher: AnyPublisher<CGFloat, Never>!
    private var longestVideoLengthPublisher: AnyPublisher<TimeInterval?, Never>!
    private var mediaReadyPublisher: AnyPublisher<Bool, Never>!
    private var mediaErrorPublisher: AnyPublisher<Error, Never>!

    private var mediaCount: Int {
        mediaItems.value.count
    }

    private var feedMediaItems: [FeedMedia] {
        mediaItems.value.map { FeedMedia($0, feedPostId: "") }
    }

    private var controlYOffset: CGFloat {
        (mediaCount > 1 ? MediaCarouselView.pageControlAreaHeight : 0) + PostComposerLayoutConstants.controlSpacing
    }

    private var showCropButton: Bool {
        currentPosition.value < mediaCount
    }

    init(
        mediaItems: ObservableMediaItems,
        inputToPost: GenericObservable<MentionInput>,
        link: GenericObservable<String>,
        linkPreviewData: GenericObservable<LinkPreviewData?>,
        linkPreviewImage: GenericObservable<UIImage?>,
        audioComposerRecorder: AudioComposerRecorder,
        initialPostType: NewPostMediaSource,
        shouldAutoPlay: GenericObservable<Bool>,
        configuration: PostComposerViewConfiguration,
        crop: @escaping (Int, @escaping ([PendingMedia], Int, Bool) -> Void) -> Void,
        goBack: @escaping () -> Void,
        share: @escaping () -> Void,
        previewTapped: @escaping () -> Void
    ) {
        self.privacySettings = MainAppContext.shared.privacySettings
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
        self.link = link
        self.linkPreviewData = linkPreviewData
        self.linkPreviewImage = linkPreviewImage
        self.audioComposerRecorder = audioComposerRecorder
        self.initialPostType = initialPostType
        self.shouldAutoPlay = shouldAutoPlay
        self.mediaCarouselMaxAspectRatio = configuration.mediaCarouselMaxAspectRatio
        self.maxVideoLength = configuration.maxVideoLength
        self.crop = crop
        self.goBack = goBack
        self.share = share
        self.configuration = configuration
        self.previewTapped = previewTapped

        let mediaReadyAndNotFailedPublisher = Publishers.CombineLatest(mediaState.$isReady, mediaState.$numberOfFailedItems)
            .map { (mediaIsReady, numberOfFailedUploads) in mediaIsReady && numberOfFailedUploads == 0 }

        readyToSharePublisher =
            Publishers.CombineLatest4(
                mediaItems.$value,
                mediaReadyAndNotFailedPublisher,
                inputToPost.$value,
                audioComposerRecorder.$voiceNote
            ).map { (mediaItems, mediaReady, inputValue, voiceNote) in
                if mediaItems.count > 0 {
                    return mediaReady
                } else if voiceNote != nil {
                    return true
                } else {
                    return !inputValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        pageChangedPublisher =
            currentPosition.$value.removeDuplicates().map { _ in return true }.eraseToAnyPublisher()

        postTextComputedHeight.value = PostComposerView.computePostHeight(
            itemsCount: self.mediaItems.value.count, postTextHeight: postTextHeight.value, link: link.value)

        postTextComputedHeightPublisher =
            Publishers.CombineLatest(
                self.mediaItems.$value,
                self.postTextHeight.$value
            )
            .map { (mediaItems, postTextHeight) -> CGFloat in
                return PostComposerView.computePostHeight(itemsCount: mediaItems.count, postTextHeight: postTextHeight, link: link.value)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        longestVideoLengthPublisher = self.mediaItems.$value
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { items in
                return items.map { item -> TimeInterval in
                    if item.type == .image {
                        return 0
                    } else {
                        guard let url = item.fileURL else { return 0 }
                        return AVURLAsset(url: url).duration.seconds
                    }
                }.max()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()

        mediaReadyPublisher = self.mediaItems.$value
            .flatMap { items in Publishers.MergeMany(items.map { $0.ready }) }
            .eraseToAnyPublisher()

        mediaErrorPublisher = self.mediaItems.$value
            .flatMap { items in Publishers.MergeMany(items.map { $0.error }) }
            .filter { $0 != nil }
            .map { $0! }
            .eraseToAnyPublisher()

        self.mediaItemsBinding = self.$mediaItems.value
        self.mediaIsReadyBinding = self.$mediaState.isReady
        self.numberOfFailedItemsBinding = self.$mediaState.numberOfFailedItems
        self.linkBinding = self.$link.value
        self.shouldAutoPlayBinding = self.$shouldAutoPlay.value
    }

    static func stopTextEdit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }

    private static func computePostHeight(itemsCount: Int, postTextHeight: CGFloat, link: String) -> CGFloat {
        var minPostHeight = PostComposerLayoutConstants.postTextNoMediaMinHeight
        if link != "" {
            minPostHeight = PostComposerLayoutConstants.postTextNoMediaMinHeight - PostComposerLayoutConstants.postLinkPreviewHeight
        }
        if itemsCount > 0 {
            minPostHeight = PostComposerLayoutConstants.postTextWithMeidaHeight
        }
        let maxPostHeight = itemsCount > 0 ? PostComposerLayoutConstants.postTextMaxHeight : CGFloat.infinity
        return min(maxPostHeight, max(minPostHeight, postTextHeight))
    }
    
    private func getMediaSliderHeight(width: CGFloat) -> CGFloat {
        return MediaCarouselView.preferredHeight(for: feedMediaItems, width: width - 4 * PostComposerLayoutConstants.horizontalPadding)
    }

    private func allowChangingDestination() -> Bool {
        switch configuration.destination {
        case .userFeed, .groupFeed:
            return true
        case .chat:
            return false
        }
    }

    var picker: some View {
        Picker(mediaItems: mediaItemsBinding) { newMediaItems, cancel in
            presentPicker = false
            guard !cancel else { return }

            let oldMediaItems = mediaItems.value
            mediaItems.value = newMediaItems
            currentPosition.value = {
                // Prefer to focus on the first newly added item
                let oldMediaItemAssets = Set(oldMediaItems.map(\.asset))
                if let idx = newMediaItems.firstIndex(where: { oldMediaItemAssets.contains($0.asset) }) {
                    return idx
                }

                // Otherwise, try to restore focus to the same item
                let previousIndex = currentPosition.value
                if previousIndex < oldMediaItems.count {
                    let lastAsset = oldMediaItems[previousIndex].asset
                    if let idx = newMediaItems.firstIndex(where: { $0.asset == lastAsset }) {
                        return idx
                    }
                }

                // Fallback
                return 0
            }()
            mediaState.isReady = mediaItems.value.allSatisfy { $0.ready.value }
        }
    }

    var postTextView: some View {
        VStack(spacing: 30) {
            ZStack (alignment: .topLeading) {
                if (inputToPost.value.text.isEmpty) {
                    Text(mediaCount > 0 ? Localizations.writeDescription : Localizations.writePost)
                        .font(Font(PostComposerLayoutConstants.getFontSize(
                            textSize: inputToPost.value.text.count, isPostWithMedia: mediaCount > 0)))
                        .foregroundColor(Color.primary.opacity(0.4))
                        .padding(.top, mediaCount > 0 ? 0 : 8)
                        .padding(.leading, 4)
                        .frame(height: postTextComputedHeight.value, alignment: mediaCount > 0 ? .leading : .topLeading)
                }
                TextView(
                    mediaItems: mediaItemsBinding,
                    pendingMention: $pendingMention,
                    link: linkBinding,
                    input: inputToPost,
                    textHeight: postTextHeight,
                    shouldFocusOnLoad: mediaCount == 0)
                    .frame(height: postTextComputedHeight.value).environmentObject(configuration)
            }
            .padding(.horizontal, PostComposerLayoutConstants.postTextHorizontalPadding)
            .padding(.vertical, PostComposerLayoutConstants.postTextVerticalPadding)

            if self.link.value != "" && self.mediaCount == 0 {
                LinkPreview(link: linkBinding, linkPreviewData: linkPreviewData, linkPreviewImage: linkPreviewImage)
                    .frame(height: PostComposerLayoutConstants.postLinkPreviewHeight, alignment: .bottom)
                    .padding(.top, -18)
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .gesture(
                        TapGesture()
                            .onEnded() { _ in
                                self.previewTapped()
                            }
                    )
            }
        }
    }

    var shareButton: some View {
        ShareButton {
            guard !self.isPosting.value else { return }

            if audioComposerRecorder.isRecording {
                audioComposerRecorder.stopRecording(cancel: false)
            }

            self.share()
        }
        .offset(x: 2)
        .disabled(!isReadyToShare || isPosting.value || (audioComposerRecorder.isRecording && !audioComposerRecorder.recorderControlsLocked))
    }

    var audioRecordingView: some View {
        return AudioPostComposer(recorder: audioComposerRecorder,
                                 isReadyToShare: isReadyToShare,
                                 shareAction: share,
                                 presentMediaPicker: $presentPicker,
                                 presentDeleteVoiceNote: $presentDeleteVoiceNote)
    }

    var voiceNotesEnabled: Bool {
        guard ServerProperties.isVoicePostsEnabled else {
            return false
        }

        switch configuration.destination {
        case .userFeed, .groupFeed:
            return true
        case .chat:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { scrollGeometry in
                ScrollView {
                    VStack {
                        VStack (alignment: .center) {
                            if self.mediaCount > 0 {
                                ZStack(alignment: .bottom) {
                                    MediaPreviewSlider(
                                        mediaItems: self.mediaItemsBinding,
                                        shouldAutoPlay: self.shouldAutoPlayBinding,
                                        presentMediaPicker: $presentPicker,
                                        currentPosition: self.currentPosition,
                                        onDelete: deleteMedia,
                                        onCrop: cropMedia
                                    )
                                    .frame(height: self.getMediaSliderHeight(width: scrollGeometry.size.width), alignment: .center)
                                    .environmentObject(configuration)
                                }
                                .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding)
                                .padding(.vertical, PostComposerLayoutConstants.verticalPadding)

                                if self.mediaState.numberOfFailedItems > 0 {
                                    Text(Localizations.mediaPrepareFailed(self.mediaState.numberOfFailedItems))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                        .padding(.bottom, 10)
                                } else if videoTooLong {
                                    Text(Localizations.maxVideoLengthTitle(maxVideoLength))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                        .padding(.bottom, 4)
                                    Text(Localizations.maxVideoLengthMessage)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                        .padding(.bottom, 10)
                                }
                            } else if initialPostType == .voiceNote || audioComposerRecorder.voiceNote != nil {
                                audioRecordingView
                            } else {
                                ZStack(alignment: .top) {
                                    ScrollView {
                                        postTextView
                                            .padding(.bottom, PostComposerLayoutConstants.sendButtonHeight + 24)
                                    }
                                    .frame(maxHeight: scrollGeometry.size.height - 2 * PostComposerLayoutConstants.verticalPadding)

                                    VStack {
                                        Spacer()
                                        HStack {
                                            Button(action: { presentPicker = true }) {
                                                Image("icon_add_photo")
                                                    .renderingMode(.template)
                                                    .foregroundColor(.blue)
                                            }
                                            .padding(.leading, 10)
                                            
                                            Spacer()
                                            shareButton
                                        }
                                        .padding(12)
                                        .background(Color(.secondarySystemGroupedBackground)).opacity(0.95)
                                    }
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius))
                        .background(mediaCount == 0 ?
                            AnyView(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0 : 0.08), radius: 8, y: 8))
                            :
                            AnyView(Rectangle().fill(Color.clear))
                        )
                        .padding(.horizontal, mediaCount > 0 ? 0 : PostComposerLayoutConstants.horizontalPadding)
                        .padding(.vertical, PostComposerLayoutConstants.verticalPadding)
                    }
                    .frame(height: scrollGeometry.size.height - 80)
                    .padding(.top, 80)
                    .background(
                        YOffsetGetter(coordinateSpace: .named(PostComposerLayoutConstants.mainScrollCoordinateSpace))
                            .onPreferenceChange(YOffsetPreferenceKey.self, perform: {
                                if $0 > 0, #available(iOS 14.0, *) { // top overscroll, before iOS 14 the reported offset seems inaccurrate
                                    PostComposerView.stopTextEdit()
                                }
                            })
                    )
                }
                .coordinateSpace(name: PostComposerLayoutConstants.mainScrollCoordinateSpace)
            }

            if mediaCount > 0 {
                HStack(alignment: .bottom, spacing: 8) {
                    if audioComposerRecorder.voiceNote != nil {
                        AudioComposerPlayer(configuration: .composerWithMedia, recorder: audioComposerRecorder, presentDeleteVoiceNote: $presentDeleteVoiceNote)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                if !configuration.isMoment {
                                    postTextView
                                        // hide vs remove to maintain sizing
                                        .opacity(audioComposerRecorder.recorderControlsExpanded ? 0 : 1)
                                }
                                if audioComposerRecorder.recorderControlsExpanded {
                                    HStack {
                                        AudioPostComposerDurationView(time: audioComposerRecorder.duration)
                                        // Maintain a solid background to hide "slide to cancel" text from recorder control
                                            .padding(.horizontal, 4)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .padding(.leading, PostComposerLayoutConstants.postTextHorizontalPadding - 4)
                                        Spacer()
                                        if audioComposerRecorder.recorderControlsLocked {
                                            Button {
                                                audioComposerRecorder.stopRecording(cancel: false)
                                            } label: {
                                                Text(Localizations.buttonStop)
                                                    .font(.system(size: 17, weight: .medium))
                                                    .foregroundColor(.primaryBlue)
                                            }
                                            .padding(.leading, -6)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .zIndex(1)
                            if voiceNotesEnabled, inputToPost.value.text.isEmpty, !audioComposerRecorder.recorderControlsLocked, !configuration.isMoment {
                                AudioComposerRecorderControl(recorder: audioComposerRecorder)
                                    .frame(width: 24, height: 24)
                                    .padding(.horizontal, PostComposerLayoutConstants.postTextHorizontalPadding)
                            }
                        }
                        .frame(minHeight: 60)
                        .background(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.postTextRadius)
                                        .fill(Color(.secondarySystemGroupedBackground)))
                        .compositingGroup()
                        .shadow(color: .black.opacity(self.colorScheme == .dark ? 0 : 0.04), radius: 2, y: 1)
                        .zIndex(1)
                    }
                    
                    if configuration.isMoment {
                        // want the share button to be on the right, not centered
                        Spacer()
                    }
                    shareButton
                        .offset(y: -2)
                        .offset(x: configuration.isMoment ? -15 : 0)
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.feedBackground)
        .sheet(isPresented: $presentPicker) {
            picker.edgesIgnoringSafeArea(.bottom)
        }
        .actionSheet(isPresented: $presentDeleteVoiceNote) {
            ActionSheet(title: Text(Localizations.deleteVoiceRecordingTitle), message: nil, buttons: [
                .destructive(Text(Localizations.buttonDelete), action: {
                    audioComposerRecorder.voiceNote = nil
                }),
                .cancel(),
            ])
        }
        .onReceive(self.readyToSharePublisher) { isReadyToShare = $0 }
        .onReceive(self.pageChangedPublisher) { _ in PostComposerView.stopTextEdit() }
        .onReceive(self.postTextComputedHeightPublisher) { self.postTextComputedHeight.value = $0 }
        .onReceive(longestVideoLengthPublisher) {
            guard let length = $0 else {
                videoTooLong = false
                return
            }
            videoTooLong = length > maxVideoLength
        }
        .onReceive(mediaReadyPublisher) { _ in
            mediaState.isReady = self.mediaItems.value.allSatisfy { $0.ready.value }
        }
        .onReceive(mediaErrorPublisher) { _ in
            mediaState.numberOfFailedItems += 1
        }
        .onAppear {
            mediaState.isReady = self.mediaItems.value.allSatisfy { $0.ready.value }
        }
    }

    private func cropMedia() {
        mediaState.isReady = false
        crop(currentPosition.value) { media, selected, cancel in
            defer {
                mediaState.isReady = self.mediaItems.value.allSatisfy { $0.ready.value }
            }

            guard !cancel else { return }

            currentPosition.value = selected
            self.mediaItems.value = media
        }
    }

    private func deleteMedia() {
        if shouldGoBackAfterMediaDeletion() {
            mediaItems.invalidated = true
            goBack()
        } else {
            mediaItems.remove(index: currentPosition.value)
        }
    }
    
    private func shouldGoBackAfterMediaDeletion() -> Bool {
        guard mediaCount == 1, audioComposerRecorder.voiceNote == nil else {
            return false
        }
        
        /*
         Don't want to go back if this composer started out as a text post
         and its text view has text
         */
        return !(initialPostType == .noMedia && !inputToPost.value.text.isEmpty)
    }
}

struct YOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {}
}

struct YOffsetGetter: View {
    let coordinateSpace: CoordinateSpace

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: YOffsetPreferenceKey.self, value: geometry.frame(in: coordinateSpace).minY)
        }
    }
}

private struct PendingMention {
    var name: String
    var userID: UserID
    var range: NSRange
}

fileprivate struct Constants {
    static let textViewTextColor = UIColor.label.withAlphaComponent(0.9)
}

fileprivate struct TextView: UIViewRepresentable {
    @EnvironmentObject var configuration: PostComposerViewConfiguration
    @Binding var mediaItems: [PendingMedia]
    @Binding var pendingMention: PendingMention?
    @Binding var link: String
    var input: GenericObservable<MentionInput>
    var textHeight: GenericObservable<CGFloat>
    var shouldFocusOnLoad: Bool
    private(set) var mentionableUsers: [MentionableUser] = []
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        DDLogInfo("TextView/makeUIView")
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.inputAccessoryView = context.coordinator.mentionPicker
        textView.isScrollEnabled = mediaItems.count > 0
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = PostComposerLayoutConstants.getFontSize(
            textSize: input.value.text.count, isPostWithMedia: mediaItems.count > 0)
        textView.tintColor = .systemBlue
        textView.textColor = Constants.textViewTextColor
        textView.text = input.value.text
        
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context)  {
        DDLogInfo("TextView/updateUIView")

        // Don't set text or selection on uiView (it clears markedTextRange, which breaks IME)

        if let mention = pendingMention {
            DispatchQueue.main.async {
                var mentionInput = self.input.value
                mentionInput.addMention(name: mention.name, userID: mention.userID, in: mention.range)
                uiView.text = mentionInput.text
                uiView.selectedRange = mentionInput.selectedRange
                self.input.value = mentionInput
                self.pendingMention = nil
            }
        }

        if shouldFocusOnLoad && !context.coordinator.hasTextViewLoaded {
            uiView.becomeFirstResponder()
        }
        
        context.coordinator.hasTextViewLoaded = true
        TextView.recomputeTextViewSizes(uiView, textSize: input.value.text.count, isPostWithMedia: mediaItems.count > 0, height: textHeight)
    }

    private static func recomputeTextViewSizes(_ textView: UITextView, textSize: Int, isPostWithMedia: Bool, height: GenericObservable<CGFloat>) {
        DispatchQueue.main.async {
            let font = PostComposerLayoutConstants.getFontSize(textSize: textSize, isPostWithMedia: isPostWithMedia)
            textView.font = font

            let size = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))
            height.value = size.height
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        var hasTextViewLoaded = false
        var destinationListener: AnyCancellable?
        
        init(_ uiTextView: TextView) {
            parent = uiTextView
            super.init()
            
            parent.mentionableUsers = mentionableUsers(for: parent.configuration.destination)
            destinationListener = parent.configuration.$destination.sink { [weak self] destination in
                guard let self = self else { return }
                self.parent.mentionableUsers = self.mentionableUsers(for: destination)
                self.validateMentionsAfterAudienceChange()
            }
        }

        // MARK: Mentions

        lazy var mentionPicker: MentionPickerView = {
            let picker = MentionPickerView(avatarStore: MainAppContext.shared.avatarStore)
            picker.cornerRadius = 10
            picker.borderColor = .systemGray
            picker.borderWidth = 1
            picker.clipsToBounds = true
            picker.translatesAutoresizingMaskIntoConstraints = false
            picker.isHidden = true // Hide until content is set
            picker.didSelectItem = { [weak self] item in self?.acceptMentionPickerItem(item) }
            picker.heightAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
            return picker
        }()
        
        private func mentionableUsers(for destination: PostComposerDestination) -> [MentionableUser] {
            switch destination {
            case .userFeed:
                return Mentions.mentionableUsersForNewPost()
            case .groupFeed(let id):
                return Mentions.mentionableUsers(forGroupID: id)
            case .chat(_):
                return []
            }
        }
        
        private func validateMentionsAfterAudienceChange() {
            updateMentionPickerContent()

            let newSet = Set(parent.mentionableUsers.map { $0.userID })
            let filtered = parent.input.value.mentions.filter { newSet.contains($1.userID) }
            parent.input.value.mentions = filtered
            
            if let pending = parent.pendingMention, !newSet.contains(pending.userID) {
                parent.pendingMention = nil
            }
        }

        private func updateMentionPickerContent() {
            let mentionableUsers = fetchMentionPickerContent(for: parent.input.value)

            mentionPicker.items = mentionableUsers
            mentionPicker.isHidden = mentionableUsers.isEmpty
        }

        private func updateWithMarkdown(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return } // account for IME
            let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            let color = Constants.textViewTextColor

            let ham = HAMarkdown(font: font, color: color)
            if let text = textView.text {
                if let selectedRange = textView.selectedTextRange {
                    textView.attributedText = ham.parseInPlace(text)
                    textView.selectedTextRange = selectedRange
                }
            }
        }

        private func acceptMentionPickerItem(_ item: MentionableUser) {
            let input = parent.input.value
            guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
                // For now we assume there is a word to replace (but in theory we could just insert at point)
                return
            }

            let utf16Range = NSRange(mentionCandidateRange, in: input.text)
            parent.pendingMention = PendingMention(
                name: item.fullName,
                userID: item.userID,
                range: utf16Range)
            updateMentionPickerContent()
        }

        private func fetchMentionPickerContent(for input: MentionInput) -> [MentionableUser] {
            guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
                return []
            }
            let mentionCandidate = input.text[mentionCandidateRange]
            let trimmedInput = String(mentionCandidate.dropFirst())
            
            let mentionableUsers = parent.mentionableUsers
            return mentionableUsers.filter {
                Mentions.isPotentialMatch(fullName: $0.fullName, input: trimmedInput)
            }
        }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            var mentionInput = parent.input.value

            // Treat mentions atomically (editing any part of the mention should remove the whole thing)
            let rangeIncludingImpactedMentions = mentionInput
                .impactedMentionRanges(in: range)
                .reduce(range) { range, mention in NSUnionRange(range, mention) }

            mentionInput.changeText(in: rangeIncludingImpactedMentions, to: text)

            if range == rangeIncludingImpactedMentions {
                // Update mentions and return true so UITextView can update text without breaking IME
                parent.input.value = mentionInput
                return true
            } else {
                // Update content ourselves and return false so UITextView doesn't issue conflicting update
                textView.text = mentionInput.text
                textView.selectedRange = mentionInput.selectedRange
                parent.input.value = mentionInput

                TextView.recomputeTextViewSizes(textView, textSize: parent.input.value.text.count, isPostWithMedia: parent.mediaItems.count > 0, height: parent.textHeight)
                return false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.input.value.text = textView.text ?? ""

            TextView.recomputeTextViewSizes(textView, textSize: parent.input.value.text.count, isPostWithMedia: parent.mediaItems.count > 0, height: parent.textHeight)
            updateMentionPickerContent()
            updateLinkPreviewViewIfNecessary()
            updateWithMarkdown(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.input.value.selectedRange = textView.selectedRange
            updateMentionPickerContent()
        }

        // MARK: Link Preview
        private func updateLinkPreviewViewIfNecessary() {
            if let url = detectLink() {
                parent.link = url.absoluteString
            } else {
                parent.link = ""
            }
        }

        private func detectLink() -> URL? {
            let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let text = parent.input.value.text
            let matches = linkDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let url = text[range]
                if let url = URL(string: String(url)) {
                    // We only care about the first link
                    return url
                }
            }
            return nil
        }
    }
}

fileprivate struct LinkPreview: UIViewRepresentable {

    @Binding var link: String
    var linkPreviewData: GenericObservable<LinkPreviewData?>
    var linkPreviewImage: GenericObservable<UIImage?>

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PostComposerLinkPreviewView {
        DDLogInfo("TextView/makeUIView")
        let linkView = PostComposerLinkPreviewView() { resetLink, linkPreviewData, linkPreviewImage in
            DispatchQueue.main.async {
                if resetLink {
                    link = ""
                }
                self.linkPreviewImage.value = linkPreviewImage
                self.linkPreviewData.value = linkPreviewData
            }
        }
        return linkView
    }

    func updateUIView(_ uiView: PostComposerLinkPreviewView, context: Context) {
        uiView.updateLink(url: URL(string: link))
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: LinkPreview

        init(_ view: LinkPreview) {
            parent = view
        }
    }
}

fileprivate struct MediaPreviewSlider: UIViewRepresentable {
    @EnvironmentObject var configuration: PostComposerViewConfiguration
    @Binding var mediaItems: [PendingMedia]
    @Binding var shouldAutoPlay: Bool
    @Binding var presentMediaPicker: Bool
    var currentPosition: GenericObservable<Int>
    let onDelete: () -> Void
    let onCrop: () -> Void

    private var feedMediaItems: [FeedMedia] {
        mediaItems.map { FeedMedia($0, feedPostId: "") }
    }

    func makeUIView(context: Context) -> MediaCarouselView {
        DDLogInfo("MediaPreviewSlider/makeUIView")
        _ = context.coordinator.apply(media: mediaItems)

        var configuration = MediaCarouselViewConfiguration.composer
        configuration.gutterWidth = PostComposerLayoutConstants.horizontalPadding
        configuration.supplementaryViewsProvider = { index in
            let deleteBackground = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 1)
            deleteBackground.translatesAutoresizingMaskIntoConstraints = false
            deleteBackground.isUserInteractionEnabled = false

            let deleteImageConfiguration = UIImage.SymbolConfiguration(weight: .heavy)
            let deleteImage = UIImage(systemName: "xmark", withConfiguration: deleteImageConfiguration)?.withTintColor(.white, renderingMode: .alwaysOriginal)

            let deleteButton = UIButton(type: .custom)
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            deleteButton.setImage(deleteImage, for: .normal)
            deleteButton.layer.cornerRadius = PostComposerLayoutConstants.controlRadius
            deleteButton.clipsToBounds = true
            deleteButton.addTarget(context.coordinator, action: #selector(context.coordinator.deleteAction), for: .touchUpInside)
            deleteButton.insertSubview(deleteBackground, at: 0)
            if let imageView = deleteButton.imageView {
                deleteButton.bringSubviewToFront(imageView)
            }

            deleteBackground.constrain(to: deleteButton)
            NSLayoutConstraint.activate([
                deleteButton.widthAnchor.constraint(equalToConstant: PostComposerLayoutConstants.controlSize),
                deleteButton.heightAnchor.constraint(equalToConstant: PostComposerLayoutConstants.controlSize)
            ])

            let editBackground = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 1)
            editBackground.translatesAutoresizingMaskIntoConstraints = false
            editBackground.isUserInteractionEnabled = false

            let editImageConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
            let editImage = UIImage(systemName: "pencil.circle.fill", withConfiguration: editImageConfiguration)?.withTintColor(.white, renderingMode: .alwaysOriginal)

            let editButton = UIButton(type: .custom)
            editButton.translatesAutoresizingMaskIntoConstraints = false
            editButton.setImage(editImage, for: .normal)
            editButton.setTitle(Localizations.edit, for: .normal)
            editButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
            editButton.layer.cornerRadius = PostComposerLayoutConstants.controlRadius
            editButton.clipsToBounds = true
            editButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
            editButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 1, right: 6)
            editButton.addTarget(context.coordinator, action: #selector(context.coordinator.cropAction), for: .touchUpInside)
            editButton.insertSubview(editBackground, at: 0)
            if let imageView = editButton.imageView {
                editButton.bringSubviewToFront(imageView)
            }
            if let titleLabel = editButton.titleLabel {
                editButton.bringSubviewToFront(titleLabel)
            }
            
            editButton.isHidden = self.configuration.isMoment

            editBackground.constrain(to: editButton)
            NSLayoutConstraint.activate([
                editButton.heightAnchor.constraint(equalToConstant: PostComposerLayoutConstants.controlSize)
            ])

            let topTrailingActions = UIStackView(arrangedSubviews: [deleteButton])
            topTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            topTrailingActions.axis = .horizontal
            topTrailingActions.isLayoutMarginsRelativeArrangement = true
            topTrailingActions.layoutMargins = UIEdgeInsets(top: PostComposerLayoutConstants.controlSpacing, left: 0, bottom: 0, right: PostComposerLayoutConstants.controlSpacing)

            let bottomTrailingActions = UIStackView(arrangedSubviews: [editButton])
            bottomTrailingActions.translatesAutoresizingMaskIntoConstraints = false
            bottomTrailingActions.axis = .horizontal
            bottomTrailingActions.isLayoutMarginsRelativeArrangement = true
            bottomTrailingActions.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: PostComposerLayoutConstants.controlSpacing, right: PostComposerLayoutConstants.controlSpacing)

            return [
                MediaCarouselSupplementaryItem(anchors: [.top, .trailing], view: topTrailingActions),
                MediaCarouselSupplementaryItem(anchors: [.bottom, .trailing], view: bottomTrailingActions),
            ]
        }
        configuration.pageControlViewsProvider = { numberOfPages in
            var items: [MediaCarouselSupplementaryItem] = []
            guard !self.configuration.isMoment else {
                // no paging for moments
                return items
            }
            
            if numberOfPages == 1 {
                let button = UIButton(type: .system)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.setTitle(Localizations.addMore, for: .normal)
                button.setTitleColor(.label.withAlphaComponent(0.4), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14)
                button.addTarget(context.coordinator, action: #selector(context.coordinator.moreAction), for: .touchUpInside)

                items.append(MediaCarouselSupplementaryItem(anchors: [.trailing], view: button))
            }

            if numberOfPages < 10 {
                let imageConf = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                let image = UIImage(systemName: "plus", withConfiguration: imageConf)
                let moreButton = UIButton(type: .custom)
                moreButton.translatesAutoresizingMaskIntoConstraints = false
                moreButton.setImage(image?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
                moreButton.setBackgroundColor(.composerMore, for: .normal)
                moreButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
                moreButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
                moreButton.layer.cornerRadius = 14
                moreButton.layer.masksToBounds = true
                moreButton.addTarget(context.coordinator, action: #selector(context.coordinator.moreAction), for: .touchUpInside)

                items.append(MediaCarouselSupplementaryItem(anchors: [.trailing], view: moreButton))
            }

            return items
        }

        let carouselView = MediaCarouselView(media: feedMediaItems, configuration: configuration)
        carouselView.delegate = context.coordinator
        carouselView.shouldAutoPlay = shouldAutoPlay

        return carouselView
    }

    func updateUIView(_ uiView: MediaCarouselView, context: Context) {
        DDLogInfo("MediaPreviewSlider/updateUIView")
        uiView.shouldAutoPlay = shouldAutoPlay

        let count = context.coordinator.mediaCount
        if context.coordinator.apply(media: mediaItems) {
            // only animate adding/removing of media items
            uiView.refreshData(media: feedMediaItems, index: currentPosition.value, animated: count != mediaItems.count)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: MediaCarouselViewDelegate {
        private struct MediaState: Equatable {
            public var order: Int
            public var type: CommonMediaType
            public var originalVideoURL: URL?
            public var fileURL: URL?
            public var asset: PHAsset?
            public var edit: PendingMediaEdit?
            public var videoEdit: PendingVideoEdit?

            init(media: PendingMedia) {
                order = media.order
                type = media.type
                originalVideoURL = media.originalVideoURL
                fileURL = media.fileURL
                asset = media.asset
                edit = media.edit
                videoEdit = media.videoEdit
            }
        }

        private var parent: MediaPreviewSlider
        private var state: [MediaState]?

        public var mediaCount: Int {
            state?.count ?? 0
        }

        init(_ view: MediaPreviewSlider) {
            parent = view
        }

        func apply(media: [PendingMedia]) -> Bool {
            let newState = media.map { MediaState(media: $0) }

            guard let currentState = state else {
                state = newState
                return true
            }

            if currentState.count != newState.count {
                state = newState
                return true
            }

            for (i, item) in newState.enumerated() {
                if currentState[i] != item {
                    state = newState

                    // don't need to refresh the carousel media on url change
                    // it handles this case itself
                    return currentState[i].fileURL != nil
                }
            }

            return false
        }

        func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
            parent.currentPosition.value = newIndex
        }

        func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
            PostComposerView.stopTextEdit()
        }

        func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {

        }

        func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {

        }

        @objc func moreAction() {
            parent.presentMediaPicker = true
        }

        @objc func deleteAction() {
            parent.onDelete()
        }

        @objc func cropAction() {
            parent.onCrop()
        }
    }
}

fileprivate struct Picker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    @Binding var mediaItems: [PendingMedia]
    let complete: ([PendingMedia], Bool) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        DDLogInfo("Picker/makeUIViewController")
        MediaCarouselView.stopAllPlayback()
        let controller = MediaPickerViewController(config: .more, selected: mediaItems) { controller, _, media, cancel in
            self.complete(media, cancel)
        }

        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        DDLogInfo("Picker/updateUIViewController")
    }
}
