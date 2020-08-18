import Core
import CocoaLumberjack
import Combine
import SwiftUI
import UIKit

fileprivate class ObservableInt: ObservableObject {
    @Published var value = 0
}

fileprivate class ObservableFloat: ObservableObject {
    @Published var value: CGFloat = 0
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

class PostComposerViewController: UIViewController {
    fileprivate let imageServer = ImageServer()

    private let showCancelButton: Bool
    private let mediaItems = ObservableMediaItems()
    private var inputToPost: GenericObservable<MentionInput>
    private var postComposerView: PostComposerView?
    private var shareButton: UIBarButtonItem!
    private let didFinish: (() -> Void)
    private let willDismissWithInput: ((MentionInput) -> Void)?

    init(
        mediaToPost media: [PendingMedia],
        initialInput: MentionInput,
        showCancelButton: Bool,
        willDismissWithInput: ((MentionInput) -> Void)? = nil,
        didFinish: @escaping () -> Void)
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

        self.navigationItem.title = "New Post"
        if showCancelButton {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        }
        shareButton = UIBarButtonItem(title: "Share", style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue

        postComposerView = PostComposerView(
            imageServer: self.imageServer,
            mediaItems: mediaItems,
            inputToPost: inputToPost,
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
        self.addChild(postComposerViewController)
        self.view.addSubview(postComposerViewController.view)
        postComposerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        postComposerViewController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        postComposerViewController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        postComposerViewController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        postComposerViewController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        postComposerViewController.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        willDismissWithInput?(inputToPost.value)
    }

    private func finish() {
        didFinish()
    }

    @objc private func cancelAction() {
        imageServer.cancel()
        finish()
    }

    @objc private func shareAction() {
        let mentionText = MentionText(expandedText: inputToPost.value.text, mentionRanges: inputToPost.value.mentions).trimmed()
        MainAppContext.shared.feedData.post(text: mentionText, media: mediaItems.value)
        finish()
    }

    private func backAction() {
        imageServer.cancel()
        self.navigationController?.popViewController(animated: true)
    }

    private func setShareVisibility(_ visibility: Bool) {
        if (visibility && self.navigationItem.rightBarButtonItem == nil) {
            self.navigationItem.rightBarButtonItem = shareButton
        } else if (!visibility && self.navigationItem.rightBarButtonItem != nil) {
            self.navigationItem.rightBarButtonItem = nil
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
}

fileprivate struct PostComposerView: View {
    private let imageServer: ImageServer
    @ObservedObject private var mediaItems: ObservableMediaItems
    @ObservedObject private var inputToPost: GenericObservable<MentionInput>
    private let crop: (_ index: ObservableInt) -> Void
    private let goBack: () -> Void
    private let setShareVisibility: (_ visibility: Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = ObservableInt()
    @ObservedObject private var postTextHeight = ObservableFloat()
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

    init(
        imageServer: ImageServer,
        mediaItems: ObservableMediaItems,
        inputToPost: GenericObservable<MentionInput>,
        crop: @escaping (_ index: ObservableInt) -> Void,
        goBack: @escaping () -> Void,
        setShareVisibility: @escaping (_ visibility: Bool) -> Void)
    {
        self.imageServer = imageServer
        self.mediaItems = mediaItems
        self.inputToPost = inputToPost
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

    var pageIndexView: some View {
        Text("\(currentPosition.value + 1) / \(mediaCount)")
            .frame(width: 2 * PostComposerLayoutConstants.controlSize, height: PostComposerLayoutConstants.controlSize)
            .background(
                RoundedRectangle(cornerRadius: PostComposerLayoutConstants.controlRadius)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.trailing, PostComposerLayoutConstants.controlXSpacing)
    }

    var controls: some View {
        HStack {
            if (mediaCount > 1) {
                pageIndexView
            }
            Button(action: addMedia) {
                ControlIconView(imageLabel: "ComposerAddMedia")
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
        .padding(.horizontal, PostComposerLayoutConstants.controlSpacing)
        .offset(y: -controlYOffset)
    }

    var postTextView: some View {
        ZStack (alignment: .topLeading) {
            if (inputToPost.value.text.isEmpty) {
                Text(mediaCount > 0 ? "Write a description" : "Write a post")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .frame(height: max(postTextHeight.value, mediaCount > 0 ? 10 : 260), alignment: .topLeading)
            }
            TextView(input: inputToPost, textHeight: postTextHeight)
                .frame(height: max(postTextHeight.value, mediaCount > 0 ? 10 : 260))
        }
        .padding(.horizontal, PostComposerLayoutConstants.horizontalPadding + PostComposerLayoutConstants.controlSpacing)
        .padding(.vertical, PostComposerLayoutConstants.verticalPadding + PostComposerLayoutConstants.controlSpacing)
    }

    var body: some View {
        return GeometryReader { geometry in
            ScrollView {
                VStack {
                    VStack (alignment: .center) {
                        if self.mediaCount > 0 {
                            ZStack(alignment: .bottom) {
                                MediaPreviewSlider(mediaItems: self.mediaItems, currentPosition: self.currentPosition)
                                    .frame(height: self.getMediaSliderHeight(geometry.size.width), alignment: .center)

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
                    .onReceive(self.pageChangedPublisher) { _ in self.stopTextEdit() }
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height - self.keyboardHeight)
            }
            .background(Color.feedBackground)
            .padding(.bottom, self.keyboardHeight)
            .edgesIgnoringSafeArea(.bottom)
        }
    }

    private func stopTextEdit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }

    private func addMedia() {
        goBack()
    }

    private func cropMedia() {
        self.mediaState.isReady = false
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

fileprivate struct TextView: UIViewRepresentable {
    @ObservedObject var input: GenericObservable<MentionInput>
    @ObservedObject var textHeight: ObservableFloat
    @State var pendingMention: PendingMention?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let myTextView = UITextView()
        myTextView.delegate = context.coordinator
        myTextView.font = .preferredFont(forTextStyle: .body)
        myTextView.inputAccessoryView = context.coordinator.mentionPicker
        myTextView.isScrollEnabled = false
        myTextView.isEditable = true
        myTextView.isUserInteractionEnabled = true
        myTextView.backgroundColor = .textFieldBackground
        myTextView.backgroundColor = UIColor.clear
        myTextView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        myTextView.text = input.value.text
        return myTextView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
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
            self.parent = uiTextView
        }

        // MARK: Mentions

        lazy var mentionPicker: MentionPickerView = {
            let picker = MentionPickerView()
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
            let mentionableUsers = fetchMentionPickerContent(
                for: parent.input.value.text,
                selectedRange: parent.input.value.selectedRange)

            mentionPicker.items = mentionableUsers
            mentionPicker.isHidden = mentionableUsers.isEmpty
        }

        private func acceptMentionPickerItem(_ item: MentionableUser) {
            guard let currentWordRange = parent.input.value.text.rangeOfWord(at: parent.input.value.selectedRange.location) else {
                return
            }
            parent.pendingMention = PendingMention(
                name: item.fullName,
                userID: item.userID,
                range: currentWordRange)
            updateMentionPickerContent()
        }

        private func fetchMentionPickerContent(for input: String?, selectedRange: NSRange) -> [MentionableUser] {
            guard let input = input,
                let currentWordRange = input.rangeOfWord(at: selectedRange.location),
                !parent.input.value.mentions.keys.contains(where: { currentWordRange.overlaps($0) }),
                selectedRange.length == 0 else
            {
                return []
            }

            let currentWord = (input as NSString).substring(with: currentWordRange)
            guard currentWord.hasPrefix("@") else {
                return []
            }

            let trimmedInput = String(currentWord.dropFirst())
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
    var currentPosition: ObservableInt

    var feedMediaItems: [FeedMedia] {
        mediaItems.value.map { FeedMedia($0, feedPostId: "") }
    }

    init(mediaItems: ObservableMediaItems, currentPosition: ObservableInt) {
        self.mediaItems = mediaItems
        self.currentPosition = currentPosition
    }

    func makeUIView(context: Context) -> MediaCarouselView {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.isZoomEnabled = false
        let feedMedia = context.coordinator.parent.feedMediaItems
        let carouselView = MediaCarouselView(media: feedMedia, configuration: configuration)
        carouselView.indexChangeDelegate = context.coordinator
        return carouselView
    }

    func updateUIView(_ uiView: MediaCarouselView, context: Context) {
        uiView.refreshData(media: context.coordinator.parent.feedMediaItems, index: context.coordinator.parent.currentPosition.value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: MediaIndexChangeListener {
        var parent: MediaPreviewSlider

        init(_ view: MediaPreviewSlider) {
            self.parent = view
        }

        func indexChanged(position: Int) {
            parent.currentPosition.value = position
        }
    }
}
