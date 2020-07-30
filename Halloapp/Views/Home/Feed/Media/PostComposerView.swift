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

fileprivate class ObservableString: ObservableObject {
    @Published var value = ""

    func set(_ newValue: String) {
        value = newValue
    }
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
    @Published var numberOfFailedUploads: Int = 0
}

class PostComposerViewController: UIViewController {
    fileprivate let imageServer = ImageServer()

    private let showCancelButton: Bool
    private let mediaItems = ObservableMediaItems()
    private var textToPost = ObservableString()
    private var postComposerView: PostComposerView?
    private var shareButton: UIBarButtonItem!
    private let didFinish: (() -> Void)
    private let willDismissWithText: ((String) -> Void)?

    init(
        mediaToPost media: [PendingMedia],
        initialText: String,
        showCancelButton: Bool,
        willDismissWithText: ((String) -> Void)? = nil,
        didFinish: @escaping () -> Void)
    {
        self.mediaItems.value = media
        self.showCancelButton = showCancelButton
        self.willDismissWithText = willDismissWithText
        self.didFinish = didFinish
        self.textToPost.set(initialText)
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
            textToPost: textToPost,
            crop: { index in
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
        willDismissWithText?(textToPost.value)
    }

    private func finish() {
        didFinish()
    }

    @objc private func cancelAction() {
        imageServer.cancel()
        finish()
    }

    @objc private func shareAction() {
        MainAppContext.shared.feedData.post(text: textToPost.value.trimmingCharacters(in: .whitespacesAndNewlines), media: mediaItems.value)
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
    @ObservedObject private var textToPost: ObservableString
    private let crop: (_ index: ObservableInt) -> Void
    private let goBack: () -> Void
    private let setShareVisibility: (_ visibility: Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var mediaState = ObservableMediaState()
    @ObservedObject private var currentPosition = ObservableInt()
    @ObservedObject private var postTextHeight = ObservableFloat()
    @State private var keyboardHeight: CGFloat = 0

    private var keyboardHeightPublisher: AnyPublisher<CGFloat, Never> {
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
    }

    private var shareVisibilityPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest4(
            mediaItems.$value,
            mediaState.$isReady,
            mediaState.$numberOfFailedUploads,
            textToPost.$value
        )
        .map { (mediaItems, mediaIsReady, numberOfFailedUploads, textValue) -> Bool in
            return (mediaItems.count > 0 && mediaIsReady && numberOfFailedUploads == 0) ||
                (mediaItems.count == 0 && !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private var mediaCount: Int {
        mediaItems.value.count
    }

    private var feedMediaItems: [FeedMedia] {
        mediaItems.value.map { FeedMedia($0, feedPostId: "") }
    }

    private var controlYOffset: CGFloat {
        (mediaCount > 1 ? MediaCarouselView.pageControlAreaHeight : 0) + PostComposerLayoutConstants.controlSpacing
    }

    init(imageServer: ImageServer, mediaItems: ObservableMediaItems, textToPost: ObservableString, crop: @escaping (_ index: ObservableInt) -> Void, goBack: @escaping () -> Void, setShareVisibility: @escaping (_ visibility: Bool) -> Void) {
        self.imageServer = imageServer
        self.mediaItems = mediaItems
        self.textToPost = textToPost
        self.crop = crop
        self.goBack = goBack
        self.setShareVisibility = setShareVisibility
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
            Button(action: cropMedia) {
                ControlIconView(imageLabel: "ComposerCropMedia")
            }.padding(.leading, PostComposerLayoutConstants.controlXSpacing)
        }
        .padding(.horizontal, PostComposerLayoutConstants.controlSpacing)
        .offset(y: -controlYOffset)
    }

    var postTextView: some View {
        ZStack (alignment: .topLeading) {
            if (textToPost.value.isEmpty) {
                Text(mediaCount > 0 ? "Write a description" : "Write a post")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .frame(height: max(postTextHeight.value, mediaCount > 0 ? 10 : 260), alignment: .topLeading)
            }
            TextView(text: textToPost, textHeight: postTextHeight)
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
                            .onTapGesture {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
                            }

                            if self.mediaState.numberOfFailedUploads > 1 {
                                Text("Failed to upload \(self.mediaState.numberOfFailedUploads) media items. Please try again.")
                                    .foregroundColor(.red)
                            } else if self.mediaState.numberOfFailedUploads > 0 {
                                Text("Failed to upload media. Please try again.")
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
                            self.imageServer.upload(self.mediaItems.value, isReady: self.$mediaState.isReady, numberOfFailedUploads: self.$mediaState.numberOfFailedUploads)
                        } else {
                            self.mediaState.isReady = true
                        }
                    }
                    .onReceive(self.shareVisibilityPublisher) { self.setShareVisibility($0) }
                    .onReceive(self.keyboardHeightPublisher) { self.keyboardHeight = $0 }
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height - self.keyboardHeight)
            }
            .background(Color.feedBackground)
            .padding(.bottom, self.keyboardHeight)
            .edgesIgnoringSafeArea(.bottom)
        }
    }

    private func addMedia() {
        goBack()
    }

    private func cropMedia() {
        crop(currentPosition)
    }

    private func deleteMedia() {
        mediaItems.remove(index: currentPosition.value)
        if (mediaItems.value.count == 0) {
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

fileprivate struct TextView: UIViewRepresentable {
    @ObservedObject var text: ObservableString
    @ObservedObject var textHeight: ObservableFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let myTextView = UITextView()
        myTextView.delegate = context.coordinator
        myTextView.font = .preferredFont(forTextStyle: .body)
        myTextView.isScrollEnabled = false
        myTextView.isEditable = true
        myTextView.isUserInteractionEnabled = true
        myTextView.backgroundColor = .textFieldBackground
        myTextView.backgroundColor = UIColor.clear
        myTextView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return myTextView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text.value
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

    class Coordinator : NSObject, UITextViewDelegate {
        var parent: TextView

        init(_ uiTextView: TextView) {
            self.parent = uiTextView
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            self.parent.text.set(textView.text ?? "")
            TextView.recomputeHeight(textView: textView, resultHeight: self.parent.$textHeight.value)
        }
    }
}

fileprivate struct MediaPreviewSlider: UIViewRepresentable {
    @ObservedObject var mediaItems: ObservableMediaItems
    @ObservedObject var currentPosition: ObservableInt

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
