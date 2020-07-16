
import CocoaLumberjack
import SwiftUI
import UIKit

class PostComposerViewController: UIViewController {

    private let showCancelButton: Bool
    private let media: [PendingMedia]
    private var postComposerView: PostComposerView!
    private let didFinish: (() -> Void)

    init(mediaToPost media: [PendingMedia], showCancelButton: Bool, didFinish: @escaping () -> Void ) {
        self.media = media
        self.showCancelButton = showCancelButton
        self.didFinish = didFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(mediaToPost:standalonePicker:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if showCancelButton {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        }

        postComposerView = PostComposerView(mediaItemsToPost: media) {
            self.finish()
        }
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

    private func finish() {
        didFinish()
    }

    @objc private func cancelAction() {
        postComposerView.imageServer.cancel()
        finish()
    }

}

struct PostComposerView: View {

    fileprivate let imageServer = ImageServer()
    private let mediaItemsToPost: [PendingMedia]
    private let didFinish: () -> Void

    @State var isTextOnlyPost: Bool = false
    @State var textToPost = ""
    @State var isMediaReady: Bool = false
    @State var numberOfFailedUploads: Int = 0

    init(mediaItemsToPost: [PendingMedia], didFinish: @escaping () -> Void) {
        self.mediaItemsToPost = mediaItemsToPost
        self.didFinish = didFinish
    }
    
    var body: some View {
        return VStack {
            Spacer()
                .frame(height: 16)

            if self.mediaItemsToPost.count > 0 {
                MediaPreviewSlider(self.mediaItemsToPost.map { FeedMedia($0, feedPostId: "") })
                    .padding(.horizontal)
                    .frame(height: 200, alignment: .center)

                if self.numberOfFailedUploads > 1 {
                    Text("Failed to upload \(self.numberOfFailedUploads) media items. Please try again.")
                        .foregroundColor(.red)
                } else if self.numberOfFailedUploads > 0 {
                    Text("Failed to upload media. Please try again.")
                        .foregroundColor(.red)
                }

                Spacer()
                    .frame(height: 16)
            }

            HStack {
                TextView(text: self.$textToPost)
                    .cornerRadius(10)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: isTextOnlyPost ? 100 : 70)
            }
            .padding(.horizontal)

            Spacer()
                .frame(height: 16)

            Button(action: {
                MainAppContext.shared.feedData.post(text: self.textToPost.trimmingCharacters(in: .whitespacesAndNewlines), media: self.mediaItemsToPost)
                self.didFinish()
            }) {
                Text("SHARE")
                    .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .background((self.isTextOnlyPost && self.textToPost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !self.isMediaReady || self.numberOfFailedUploads != 0 ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
            }
            .disabled((self.isTextOnlyPost && self.textToPost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !self.isMediaReady || self.numberOfFailedUploads != 0)

            Spacer()
        }
        .background(Color.feedBackground)
        .onAppear {
            if self.mediaItemsToPost.isEmpty {
                self.isTextOnlyPost = true
                self.isMediaReady = true
            } else {
                self.imageServer.upload(self.mediaItemsToPost, isReady: self.$isMediaReady, numberOfFailedUploads: self.$numberOfFailedUploads)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

fileprivate struct TextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let myTextView = UITextView()
        myTextView.delegate = context.coordinator
        myTextView.font = .preferredFont(forTextStyle: .body)
        myTextView.isScrollEnabled = true
        myTextView.isEditable = true
        myTextView.isUserInteractionEnabled = true
        myTextView.backgroundColor = .textFieldBackground
        myTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return myTextView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
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
            self.parent.text = textView.text
        }
    }
}

fileprivate struct MediaPreviewSlider: UIViewRepresentable {

    var media: [FeedMedia]

    init(_ media: [FeedMedia]) {
        self.media = media
    }

    func makeUIView(context: Context) -> MediaCarouselView {
        var configuration = MediaCarouselViewConfiguration.default
        configuration.isZoomEnabled = false
        configuration.alwaysScaleToFitContent = true
        let carouselView = MediaCarouselView(media: context.coordinator.parent.media, configuration: configuration)
        return carouselView
    }

    func updateUIView(_ uiView: MediaCarouselView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: MediaPreviewSlider

        init(_ view: MediaPreviewSlider) {
            self.parent = view
        }
    }
}
