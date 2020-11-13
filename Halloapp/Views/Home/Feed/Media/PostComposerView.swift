import Core
import CocoaLumberjack
import Combine
import SwiftUI
import UIKit

protocol PostComposerViewDelegate: AnyObject {
    func composerShareAction(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia])
    func composerDidFinish(controller: PostComposerViewController, media: [PendingMedia], isBackAction: Bool)
    func willDismissWithInput(mentionInput: MentionInput)
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
    var backgroundImage: UIImage?
    var shadowImage: UIImage?
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
}

class PostComposerViewController: UIViewController {
    enum TitleMode {
        case post
        case message
    }

    private let privacySettings = MainAppContext.shared.privacySettings
    private var privacySubscription: AnyCancellable?

    let backIcon = UIImage(named: "NavbarBack")
    let closeIcon = UIImage(named: "NavbarClose")
    fileprivate let imageServer = ImageServer()

    private let titleMode: TitleMode
    private let showCancelButton: Bool
    private let mediaItems = ObservableMediaItems()
    private var inputToPost: GenericObservable<MentionInput>
    private var shouldAutoPlay = GenericObservable(false)
    private var postComposerView: PostComposerView?
    private var shareButton: UIBarButtonItem!
    private let isMediaPost: Bool
    private let disableMentions: Bool
    private let showAddMoreMediaButton: Bool
    private var useTransparentNavigationBar: Bool
    private weak var delegate: PostComposerViewDelegate?

    private var barState: NavigationBarState?
    private var blurView: UIVisualEffectView?

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        showCancelButton: Bool,
        titleMode: TitleMode = .post,
        disableMentions: Bool = false,
        showAddMoreMediaButton: Bool = true,
        useTransparentNavigationBar: Bool = false,
        delegate: PostComposerViewDelegate)
    {
        self.mediaItems.value = media
        self.isMediaPost = media.count > 0
        self.inputToPost = GenericObservable(initialInput)
        self.showCancelButton = showCancelButton
        self.titleMode = titleMode
        self.disableMentions = disableMentions
        self.showAddMoreMediaButton = showAddMoreMediaButton
        self.useTransparentNavigationBar = useTransparentNavigationBar
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaToPost:standalonePicker:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        postComposerView = PostComposerView(
            imageServer: imageServer,
            mediaItems: mediaItems,
            inputToPost: inputToPost,
            shouldAutoPlay: shouldAutoPlay,
            disableMentions: disableMentions,
            showAddMoreMediaButton: showAddMoreMediaButton,
            crop: { [weak self] index in
                guard let self = self else { return }
                let editController = MediaEditViewController(mediaToEdit: self.mediaItems.value, selected: index.value) { controller, media, selected, cancel in
                    controller.dismiss(animated: true)
                    
                    guard !cancel else { return }

                    index.value = selected
                    self.mediaItems.value = media
                    
                    if media.count == 0 {
                        self.backAction()
                    }
                }
                
                editController.modalPresentationStyle = .fullScreen
                self.present(editController, animated: true)
            },
            goBack: { [weak self] in self?.backAction() },
            setShareVisibility: { [weak self] visibility in self?.setShareVisibility(visibility) }
        )

        let postComposerViewController = UIHostingController(rootView: postComposerView)
        addChild(postComposerViewController)
        view.addSubview(postComposerViewController.view)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.backgroundColor =
            mediaItems.value.count > 0 ? .secondarySystemGroupedBackground : .feedBackground
        postComposerViewController.view.constrain(to: view)
        postComposerViewController.didMove(toParent: self)

        switch titleMode {
        case .post:
            let titleView = TitleView()
            titleView.titleLabel.text = NSLocalizedString("composer.post.title", value: "New Post", comment: "Composer New Post title.")
            titleView.subtitleLabel.text = privacySettings?.composerIndicator ?? ""
            privacySubscription = privacySettings?.$composerIndicator.assign(to: \.text!, on: titleView.subtitleLabel)
            navigationItem.titleView = titleView

        case .message:
            // Refactor with separate titleView for messages?
            let titleView = TitleView()
            titleView.titleLabel.text = NSLocalizedString("composer.message.title", value: "New Message", comment: "Composer New Message title.")
            titleView.subtitleLabel.isHidden = true
            navigationItem.titleView = titleView
        }

        navigationItem.leftBarButtonItem =
            UIBarButtonItem(image: isMediaPost ? backIcon : closeIcon, style: .plain, target: self, action: #selector(backAction))
        let shareTitle = NSLocalizedString("composer.post.button.share", value: "Share", comment: "Share button title.")
        shareButton = UIBarButtonItem(title: shareTitle, style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue
    }

    private func getNavigationStatusBarHeight() -> CGFloat {
        return navigationController?.view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldAutoPlay.value = true

        guard useTransparentNavigationBar, let navigationController = navigationController else { return }
        barState = NavigationBarState(
            backgroundImage: navigationController.navigationBar.backgroundImage(for: .default),
            shadowImage: navigationController.navigationBar.shadowImage,
            isTranslucent: navigationController.navigationBar.isTranslucent,
            backgroundColor: navigationController.navigationBar.backgroundColor)

        navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController.navigationBar.shadowImage = UIImage()
        navigationController.navigationBar.isTranslucent = true
        navigationController.navigationBar.backgroundColor = .clear

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = UIVisualEffectView(effect: blurEffect)
        blurredEffectView.frame = navigationController.navigationBar.bounds
        blurredEffectView.frame.size.height += getNavigationStatusBarHeight()
        blurredEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let barViewIndex = navigationController.view.subviews.firstIndex(of: navigationController.navigationBar)
        if barViewIndex != nil {
            navigationController.view.insertSubview(blurredEffectView, at: barViewIndex!)
            blurView = blurredEffectView
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.shouldAutoPlay.value = false
        delegate?.willDismissWithInput(mentionInput: inputToPost.value)
        blurView?.removeFromSuperview()

        guard useTransparentNavigationBar, let navigationController = navigationController, let barState = barState else { return }
        navigationController.navigationBar.setBackgroundImage(barState.backgroundImage, for: .default)
        navigationController.navigationBar.shadowImage = barState.shadowImage
        navigationController.navigationBar.isTranslucent = barState.isTranslucent
        navigationController.navigationBar.backgroundColor = barState.backgroundColor
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil && isMediaPost {
            imageServer.cancel()
        }
    }

    @objc private func shareAction() {
        let mentionText = MentionText(expandedText: inputToPost.value.text, mentionRanges: inputToPost.value.mentions).trimmed()
        delegate?.composerShareAction(controller: self, mentionText: mentionText, media: mediaItems.value)
        inputToPost.value.text = ""
        delegate?.composerDidFinish(controller: self, media: [], isBackAction: false)
    }

    @objc private func backAction() {
        if isMediaPost {
            imageServer.cancel()
        }
        delegate?.composerDidFinish(controller: self, media: self.mediaItems.value, isBackAction: true)
    }

    private func setShareVisibility(_ visibility: Bool) {
        if (visibility && navigationItem.rightBarButtonItem == nil) {
            navigationItem.rightBarButtonItem = shareButton
        } else if (!visibility && navigationItem.rightBarButtonItem != nil) {
            navigationItem.rightBarButtonItem = nil
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
        vStack.spacing = 0

        addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor).isActive = true
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
    static let postTextVerticalPadding = verticalPadding + 8

    static let postTextNoMediaMinHeight: CGFloat = 265 - postTextVerticalPadding
    static let postTextUnfocusedMinHeight: CGFloat = 100 - postTextVerticalPadding
    static let postTextFocusedMinHeight: CGFloat = 80 - postTextVerticalPadding
    static let postTextMaxHeight: CGFloat = 250

    static let fontSize: CGFloat = 16
    static let fontSizeLarge: CGFloat = 20

    static let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    static let smallFont = UIFont(descriptor: fontDescriptor, size: fontSize)
    static let largeFont = UIFont(descriptor: fontDescriptor, size: fontSizeLarge)

    static func getFontSize(textSize: Int, isPostWithMedia: Bool) -> UIFont {
        return isPostWithMedia || textSize > 180 ? smallFont : largeFont
    }
}

fileprivate struct PostComposerView: View {
    private let imageServer: ImageServer
    private let showAddMoreMediaButton: Bool
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    @ObservedObject private var shouldAutoPlay: GenericObservable<Bool>
    @ObservedObject private var areMentionsDisabled: GenericObservable<Bool>
    private let crop: (_ index: GenericObservable<Int>) -> Void
    private let goBack: () -> Void
    private let setShareVisibility: (Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = GenericObservable(0)
    @ObservedObject private var postTextHeight = GenericObservable<CGFloat>(0)
    @ObservedObject private var postTextComputedHeight = GenericObservable<CGFloat>(0)
    @State private var keyboardHeight: CGFloat = 0
    @State private var presentPicker = false

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

    private var shareVisibilityPublisher: AnyPublisher<Bool, Never>!
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
        currentPosition.value < mediaCount && mediaItems.value[currentPosition.value].type == FeedMediaType.image
    }

    static func stopTextEdit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }

    init(
        imageServer: ImageServer,
        mediaItems: ObservableMediaItems,
        inputToPost: GenericObservable<MentionInput>,
        shouldAutoPlay: GenericObservable<Bool>,
        disableMentions: Bool,
        showAddMoreMediaButton: Bool,
        crop: @escaping (_ index: GenericObservable<Int>) -> Void,
        goBack: @escaping () -> Void,
        setShareVisibility: @escaping (_ visibility: Bool) -> Void)
    {
        self.imageServer = imageServer
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
        self.shouldAutoPlay = shouldAutoPlay
        self.areMentionsDisabled = GenericObservable(disableMentions)
        self.showAddMoreMediaButton = showAddMoreMediaButton
        self.crop = crop
        self.goBack = goBack
        self.setShareVisibility = setShareVisibility

        shareVisibilityPublisher =
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
    
    private func getMediaSliderHeight(_ width: CGFloat) -> CGFloat {
        return MediaCarouselView.preferredHeight(for: feedMediaItems, width: width - 4 * PostComposerLayoutConstants.horizontalPadding)
    }

    var pageIndex: some View {
        HStack {
            if (mediaCount > 1) {
                PageIndexView(mediaItems: mediaItems, currentPosition: currentPosition)
                    .frame(height: 20, alignment: .trailing)
            }
        }
        .padding(.horizontal, 2 * PostComposerLayoutConstants.controlSpacing)
        .offset(y: 2 * PostComposerLayoutConstants.controlSpacing)
    }

    var picker: some View {
        Picker(mediaItems: mediaItems.value) { newMediaItems, cancel in
            presentPicker = false
            guard !cancel else { return }

            mediaState.isReady = false
            imageServer.cancel()

            let lastAsset = mediaItems.value[currentPosition.value].asset
            mediaItems.value = newMediaItems
            currentPosition.value = newMediaItems.firstIndex { $0.asset == lastAsset } ?? 0

            imageServer.prepare(mediaItems: mediaItems.value, isReady: $mediaState.isReady, numberOfFailedItems: $mediaState.numberOfFailedItems)
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
                if (showCropButton) {
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
            TextView(mediaItems: mediaItems, input: inputToPost, textHeight: postTextHeight, areMentionsDisabled: areMentionsDisabled)
                .frame(height: postTextComputedHeight.value)
        }
        .background(Color(mediaCount == 0 ? .secondarySystemGroupedBackground : .clear))
        .padding(.horizontal, PostComposerLayoutConstants.postTextHorizontalPadding)
        .padding(.vertical, PostComposerLayoutConstants.postTextVerticalPadding)
        .background(Color(mediaCount > 0 ? .secondarySystemGroupedBackground : .clear))
    }

    var body: some View {
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack {
                        VStack (alignment: .center) {
                            if self.mediaCount > 0 {
                                ZStack(alignment: .bottom) {
                                    MediaPreviewSlider(
                                        mediaItems: self.mediaItems,
                                        shouldAutoPlay: self.shouldAutoPlay,
                                        currentPosition: self.currentPosition)
                                    .frame(height: self.getMediaSliderHeight(geometry.size.width), alignment: .center)

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
                        .background(
                            RoundedRectangle(cornerRadius: PostComposerLayoutConstants.backgroundRadius)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0 : 0.08), radius: 8, y: 8))
                        .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding)
                        .padding(.vertical, PostComposerLayoutConstants.verticalPadding)
                        .onAppear {
                            if (self.mediaCount > 0) {
                                self.imageServer.prepare(mediaItems: self.mediaItems.value, isReady: self.$mediaState.isReady, numberOfFailedItems: self.$mediaState.numberOfFailedItems)
                            } else {
                                self.mediaState.isReady = true
                            }
                        }
                        .onReceive(self.shareVisibilityPublisher) { self.setShareVisibility($0) }
                        .onReceive(self.keyboardHeightPublisher) { self.keyboardHeight = $0 }
                        .onReceive(self.pageChangedPublisher) { _ in PostComposerView.stopTextEdit() }
                        .onReceive(self.postTextComputedHeightPublisher) { self.postTextComputedHeight.value = $0 }
                    }
                    .frame(minHeight: geometry.size.height - self.keyboardHeight - (self.mediaCount > 0 ? self.postTextComputedHeight.value : 0))
                }
            }

            if self.mediaCount > 0 {
                self.postTextView
            }
        }
        .background(Color.feedBackground)
        .padding(.bottom, self.keyboardHeight)
        .edgesIgnoringSafeArea(.bottom)
    }

    private func addMedia() {
        presentPicker = true
    }

    private func cropMedia() {
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

fileprivate struct PageIndexView: UIViewRepresentable {
    @ObservedObject var mediaItems: ObservableMediaItems
    @ObservedObject var currentPosition: GenericObservable<Int>

    private let strokeTextAttributes: [NSAttributedString.Key : Any] = [
        .strokeWidth: -0.5,
        .foregroundColor: UIColor.white,
        .strokeColor: UIColor.black.withAlphaComponent(0.4),
        .font: UIFont.gothamFont(ofSize: 17)
    ]

    private var attributedString: NSAttributedString {
        return NSAttributedString(
            string: "\(currentPosition.value + 1) / \(mediaItems.value.count)",
            attributes: strokeTextAttributes
        )
    }

    func makeUIView(context: Context) -> UILabel {
        let pageIndexLabel = UILabel()
        pageIndexLabel.textAlignment = .right
        pageIndexLabel.backgroundColor = .clear
        pageIndexLabel.attributedText = attributedString

        pageIndexLabel.layer.shadowColor = UIColor.black.cgColor
        pageIndexLabel.layer.shadowOffset = CGSize(width: 0, height: 0)
        pageIndexLabel.layer.shadowOpacity = 0.4
        pageIndexLabel.layer.shadowRadius = 2.0

        return pageIndexLabel
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = attributedString
    }
}

fileprivate struct TextView: UIViewRepresentable {
    @ObservedObject var mediaItems: ObservableMediaItems
    @ObservedObject var input: GenericObservable<MentionInput>
    @ObservedObject var textHeight: GenericObservable<CGFloat>
    @ObservedObject var areMentionsDisabled: GenericObservable<Bool>
    @State var pendingMention: PendingMention?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
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
            textSize: input.value.text.count, isPostWithMedia: mediaItems.value.count > 0)
        textView.textColor = UIColor.label.withAlphaComponent(0.9)
        textView.text = input.value.text
        textView.textContainerInset.bottom = PostComposerLayoutConstants.postTextVerticalPadding
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context)  {
        // Don't set text or selection on uiView (it clears markedTextRange, which breaks IME)
        let fontToUse = PostComposerLayoutConstants.getFontSize(
            textSize: input.value.text.count, isPostWithMedia: mediaItems.value.count > 0)
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

        TextView.recomputeHeight(textView: uiView, resultHeight: $textHeight.value)
    }

    private static func recomputeHeight(textView: UIView, resultHeight: Binding<CGFloat>) {
        let newSize = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))
        if resultHeight.wrappedValue != newSize.height {
            DispatchQueue.main.async {
                resultHeight.wrappedValue = newSize.height
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

        private lazy var mentionableUsers: [MentionableUser] = {
            return Mentions.mentionableUsersForNewPost()
        }()

        private func updateMentionPickerContent() {
            guard !parent.areMentionsDisabled.value else { return }

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
            return mentionableUsers.filter {
                Mentions.isPotentialMatch(fullName: $0.fullName, input: trimmedInput)
            }
        }


        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !parent.areMentionsDisabled.value else { return true }

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
            TextView.recomputeHeight(textView: textView, resultHeight: parent.$textHeight.value)
            updateMentionPickerContent()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.input.value.selectedRange = textView.selectedRange
            updateMentionPickerContent()
        }
    }
}

fileprivate struct MediaPreviewSlider: UIViewRepresentable {
    @ObservedObject var mediaItems: ObservableMediaItems
    @ObservedObject var shouldAutoPlay: GenericObservable<Bool>
    var currentPosition: GenericObservable<Int>

    var feedMediaItems: [FeedMedia] {
        mediaItems.value.map { FeedMedia($0, feedPostId: "") }
    }

    func makeUIView(context: Context) -> MediaCarouselView {
        let feedMedia = context.coordinator.parent.feedMediaItems
        let carouselView = MediaCarouselView(media: feedMedia, configuration: MediaCarouselViewConfiguration.composer)
        carouselView.delegate = context.coordinator
        carouselView.shouldAutoPlay = context.coordinator.parent.shouldAutoPlay.value
        return carouselView
    }

    func updateUIView(_ uiView: MediaCarouselView, context: Context) {
        uiView.shouldAutoPlay = context.coordinator.parent.shouldAutoPlay.value
        uiView.refreshData(
            media: context.coordinator.parent.feedMediaItems,
            index: context.coordinator.parent.currentPosition.value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: MediaCarouselViewDelegate {
        var parent: MediaPreviewSlider

        init(_ view: MediaPreviewSlider) {
            parent = view
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

    @State var mediaItems: [PendingMedia]
    let complete: ([PendingMedia], Bool) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = MediaPickerViewController(selected: mediaItems) { controller, media, cancel in
            self.complete(media, cancel)
        }

        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}
