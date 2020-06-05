
import CocoaLumberjack
import SwiftUI
import UIKit

struct PostComposerView: View {

    private let imageServer = ImageServer()
    private let mediaItemsToPost: [PendingMedia]
    private let didFinish: () -> Void

    @State var isJustText: Bool = false
    @State var msgToSend = ""
    @State var isShareClicked: Bool = false
    @State var isReadyToPost: Bool = false
    @State var numberOfFailedUploads: Int = 0

    init(mediaItemsToPost: [PendingMedia], didFinish: @escaping () -> Void) {
        self.mediaItemsToPost = mediaItemsToPost
        self.didFinish = didFinish
    }
    
    var body: some View {
        return NavigationView {
            VStack {
                Spacer()
                    .frame(height: 16)

                if self.mediaItemsToPost.count > 0 {
                    MediaPreviewSlider(self.mediaItemsToPost.map { FeedMedia($0, feedPostId: "") })
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
                    TextView(text: self.$msgToSend)
                        .cornerRadius(10)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: isJustText ? 100 : 70)
                }
                .padding(.horizontal)

                Spacer()
                    .frame(height: 16)

                Button(action: {
                    if self.isShareClicked {
                        return
                    }

                    if self.isJustText && self.msgToSend == "" {
                        return
                    }

                    if self.numberOfFailedUploads > 0 {
                        return
                    }

                    if self.isReadyToPost {
                        self.isShareClicked = true
                        MainAppContext.shared.feedData.post(text: self.msgToSend.trimmingCharacters(in: .whitespacesAndNewlines), media: self.mediaItemsToPost)
                        self.didFinish()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.msgToSend = ""
                            self.isShareClicked = false
                        }
                    }
                }) {
                    Text("SHARE")
                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .background((self.isJustText && self.msgToSend != "") || (!self.isJustText && self.isReadyToPost && self.numberOfFailedUploads == 0) ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                }

                Spacer()
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(leading:
                HStack {
                    Button(action: {
                        self.imageServer.cancel()
                        self.didFinish()
                    }) {
                        Text("Cancel")
                    }
            })
            .background(Color(UIColor.feedBackgroundColor))
        }
        .onAppear {
            if self.mediaItemsToPost.isEmpty {
                self.isJustText = true
                self.isReadyToPost = true
            } else {
                self.imageServer.upload(self.mediaItemsToPost, isReady: self.$isReadyToPost, numberOfFailedUploads: self.$numberOfFailedUploads)
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
        myTextView.backgroundColor = UIColor.textFieldBackgroundColor
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
        let carouselView = MediaCarouselView(media: context.coordinator.parent.media)
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
