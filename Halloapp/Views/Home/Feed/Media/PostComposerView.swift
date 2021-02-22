import AVFoundation
import Core
import CocoaLumberjack
import Combine
import PhotosUI
import SwiftUI
import UIKit

protocol PostComposerViewDelegate: AnyObject {
    func composerDidTapShare(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia])
    func composerDidTapBack(controller: PostComposerViewController, media: [PendingMedia])
    func willDismissWithInput(mentionInput: MentionInput)
}

struct PostComposerViewConfiguration {
    var titleMode: PostComposerViewController.TitleMode = .userPost
    var mentionableUsers: [MentionableUser]
    var showAddMoreMediaButton = true
    var useTransparentNavigationBar = false
    var mediaCarouselMaxAspectRatio: CGFloat = 1.25
    var mediaEditMaxAspectRatio: CGFloat = 1.25
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
            titleMode: .groupPost,
            mentionableUsers: Mentions.mentionableUsers(forGroupID: groupID),
            useTransparentNavigationBar: true,
            maxVideoLength: ServerProperties.maxFeedVideoDuration
        )
    }

    static var message: PostComposerViewConfiguration {
        PostComposerViewConfiguration(
            titleMode: .message,
            mentionableUsers: [],
            mediaCarouselMaxAspectRatio: 1.0,
            mediaEditMaxAspectRatio: 100,
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
        NSLocalizedString("composer.max.video.length.message", value: "Please select another video.", comment: "Alert message in composer when a video is too long")
    }
}

class PostComposerViewController: UIViewController {
    enum TitleMode {
        case userPost
        case groupPost
        case message
    }

    private let privacySettings = MainAppContext.shared.privacySettings
    private var privacySubscription: AnyCancellable?

    let backIcon = UIImage(named: "NavbarBack")
    let closeIcon = UIImage(named: "NavbarClose")
    var imageServer: ImageServer?

    private var isPosting = false
    private var isReadyToShare = false

    private let mediaItems = ObservableMediaItems()
    private var inputToPost: GenericObservable<MentionInput>
    private var recipientName: String?
    private var shouldAutoPlay = GenericObservable(false)
    private var postComposerView: PostComposerView?
    private var shareButton: UIBarButtonItem!
    private let isMediaPost: Bool
    private let configuration: PostComposerViewConfiguration
    private weak var delegate: PostComposerViewDelegate?

    private var barState: NavigationBarState?

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        recipientName: String? = nil,
        configuration: PostComposerViewConfiguration,
        delegate: PostComposerViewDelegate)
    {
        self.mediaItems.value = media
        self.isMediaPost = media.count > 0
        self.inputToPost = GenericObservable(initialInput)
        self.recipientName = recipientName
        self.configuration = configuration
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
            mentionableUsers: configuration.mentionableUsers,
            shouldAutoPlay: shouldAutoPlay,
            configuration: configuration,
            prepareImages: { [weak self] isReady, imagesAreProcessed, numberOfFailedItems in
                guard let self = self else { return }
                self.imageServer?.cancel()

                self.imageServer = ImageServer(maxAllowedAspectRatio: self.configuration.imageServerMaxAspectRatio)
                self.imageServer!.prepare(mediaItems: self.mediaItems.value, isReady: isReady, imagesAreProcessed: imagesAreProcessed, numberOfFailedItems: numberOfFailedItems)
            },
            crop: { [weak self] index in
                guard let self = self else { return }

                let editController: UIViewController
                let media = self.mediaItems.value[index.value]

                if media.type == .image {
                    editController = MediaEditViewController(mediaToEdit: self.mediaItems.value, selected: index.value, maxAspectRatio: self.configuration.mediaEditMaxAspectRatio) { controller, media, selected, cancel in
                        controller.dismiss(animated: true)

                        guard !cancel else { return }

                        index.value = selected
                        self.mediaItems.value = media

                        if media.count == 0 {
                            self.backAction()
                        }
                    }
                } else {
                    MediaCarouselView.stopAllPlayback()
                    editController = VideoEditViewController(media: media) { controller, media, cancel in
                        controller.dismiss(animated: true)
                        guard !cancel else { return }
                        media.isResized = false
                        self.mediaItems.value[index.value] = media
                    }.withNavigationController()
                }
                
                editController.modalPresentationStyle = .fullScreen
                self.present(editController, animated: true)
            },
            goBack: { [weak self] in self?.backAction() },
            setReadyToShare: { [weak self] isReady in
                self?.isReadyToShare = isReady
                self?.updateShareButton()
            }
        )

        let postComposerViewController = UIHostingController(rootView: postComposerView)
        addChild(postComposerViewController)
        view.addSubview(postComposerViewController.view)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.backgroundColor = .feedBackground
        postComposerViewController.view.constrain(to: view)
        postComposerViewController.didMove(toParent: self)

        let titleView = TitleView()
        let shareTitle = NSLocalizedString("composer.post.button.share", value: "Share", comment: "Share button title.")
        shareButton = UIBarButtonItem(title: shareTitle, style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue
        navigationItem.rightBarButtonItem = shareButton
        navigationItem.rightBarButtonItem!.isEnabled = false

        switch configuration.titleMode {
        case .userPost:
            titleView.titleLabel.text = NSLocalizedString("composer.post.title", value: "New Post", comment: "Composer New Post title.")
            titleView.subtitleLabel.text = privacySettings?.composerIndicator ?? ""
            privacySubscription = privacySettings?.$composerIndicator.assign(to: \.text!, on: titleView.subtitleLabel)
        case .groupPost:
            titleView.titleLabel.text = NSLocalizedString("composer.post.title", value: "New Post", comment: "Composer New Post title.")
            if let recipientName = recipientName {
                let formatString = NSLocalizedString("composer.post.subtitle", value: "Sharing with %@", comment: "Composer subtitle for group posts.")
                titleView.subtitleLabel.text = String.localizedStringWithFormat(formatString, recipientName)
            } else {
                titleView.isHidden = true
            }
        case .message:
            titleView.titleLabel.text = NSLocalizedString("composer.message.title", value: "New Message", comment: "Composer New Message title.")
            if let recipientName = recipientName {
                let formatString = NSLocalizedString("composer.message.subtitle", value: "Sending to %@", comment: "Composer subtitle for messages.")
                titleView.subtitleLabel.text = String.localizedStringWithFormat(formatString, recipientName)
            } else {
                titleView.isHidden = true
            }
            shareButton.title = NSLocalizedString("composer.post.button.send", value: "Send", comment: "Send button title.")
        }

        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem =
            UIBarButtonItem(image: isMediaPost ? backIcon : closeIcon, style: .plain, target: self, action: #selector(backAction))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldAutoPlay.value = true

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
        self.shouldAutoPlay.value = false
        delegate?.willDismissWithInput(mentionInput: inputToPost.value)

        guard configuration.useTransparentNavigationBar, let navigationController = navigationController, let barState = barState else { return }
        navigationController.navigationBar.standardAppearance = barState.standardAppearance
        navigationController.navigationBar.isTranslucent = barState.isTranslucent
        navigationController.navigationBar.backgroundColor = barState.backgroundColor
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil && isMediaPost {
            imageServer?.cancel()
        }
    }

    @objc private func shareAction() {
        isVideoLengthWithinLimit { [weak self] isWithinLimit in
            guard let self = self else { return }

            if isWithinLimit {
                self.share()
            } else {
                self.alertVideoLengthOverLimit()
            }
        }
    }

    @objc private func backAction() {
        if isMediaPost {
            imageServer?.cancel()
        }
        delegate?.composerDidTapBack(controller: self, media: self.mediaItems.value)
    }

    private func updateShareButton() {
        navigationItem.rightBarButtonItem?.isEnabled = isReadyToShare && !isPosting
    }

    private func share() {
        isPosting = true
        updateShareButton()
        let mentionText = MentionText(expandedText: inputToPost.value.text, mentionRanges: inputToPost.value.mentions).trimmed()
        delegate?.composerDidTapShare(controller: self, mentionText: mentionText, media: mediaItems.value)
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
                guard let url = item.videoURL else { continue }

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

fileprivate class TitleView: UIView {
    public var isShowingTypingIndicator: Bool = false

    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func showChatState(with typingIndicatorStr: String?) {
        let show: Bool = typingIndicatorStr != nil

        subtitleLabel.isHidden = show
        isShowingTypingIndicator = show
    }

    private func setup() {
        let vStack = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.distribution = .fillProportionally
        vStack.spacing = 0

        addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
    }

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        return label
    }()

    lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
}

fileprivate struct PostComposerLayoutConstants {
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let controlSpacing: CGFloat = 12
    static let controlRadius: CGFloat = 18
    static let controlXSpacing: CGFloat = 20
    static let controlSize: CGFloat = 36
    static let backgroundRadius: CGFloat = 20

    static let postTextHorizontalPadding = horizontalPadding + 12
    static let postTextVerticalPadding = verticalPadding + 4

    static let postTextNoMediaMinHeight: CGFloat = 265 - postTextVerticalPadding
    static let postTextUnfocusedMinHeight: CGFloat = 100 - postTextVerticalPadding
    static let postTextFocusedMinHeight: CGFloat = 80 - postTextVerticalPadding
    static let postTextMaxHeight: CGFloat = 250

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
    private let showAddMoreMediaButton: Bool
    private let mediaCarouselMaxAspectRatio: CGFloat
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    @ObservedObject private var shouldAutoPlay: GenericObservable<Bool>
    @ObservedObject private var isPosting = GenericObservable<Bool>(false)
    private let mentionableUsers: [MentionableUser]
    private let prepareImages: (Binding<Bool>, Binding<Bool>, Binding<Int>) -> Void
    private let crop: (GenericObservable<Int>) -> Void
    private let goBack: () -> Void
    private let setReadyToShare: (Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = GenericObservable(0)
    @ObservedObject private var postTextHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var postTextComputedHeight = GenericObservable<CGFloat>(0)
    @State private var pendingMention: PendingMention? = nil
    @State private var keyboardHeight: CGFloat = 0
    @State private var presentPicker = false
    @State private var imagesAreProcessed = false
    private var mediaItemsBinding = Binding.constant([PendingMedia]())
    private var mediaIsReadyBinding = Binding.constant(false)
    private var numberOfFailedItemsBinding = Binding.constant(0)
    private var shouldAutoPlayBinding = Binding.constant(false)

    private var keyboardHeightPublisher: AnyPublisher<CGFloat, Never> =
        Publishers.Merge3(
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
                .map { $0.height },
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
                .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
                .map { $0.height },
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .removeDuplicates()
        .eraseToAnyPublisher()

    private var readyToSharePublisher: AnyPublisher<Bool, Never>!
    private var pageChangedPublisher: AnyPublisher<Bool, Never>!
    private var postTextComputedHeightPublisher: AnyPublisher<CGFloat, Never>!

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
        mentionableUsers: [MentionableUser],
        shouldAutoPlay: GenericObservable<Bool>,
        configuration: PostComposerViewConfiguration,
        prepareImages: @escaping (Binding<Bool>, Binding<Bool>, Binding<Int>) -> Void,
        crop: @escaping (GenericObservable<Int>) -> Void,
        goBack: @escaping () -> Void,
        setReadyToShare: @escaping (Bool) -> Void)
    {
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
        self.mentionableUsers = mentionableUsers
        self.shouldAutoPlay = shouldAutoPlay
        self.showAddMoreMediaButton = configuration.showAddMoreMediaButton
        self.mediaCarouselMaxAspectRatio = configuration.mediaCarouselMaxAspectRatio
        self.prepareImages = prepareImages
        self.crop = crop
        self.goBack = goBack
        self.setReadyToShare = setReadyToShare

        readyToSharePublisher =
            Publishers.CombineLatest4(
                self.mediaItems.$value,
                self.mediaState.$isReady,
                self.mediaState.$numberOfFailedItems,
                self.inputToPost.$value
            )
            .map { (mediaItems, mediaIsReady, numberOfFailedUploads, inputValue) -> Bool in
                return (mediaItems.count > 0 && mediaIsReady && numberOfFailedUploads == 0) ||
                    (mediaItems.count == 0 && !inputValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        pageChangedPublisher =
            currentPosition.$value.removeDuplicates().map { _ in return true }.eraseToAnyPublisher()

        postTextComputedHeight.value = PostComposerView.computePostHeight(
            itemsCount: self.mediaItems.value.count, keyboardHeight: 0, postTextHeight: postTextHeight.value)

        postTextComputedHeightPublisher =
            Publishers.CombineLatest3(
                self.mediaItems.$value,
                self.keyboardHeightPublisher,
                self.postTextHeight.$value
            )
            .map { (mediaItems, keyboardHeight, postTextHeight) -> CGFloat in
                return PostComposerView.computePostHeight(
                    itemsCount: mediaItems.count, keyboardHeight: keyboardHeight, postTextHeight: postTextHeight)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        self.mediaItemsBinding = self.$mediaItems.value
        self.mediaIsReadyBinding = self.$mediaState.isReady
        self.numberOfFailedItemsBinding = self.$mediaState.numberOfFailedItems
        self.shouldAutoPlayBinding = self.$shouldAutoPlay.value
    }

    static func stopTextEdit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }

    private static func computePostHeight(itemsCount: Int, keyboardHeight: CGFloat, postTextHeight: CGFloat) -> CGFloat {
        var minPostHeight = PostComposerLayoutConstants.postTextNoMediaMinHeight
        if itemsCount > 0 {
            minPostHeight = keyboardHeight > 0 ?
                PostComposerLayoutConstants.postTextFocusedMinHeight : PostComposerLayoutConstants.postTextUnfocusedMinHeight
        }
        let maxPostHeight = itemsCount > 0 ? PostComposerLayoutConstants.postTextMaxHeight : CGFloat.infinity
        return min(maxPostHeight, max(minPostHeight, postTextHeight))
    }
    
    private func getMediaSliderHeight(width: CGFloat) -> CGFloat {
        return MediaCarouselView.preferredHeight(for: feedMediaItems, width: width - 4 * PostComposerLayoutConstants.horizontalPadding, maxAllowedAspectRatio: mediaCarouselMaxAspectRatio)
    }

    var picker: some View {
        Picker(mediaItems: mediaItemsBinding) { newMediaItems, cancel in
            presentPicker = false
            guard !cancel else { return }

            imagesAreProcessed = false
            mediaState.isReady = false

            let lastAsset = mediaItems.value[currentPosition.value].asset
            mediaItems.value = newMediaItems
            currentPosition.value = newMediaItems.firstIndex { $0.asset == lastAsset } ?? 0

            prepareImages($mediaState.isReady, $imagesAreProcessed, $mediaState.numberOfFailedItems)
        }
    }

    var controls: some View {
        HStack {
            if keyboardHeight == 0 {
                if showAddMoreMediaButton {
                    Button(action: addMedia) {
                        ControlIconView(imageLabel: "ComposerAddMedia")
                    }.sheet(isPresented: $presentPicker) {
                        picker
                    }
                }
                Spacer()
                Button(action: deleteMedia) {
                    ControlIconView(imageLabel: "ComposerDeleteMedia")
                }
                if imagesAreProcessed && showCropButton {
                    Button(action: cropMedia) {
                        ControlIconView(imageLabel: "ComposerCropMedia")
                    }
                    .padding(.leading, PostComposerLayoutConstants.controlXSpacing)
                }
            }
        }
        .padding(.horizontal, PostComposerLayoutConstants.controlSpacing)
        .offset(y: -controlYOffset)
    }

    var postTextView: some View {
        ZStack (alignment: .topLeading) {
            if (inputToPost.value.text.isEmpty) {
                Text(mediaCount > 0 ? Localizations.writeDescription : Localizations.writePost)
                    .font(Font(PostComposerLayoutConstants.getFontSize(
                        textSize: inputToPost.value.text.count, isPostWithMedia: mediaCount > 0)))
                    .foregroundColor(Color.primary.opacity(0.5))
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .frame(height: postTextComputedHeight.value, alignment: .topLeading)
            }
            TextView(
                mediaItems: mediaItemsBinding,
                pendingMention: $pendingMention,
                input: inputToPost,
                mentionableUsers: mentionableUsers,
                textHeight: postTextHeight)
                .frame(height: postTextComputedHeight.value)
        }
        .background(Color(mediaCount == 0 ? .secondarySystemGroupedBackground : .clear))
        .padding(.horizontal, PostComposerLayoutConstants.postTextHorizontalPadding)
        .padding(.vertical, PostComposerLayoutConstants.postTextVerticalPadding)
        .background(Color(mediaCount > 0 ? .secondarySystemGroupedBackground : .clear))
    }

    var body: some View {
        return GeometryReader { geometry in
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
                                    }
                                } else {
                                    self.postTextView
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius))
                            .background(
                                RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0 : 0.08), radius: 8, y: 8))
                            .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding)
                            .padding(.vertical, PostComposerLayoutConstants.verticalPadding)
                            .onAppear {
                                if (self.mediaCount > 0) {
                                    self.imagesAreProcessed = false
                                    self.mediaState.isReady = false
                                    self.prepareImages(self.$mediaState.isReady, $imagesAreProcessed, self.$mediaState.numberOfFailedItems)
                                } else {
                                    self.mediaState.isReady = true
                                }
                            }
                            .onReceive(self.readyToSharePublisher) { self.setReadyToShare($0) }
                            .onReceive(self.keyboardHeightPublisher) { self.keyboardHeight = $0 }
                            .onReceive(self.pageChangedPublisher) { _ in PostComposerView.stopTextEdit() }
                            .onReceive(self.postTextComputedHeightPublisher) { self.postTextComputedHeight.value = $0 }
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

                if self.mediaCount > 0 {
                    self.postTextView
                }

                Spacer().frame(height: keyboardHeight)
            }
            .background(Color.feedBackground)
            .edgesIgnoringSafeArea(.bottom)
        }
    }

    private func addMedia() {
        presentPicker = true
    }

    private func cropMedia() {
        imagesAreProcessed = false
        mediaState.isReady = false
        crop(currentPosition)
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

fileprivate struct TextView: UIViewRepresentable {
    @Binding var mediaItems: [PendingMedia]
    @Binding var pendingMention: PendingMention?
    var input: GenericObservable<MentionInput>
    let mentionableUsers: [MentionableUser]
    var textHeight: GenericObservable<CGFloat>

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        DDLogInfo("TextView/makeUIView")
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.inputAccessoryView = context.coordinator.mentionPicker
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = PostComposerLayoutConstants.getFontSize(
            textSize: input.value.text.count, isPostWithMedia: mediaItems.count > 0)
        textView.textColor = UIColor.label.withAlphaComponent(0.9)
        textView.text = input.value.text
        textView.textContainerInset.bottom = PostComposerLayoutConstants.postTextVerticalPadding
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context)  {
        DDLogInfo("TextView/updateUIView")

        // Don't set text or selection on uiView (it clears markedTextRange, which breaks IME)
        let fontToUse = PostComposerLayoutConstants.getFontSize(
            textSize: input.value.text.count, isPostWithMedia: mediaItems.count > 0)
        if uiView.font != fontToUse {
            uiView.font = fontToUse
        }

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

        TextView.recomputeHeight(textView: uiView, resultHeight: textHeight)
    }

    private static func recomputeHeight(textView: UIView, resultHeight: GenericObservable<CGFloat>) {
        let newSize = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))
        if resultHeight.value != newSize.height {
            DispatchQueue.main.async {
                resultHeight.value = newSize.height
            }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView

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
                return false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.input.value.text = textView.text ?? ""
            TextView.recomputeHeight(textView: textView, resultHeight: parent.textHeight)
            updateMentionPickerContent()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.input.value.selectedRange = textView.selectedRange
            updateMentionPickerContent()
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
        context.coordinator.apply(media: mediaItems)

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
            uiView.refreshData(media: feedMediaItems, index: currentPosition.value)
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
            public var videoURL: URL?
            public var fileURL: URL?
            public var asset: PHAsset?
            public var edit: PendingMediaEdit?
            public var videoEdit: PendingVideoEdit?

            init(media: PendingMedia) {
                order = media.order
                type = media.type
                image = media.image
                originalVideoURL = media.originalVideoURL
                videoURL = media.videoURL
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
