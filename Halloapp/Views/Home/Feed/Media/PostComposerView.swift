import Core
import CocoaLumberjack
import Combine
import SwiftUI
import UIKit

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

class PostComposerViewController: UIViewController {
    fileprivate let imageServer = ImageServer()

    private let showCancelButton: Bool
    private let mediaItems = ObservableMediaItems()
    private var inputToPost: GenericObservable<MentionInput>
    private var shouldAutoPlay = GenericObservable(false)
    private var postComposerView: PostComposerView?
    private var shareButton: UIBarButtonItem!
    private let didFinish: ((Bool, [PendingMedia]) -> Void)
    private let willDismissWithInput: ((MentionInput) -> Void)?

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        showCancelButton: Bool,
        willDismissWithInput: ((MentionInput) -> Void)? = nil,
        didFinish: @escaping (Bool, [PendingMedia]) -> Void)
    {
        self.mediaItems.value = media
        self.showCancelButton = showCancelButton
        self.willDismissWithInput = willDismissWithInput
        self.didFinish = didFinish
        self.inputToPost = GenericObservable(initialInput)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaToPost:standalonePicker:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "New Post"
        if showCancelButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(backAction))
        } else {
            let icon = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: icon, style: .plain, target: self, action: #selector(backAction))
        }
        shareButton = UIBarButtonItem(title: "Share", style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue

        postComposerView = PostComposerView(
            imageServer: imageServer,
            mediaItems: mediaItems,
            inputToPost: inputToPost,
            shouldAutoPlay: shouldAutoPlay,
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
            setShareVisibility: { [weak self] visibility in self?.setShareVisibility(visibility)}
        )

        let postComposerViewController = UIHostingController(rootView: postComposerView)
        addChild(postComposerViewController)
        view.addSubview(postComposerViewController.view)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.backgroundColor = .feedBackground
        postComposerViewController.view.constrain(to: view)
        postComposerViewController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.shouldAutoPlay.value = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.shouldAutoPlay.value = false
        willDismissWithInput?(inputToPost.value)
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil {
            imageServer.cancel()
        }
    }

    @objc private func shareAction() {
        let mentionText = MentionText(expandedText: inputToPost.value.text, mentionRanges: inputToPost.value.mentions).trimmed()
        MainAppContext.shared.feedData.post(text: mentionText, media: mediaItems.value)
        didFinish(false, [])
    }

    @objc private func backAction() {
        if showCancelButton {
            imageServer.cancel()
        }
        
        didFinish(true, self.mediaItems.value)
    }

    private func setShareVisibility(_ visibility: Bool) {
        if (visibility && navigationItem.rightBarButtonItem == nil) {
            navigationItem.rightBarButtonItem = shareButton
        } else if (!visibility && navigationItem.rightBarButtonItem != nil) {
            navigationItem.rightBarButtonItem = nil
        }
    }
}

fileprivate struct PostComposerLayoutConstants {
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let controlSpacing: CGFloat = 8
    static let controlRadius: CGFloat = 15
    static let controlXSpacing: CGFloat = 17
    static let controlSize: CGFloat = 30
    static let backgroundRadius: CGFloat = 20

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
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    @ObservedObject private var shouldAutoPlay: GenericObservable<Bool>
    private let crop: (_ index: GenericObservable<Int>) -> Void
    private let goBack: () -> Void
    private let setShareVisibility: (_ visibility: Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = GenericObservable(0)
    @ObservedObject private var postTextHeight = GenericObservable<CGFloat>(0)
    @State private var keyboardHeight: CGFloat = 0

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
        crop: @escaping (_ index: GenericObservable<Int>) -> Void,
        goBack: @escaping () -> Void,
        setShareVisibility: @escaping (_ visibility: Bool) -> Void)
    {
        self.imageServer = imageServer
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
        self.shouldAutoPlay = shouldAutoPlay
        self.crop = crop
        self.goBack = goBack
        self.setShareVisibility = setShareVisibility

        self.shareVisibilityPublisher =
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

        self.pageChangedPublisher =
            self.currentPosition.$value.removeDuplicates().map { _ in return true }.eraseToAnyPublisher()
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

    var controls: some View {
        HStack {
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
        .padding(.horizontal, PostComposerLayoutConstants.controlSpacing)
        .offset(y: -controlYOffset)
    }

    var postTextView: some View {
        ZStack (alignment: .topLeading) {
            if (inputToPost.value.text.isEmpty) {
                Text(mediaCount > 0 ? "Write a description" : "Write a post")
                    .font(Font(PostComposerLayoutConstants.getFontSize(
                        textSize: inputToPost.value.text.count, isPostWithMedia: mediaCount > 0)))
                    .foregroundColor(Color.primary.opacity(0.5))
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .frame(height: max(postTextHeight.value, mediaCount > 0 ? 10 : 260), alignment: .topLeading)
            }
            TextView(mediaItems: mediaItems, input: inputToPost, textHeight: postTextHeight)
                .frame(height: max(postTextHeight.value, mediaCount > 0 ? 10 : 260))
        }
        .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding + PostComposerLayoutConstants.controlSpacing)
        .padding(.top, PostComposerLayoutConstants.verticalPadding + PostComposerLayoutConstants.controlSpacing)
    }

    var body: some View {
        return GeometryReader { geometry in
            ScrollView {
                VStack {
                    VStack (alignment: .center) {
                        if self.mediaCount > 0 {
                            ZStack(alignment: .bottom) {
                                ZStack(alignment: .top) {
                                    MediaPreviewSlider(
                                        mediaItems: self.mediaItems,
                                        shouldAutoPlay: self.shouldAutoPlay,
                                        currentPosition: self.currentPosition)
                                    .frame(height: self.getMediaSliderHeight(geometry.size.width), alignment: .center)

                                    self.pageIndex
                                }

                                self.controls
                            }
                            .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding)
                            .padding(.vertical, PostComposerLayoutConstants.verticalPadding)

                            if self.mediaState.numberOfFailedItems > 1 {
                                Text("Failed to prepare \(self.mediaState.numberOfFailedItems) media items. Please try again or select a different photo / video.")
                                    .foregroundColor(.red)
                            } else if self.mediaState.numberOfFailedItems > 0 {
                                Text("Failed to prepare media. Please try again or select a different photo / video.")
                                    .foregroundColor(.red)
                            }
                        }

                        self.postTextView
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
                }
                .frame(minHeight: geometry.size.height - self.keyboardHeight)
            }
            .background(Color.feedBackground)
            .padding(.bottom, self.keyboardHeight)
            .edgesIgnoringSafeArea(.bottom)
        }
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
            .frame(width: PostComposerLayoutConstants.controlSize, height: PostComposerLayoutConstants.controlSize)
            .background(
                RoundedRectangle(cornerRadius: PostComposerLayoutConstants.controlRadius)
                    .fill(Color(.systemGray6))
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
    @State var pendingMention: PendingMention?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.inputAccessoryView = context.coordinator.mentionPicker
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .textFieldBackground
        textView.backgroundColor = UIColor.clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = PostComposerLayoutConstants.getFontSize(
            textSize: input.value.text.count, isPostWithMedia: mediaItems.value.count > 0)
        textView.text = input.value.text
        textView.textContainerInset.bottom = PostComposerLayoutConstants.verticalPadding + PostComposerLayoutConstants.controlSpacing
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
        let carouselView = MediaCarouselView(media: feedMedia, configuration: MediaCarouselViewConfiguration.default)
        carouselView.indexChangeDelegate = context.coordinator
        carouselView.shouldAutoPlay = context.coordinator.parent.shouldAutoPlay.value

        let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        carouselView.addGestureRecognizer(gestureRecognizer)

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

    class Coordinator: MediaIndexChangeListener {
        var parent: MediaPreviewSlider

        init(_ view: MediaPreviewSlider) {
            parent = view
        }

        func indexChanged(position: Int) {
            parent.currentPosition.value = position
        }

        @objc func tapped(gesture: UITapGestureRecognizer) {
            PostComposerView.stopTextEdit()
        }
    }
}
