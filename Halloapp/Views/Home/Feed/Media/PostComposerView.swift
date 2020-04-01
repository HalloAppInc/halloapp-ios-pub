import SwiftUI
import UIKit

struct DismissingKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                let keyWindow = UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .map({$0 as? UIWindowScene})
                    .compactMap({$0})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first
                keyWindow?.endEditing(true)
        }
    }
}


struct PostComposerView: View {
    private let userData = AppContext.shared.userData
    private let imageServer = ImageServer()

    var mediaItemsToPost: [FeedMedia] = []

    var didFinish: () -> Void

    @State var isJustText: Bool = false
    
    @State var msgToSend = ""

    @State var isShareClicked: Bool = false
    
    @State var isReadyToPost: Bool = false
    
    @State private var play: Bool = true

    @State private var item: FeedDataItem
    
    init(mediaItemsToPost: [FeedMedia], didFinish: @escaping () -> Void) {
        
        self.mediaItemsToPost = mediaItemsToPost
        self.didFinish = didFinish
        
        self._item = State(initialValue: FeedDataItem())
        self.item.media = self.mediaItemsToPost
    }
    
    var body: some View {
        return VStack {

            Divider()
                .frame(height: UIScreen.main.bounds.height < 812 ? 10 : 40)
                .hidden()
                .modifier(DismissingKeyboard())

            HStack() {

                Button(action: {
                    self.didFinish()
                }) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.gray)
                        .padding(EdgeInsets(top: 15, leading: 20, bottom: 0, trailing: 15))
                }
                Spacer()
            }
            .modifier(DismissingKeyboard())

            Divider()
                .frame(height: isJustText ? 15 : 0)
                .hidden()

            if self.mediaItemsToPost.count > 0 {
                MediaSlider(self.item)
                    .frame(height: 200, alignment: .center)
            }
        
            HStack {
                TextView(text: self.$msgToSend)
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: isJustText ? 100 : 70)
                    .cornerRadius(10)
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .modifier(DismissingKeyboard())

            Divider()
                .frame(height: isJustText ? 20 : 5)
                .hidden()
                .modifier(DismissingKeyboard())

            Button(action: {
                if self.isShareClicked {
                    return
                }

                if self.isJustText && self.msgToSend == "" {
                    return
                }

                if self.isReadyToPost {
                    self.isShareClicked = true
                    AppContext.shared.feedData.postItem(self.userData.phone, self.msgToSend, self.mediaItemsToPost)
                    self.didFinish()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.msgToSend = ""
                        self.isShareClicked = false
                    }
                }
            }) {
                Text("SHARE")
                    .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .background((self.isJustText && self.msgToSend != "") || (!self.isJustText && self.isReadyToPost) ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
            }

            Spacer()
                .modifier(DismissingKeyboard())
        }
        .onAppear {
            if self.mediaItemsToPost.isEmpty {
                self.isJustText = true
                self.isReadyToPost = true
            } else {
                self.imageServer.beginUploading(items: self.mediaItemsToPost, isReady: self.$isReadyToPost)
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}
