import AVFoundation
import Core
import CocoaLumberjackSwift
import Combine
import PhotosUI
import SwiftUI
import UIKit

protocol PostComposerViewDelegate: AnyObject {
    func composerDidTapShare(controller: PostComposerViewController, destination: PostComposerDestination, mentionText: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia: PendingMedia?)
    func composerDidTapBack(controller: PostComposerViewController, media: [PendingMedia])
    func willDismissWithInput(mentionInput: MentionInput)
}

enum PostComposerDestination: Equatable {
    case userFeed
    case groupFeed(GroupID)
    case chat(UserID?)
}

struct PostComposerViewConfiguration {
    var destination: PostComposerDestination = .userFeed
    var mentionableUsers: [MentionableUser]
    var useTransparentNavigationBar = false
    var mediaCarouselMaxAspectRatio: CGFloat = 1.25
    var mediaEditMaxAspectRatio: CGFloat?
    var imageServerMaxAspectRatio: CGFloat? = 1.25
    var maxVideoLength: TimeInterval = 500

    static var userPost: PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            mentionableUsers: Mentions.mentionableUsersForNewPost(),
            useTransparentNavigationBar: true,
            maxVideoLength: ServerProperties.maxFeedVideoDuration
        )
    }

    static func groupPost(id groupID: GroupID) -> PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .groupFeed(groupID),
            mentionableUsers: Mentions.mentionableUsers(forGroupID: groupID),
            useTransparentNavigationBar: true,
            maxVideoLength: ServerProperties.maxFeedVideoDuration
        )
    }

    static func message(id userId: UserID?) -> PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            destination: .chat(userId),
            mentionableUsers: [],
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

struct NavigationBarState {
    var standardAppearance: UINavigationBarAppearance
    var isTranslucent: Bool
    var backgroundColor: UIColor?
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
    private let isInitiallyVoiceNotePost: Bool

    private var barState: NavigationBarState?
    
    private var cancellableSet: Set<AnyCancellable> = []

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        configuration: PostComposerViewConfiguration,
        isInitiallyVoiceNotePost: Bool,
        delegate: PostComposerViewDelegate)
    {
        self.mediaItems.value = media
        self.isMediaPost = media.count > 0
        self.inputToPost = GenericObservable(initialInput)
        self.link = GenericObservable("")
        self.linkPreviewData = GenericObservable(nil)
        self.linkPreviewImage = GenericObservable(nil)
        self.configuration = configuration
        self.isInitiallyVoiceNotePost = isInitiallyVoiceNotePost
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaToPost:standalonePicker:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        postComposerView = PostComposerView(
            mediaItems: mediaItems,
            inputToPost: inputToPost,
            link: link,
            linkPreviewData: linkPreviewData,
            linkPreviewImage: linkPreviewImage,
            audioComposerRecorder: audioComposerRecorder,
            isInitiallyVoiceNotePost: isInitiallyVoiceNotePost,
            mentionableUsers: configuration.mentionableUsers,
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
            changeDestination: { [weak self] completion in
                guard let self = self else { return }

                let controller = ChangeDestinationViewController(destination: self.configuration.destination) { controller, destination in
                    controller.dismiss(animated: true)
                    self.configuration.destination = destination
                    completion(destination)
                }

                self.present(UINavigationController(rootViewController: controller), animated: true)
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
            }
        )

        let postComposerViewController = UIHostingController(rootView: postComposerView)
        addChild(postComposerViewController)
        view.addSubview(postComposerViewController.view)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.backgroundColor = .feedBackground
        postComposerViewController.view.constrain(to: view)
        postComposerViewController.didMove(toParent: self)

        switch configuration.destination {
        case .chat(_):
            title = Localizations.newMessageTitle
        default:
            title = Localizations.newPostTitle
        }

        navigationItem.leftBarButtonItem =
            UIBarButtonItem(image: isMediaPost ? backIcon : closeIcon, style: .plain, target: self, action: #selector(backAction))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard configuration.useTransparentNavigationBar, let navigationController = navigationController else { return }

        barState = NavigationBarState(
            standardAppearance: navigationController.navigationBar.standardAppearance,
            isTranslucent: navigationController.navigationBar.isTranslucent,
            backgroundColor: navigationController.navigationBar.backgroundColor)

        navigationController.navigationBar.standardAppearance = .translucentAppearance
        navigationController.navigationBar.isTranslucent = true
        navigationController.navigationBar.backgroundColor = .clear
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        delegate?.willDismissWithInput(mentionInput: inputToPost.value)

        guard configuration.useTransparentNavigationBar, let navigationController = navigationController, let barState = barState else { return }
        navigationController.navigationBar.standardAppearance = barState.standardAppearance
        navigationController.navigationBar.isTranslucent = barState.isTranslucent
        navigationController.navigationBar.backgroundColor = barState.backgroundColor
    }

    @objc private func backAction() {
        delegate?.composerDidTapBack(controller: self, media: self.mediaItems.value)
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
            delegate?.composerDidTapShare(controller: self, destination: configuration.destination, mentionText: mentionText, media: allMediaItems, linkPreviewData: linkPreviewData.value, linkPreviewMedia: nil)
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
            self.delegate?.composerDidTapShare(controller: self, destination: configuration.destination, mentionText: mentionText, media: mediaItems, linkPreviewData: linkPreviewData.value, linkPreviewMedia: linkPreviewMedia)
        } else {
            self.cancellableSet.insert(
                linkPreviewMedia.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }
                    self.delegate?.composerDidTapShare(controller: self, destination: self.configuration.destination, mentionText: mentionText, media: mediaItems, linkPreviewData: self.linkPreviewData.value, linkPreviewMedia: linkPreviewMedia)
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
    static let controlSpacing: CGFloat = 12
    static let controlRadius: CGFloat = 18
    static let controlXSpacing: CGFloat = 20
    static let controlSize: CGFloat = 36
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
    private let mediaCarouselMaxAspectRatio: CGFloat
    private let maxVideoLength: TimeInterval
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    @ObservedObject private var link: GenericObservable<String>
    @ObservedObject private var linkPreviewData: GenericObservable<LinkPreviewData?>
    @ObservedObject private var linkPreviewImage: GenericObservable<UIImage?>
    @ObservedObject private var audioComposerRecorder: AudioComposerRecorder
    private let isInitiallyVoiceNotePost: Bool
    @ObservedObject private var shouldAutoPlay: GenericObservable<Bool>
    @ObservedObject private var isPosting = GenericObservable<Bool>(false)
    private let mentionableUsers: [MentionableUser]
    private let changeDestination: (@escaping (PostComposerDestination) -> Void) -> Void
    private let crop: (Int, @escaping ([PendingMedia], Int, Bool) -> Void) -> Void
    private let goBack: () -> Void
    private let share: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = GenericObservable(0)
    @ObservedObject private var postTextHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var postTextComputedHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var privacySettings: PrivacySettings
    @State private var pendingMention: PendingMention? = nil
    @State private var presentPicker = false
    @State private var videoTooLong = false
    @State private var destination: PostComposerDestination = .userFeed
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
        isInitiallyVoiceNotePost: Bool,
        mentionableUsers: [MentionableUser],
        shouldAutoPlay: GenericObservable<Bool>,
        configuration: PostComposerViewConfiguration,
        crop: @escaping (Int, @escaping ([PendingMedia], Int, Bool) -> Void) -> Void,
        changeDestination: @escaping (@escaping(PostComposerDestination) -> Void) -> Void,
        goBack: @escaping () -> Void,
        share: @escaping () -> Void
    ) {
        self.privacySettings = MainAppContext.shared.privacySettings
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
        self.link = link
        self.linkPreviewData = linkPreviewData
        self.linkPreviewImage = linkPreviewImage
        self.audioComposerRecorder = audioComposerRecorder
        self.isInitiallyVoiceNotePost = isInitiallyVoiceNotePost
        self.mentionableUsers = mentionableUsers
        self.shouldAutoPlay = shouldAutoPlay
        self.mediaCarouselMaxAspectRatio = configuration.mediaCarouselMaxAspectRatio
        self.maxVideoLength = configuration.maxVideoLength
        self.changeDestination = changeDestination
        self.crop = crop
        self.goBack = goBack
        self.share = share
        self._destination = State(initialValue: configuration.destination)

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

    private func changeDestinationButtonText() -> String {
        switch destination {
        case .userFeed:
            return PrivacyList.name(forPrivacyListType: privacySettings.activeType ?? .all)
        case .groupFeed(let groupId):
            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                return group.name
            }
        case .chat(let userId):
            if let userId = userId {
                let name = MainAppContext.shared.contactStore.fullName(for: userId)
                return Localizations.newMessageSubtitle(recipient: name)
            }
        }

        return ""
    }

    private func allowChangingDestination() -> Bool {
        switch destination {
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

    var controls: some View {
        HStack {
            Button(action: addMedia) {
                ControlIconView(imageLabel: "ComposerAddMedia")
            }.sheet(isPresented: $presentPicker) {
                picker
                    .edgesIgnoringSafeArea(.bottom)
            }

            Spacer()

            Button(action: deleteMedia) {
                ControlIconView(imageLabel: "ComposerDeleteMedia")
            }

            if mediaState.isReady && showCropButton {
                Button(action: cropMedia) {
                    ControlIconView(imageLabel: "ComposerCropMedia")
                }
                .padding(.leading, PostComposerLayoutConstants.controlXSpacing)
            }
        }
        .padding(.horizontal, PostComposerLayoutConstants.controlSpacing)
        .offset(y: -controlYOffset)
    }

    var postTextView: some View {
        VStack(spacing: 0) {
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
                    mentionableUsers: mentionableUsers,
                    textHeight: postTextHeight,
                    shouldFocusOnLoad: mediaCount == 0)
                    .frame(height: postTextComputedHeight.value)
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
        .disabled(!isReadyToShare || isPosting.value)
    }

    var audioRecordingView: some View {
        return AudioPostComposer(recorder: audioComposerRecorder,
                                 isReadyToShare: isReadyToShare,
                                 shareAction: share,
                                 presentMediaPicker: $presentPicker,
                                 mediaPicker: { picker })
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                changeDestination { destination in
                    self.destination = destination
                }
            }) {
                Text(changeDestinationButtonText())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .offset(y: -1)

                if allowChangingDestination() {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .frame(height: 25)
            .padding(EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 11))
            .background(Color.blue)
            .cornerRadius(12)
            .offset(y: -1)
            .disabled(!allowChangingDestination())

            GeometryReader { scrollGeometry in
                ScrollView {
                    VStack {
                        VStack (alignment: .center) {
                            if self.mediaCount > 0 {
                                ZStack(alignment: .bottom) {
                                    MediaPreviewSlider(
                                        mediaItems: self.mediaItemsBinding,
                                        shouldAutoPlay: self.shouldAutoPlayBinding,
                                        currentPosition: self.currentPosition)
                                    .frame(height: self.getMediaSliderHeight(width: scrollGeometry.size.width), alignment: .center)

                                    self.controls
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
                            } else if isInitiallyVoiceNotePost {
                                audioRecordingView
                            } else {
                                ScrollView {
                                    postTextView
                                }
                                .frame(maxHeight: min(
                                    PostComposerLayoutConstants.postTextNoMediaMinHeight + PostComposerLayoutConstants.sendButtonHeight,
                                    scrollGeometry.size.height - 2 * PostComposerLayoutConstants.sendButtonHeight
                                ))

                                HStack {
                                    Button(action: addMedia) {
                                        Image("icon_add_photo")
                                            .renderingMode(.template)
                                            .foregroundColor(.blue)
                                    }
                                    .sheet(isPresented: $presentPicker) {
                                        picker
                                            .edgesIgnoringSafeArea(.bottom)
                                    }
                                    .padding(.leading, 10)

                                    Spacer()
                                    shareButton
                                }
                                .padding(12)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius))
                        .background(
                            RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0 : 0.08), radius: 8, y: 8))
                        .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding)
                        .padding(.vertical, PostComposerLayoutConstants.verticalPadding)
                    }
                    .frame(minHeight: scrollGeometry.size.height)
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
                        AudioComposerPlayer(configuration: .composerWithMedia, recorder: audioComposerRecorder)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                postTextView
                                    // hide vs remove to maintain sizing
                                    .opacity(audioComposerRecorder.recorderControlsExpanded ? 0 : 1)
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
                                                    .foregroundColor(.primaryBlue)
                                            }
                                            .padding(.leading, -6)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .zIndex(1)
                            if inputToPost.value.text.isEmpty, !audioComposerRecorder.recorderControlsLocked {
                                AudioComposerRecorderControl(recorder: audioComposerRecorder)
                                    .frame(width: 24, height: 24)
                                    .padding(.horizontal, PostComposerLayoutConstants.postTextHorizontalPadding)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.postTextRadius)
                                        .fill(Color(.secondarySystemGroupedBackground)))
                        .compositingGroup()
                        .shadow(color: .black.opacity(self.colorScheme == .dark ? 0 : 0.04), radius: 2, y: 1)
                    }
                    shareButton
                        .offset(y: -2)
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.feedBackground)
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

    private func addMedia() {
        presentPicker = true
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
        mediaItems.remove(index: currentPosition.value)
        if (mediaCount == 0) {
            goBack()
        }
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

fileprivate struct ControlIconView: View {
    let imageLabel: String

    var body: some View {
        Image(imageLabel)
            .renderingMode(.template)
            .foregroundColor(.white)
            .frame(width: PostComposerLayoutConstants.controlSize, height: PostComposerLayoutConstants.controlSize)
            .background(
                RoundedRectangle(cornerRadius: PostComposerLayoutConstants.controlRadius)
                    .fill(Color(.composerButton))
            )
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
    @Binding var mediaItems: [PendingMedia]
    @Binding var pendingMention: PendingMention?
    @Binding var link: String
    var input: GenericObservable<MentionInput>
    let mentionableUsers: [MentionableUser]
    var textHeight: GenericObservable<CGFloat>
    var shouldFocusOnLoad: Bool

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

        init(_ uiTextView: TextView) {
            parent = uiTextView
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
            return parent.mentionableUsers.filter {
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
    @Binding var mediaItems: [PendingMedia]
    @Binding var shouldAutoPlay: Bool
    var currentPosition: GenericObservable<Int>

    private var feedMediaItems: [FeedMedia] {
        mediaItems.map { FeedMedia($0, feedPostId: "") }
    }

    func makeUIView(context: Context) -> MediaCarouselView {
        DDLogInfo("MediaPreviewSlider/makeUIView")
        _ = context.coordinator.apply(media: mediaItems)

        var configuration = MediaCarouselViewConfiguration.composer
        configuration.gutterWidth = PostComposerLayoutConstants.horizontalPadding

        let carouselView = MediaCarouselView(media: feedMediaItems, configuration: configuration)
        carouselView.delegate = context.coordinator
        carouselView.shouldAutoPlay = shouldAutoPlay

        return carouselView
    }

    func updateUIView(_ uiView: MediaCarouselView, context: Context) {
        DDLogInfo("MediaPreviewSlider/updateUIView")
        uiView.shouldAutoPlay = shouldAutoPlay

        if context.coordinator.apply(media: mediaItems) {
            uiView.refreshData(media: feedMediaItems, index: currentPosition.value, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: MediaCarouselViewDelegate {
        private struct MediaState: Equatable {
            public var order: Int
            public var type: FeedMediaType
            public var image: UIImage?
            public var originalVideoURL: URL?
            public var fileURL: URL?
            public var asset: PHAsset?
            public var edit: PendingMediaEdit?
            public var videoEdit: PendingVideoEdit?

            init(media: PendingMedia) {
                order = media.order
                type = media.type
                image = media.image
                originalVideoURL = media.originalVideoURL
                fileURL = media.fileURL
                asset = media.asset
                edit = media.edit
                videoEdit = media.videoEdit
            }
        }

        private var parent: MediaPreviewSlider
        private var state: [MediaState]?

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
                    return true
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
    }
}

fileprivate struct Picker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    @Binding var mediaItems: [PendingMedia]
    let complete: ([PendingMedia], Bool) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        DDLogInfo("Picker/makeUIViewController")
        MediaCarouselView.stopAllPlayback()
        let controller = MediaPickerViewController(selected: mediaItems) { controller, media, cancel in
            self.complete(media, cancel)
        }

        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        DDLogInfo("Picker/updateUIViewController")
    }
}
