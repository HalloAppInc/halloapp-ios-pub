
import Combine
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

struct urlContainer {
    var getUrl: String = ""
    var putUrl: String = ""
}

struct PostComposerView: View {
    private let userData = AppContext.shared.userData

    var mediaItemsToPost: [FeedMedia] = []

    var didFinish: () -> Void

    @State var isJustText: Bool = false
    
    @State var msgToSend = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State var fetchedUrls: [urlContainer] = []
    
    @State var isShareClicked: Bool = false
    
    @State var isReadyToPost: Bool = false
    
    @State private var play: Bool = true

    var body: some View {

        DispatchQueue.main.async {

            self.cancellableSet.forEach {
                $0.cancel()
            }
            self.cancellableSet.removeAll()

            print("cancellable count: \(self.cancellableSet.count)")

            if (self.mediaItemsToPost.count == 0) {
                self.isJustText = true
                self.isReadyToPost = true
            }

            /* important: this needs to be cancelled in onDisappear as the sinks remains even after */
            self.cancellableSet.insert(

                AppContext.shared.xmppController.didGetUploadUrl.sink(receiveValue: { iq in

                    var urlCon: urlContainer = urlContainer()

                    (urlCon.getUrl, urlCon.putUrl) = Utils().parseMediaUrl(iq)

                    print("got url: \(urlCon.getUrl)")
                    self.fetchedUrls.append(urlCon)

                    // preemptive uploads
                    if (self.fetchedUrls.count != 0 && self.mediaItemsToPost.count != 0) {
                        if (self.fetchedUrls.count == self.mediaItemsToPost.count) {

                            var uploadArr: [FeedMedia] = []
                            var index = 0

                            for item in self.mediaItemsToPost {

                                item.url = self.fetchedUrls[index].getUrl

                                let feedMedia = FeedMedia()
                                feedMedia.type = item.type
                                feedMedia.url = self.fetchedUrls[index].putUrl

                                if feedMedia.type == "image" {
                                    
                                    self.userData.log("Post Image: original res - \(item.width) x \(item.height)")

                                    if item.width > 1600 || item.height > 1600 {
                                        item.image = item.image.getNewSize(res: 1600) ?? UIImage()
                                        item.width = Int(item.image.size.width)
                                        item.height = Int(item.image.size.height)
                                        
                                        self.userData.log("Post Image: resized res - \(item.image.size.width) x \(item.image.size.height)")
                                    }

                                    feedMedia.image = item.image

                                    /* turn on/off encryption of media */
                                    if let imgData = feedMedia.image.jpegData(compressionQuality: CGFloat(self.userData.compressionQuality)) {
                                        self.userData.log("Post Image: (\(self.userData.compressionQuality)) compressed size - \(imgData.count)")
                                        
                                        (feedMedia.encryptedData, feedMedia.key, feedMedia.sha256hash) = HAC().encryptData(data: imgData, type: "image")

                                        item.key = feedMedia.key
                                        item.sha256hash = feedMedia.sha256hash
                                    }

                                }

                                uploadArr.append(feedMedia)

                                index += 1
                            }


                            ImageServer().uploadMultiple(media: uploadArr)

                            self.isReadyToPost = true

                        }
                    }

                })

            )

        }
        
        
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

//                if item.media.count > 0 {
//
//                    MediaSlider(item, item.mediaHeight)
//                }

            if (self.mediaItemsToPost.count > 1) {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        /* do not use .self for id as that is not always unique and can crash the app */
                        ForEach(self.mediaItemsToPost, id: \.id) { item in
                            Image(uiImage: item.image)
                                .resizable()
                                .aspectRatio(item.image.size, contentMode: .fit)
                                .frame(maxHeight: 200)
                                .background(Color.gray)
                                .cornerRadius(10)
                                .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                        }
                    }
                }
                .modifier(DismissingKeyboard())
            } else if self.mediaItemsToPost.count == 1 {
                if self.mediaItemsToPost[0].type == "image" {
                    Image(uiImage: self.mediaItemsToPost[0].image)
                        .resizable()
                        .aspectRatio(self.mediaItemsToPost[0].image.size, contentMode: .fit)
                        .frame(maxHeight: 200)
                        .background(Color.gray)
                        .cornerRadius(10)
                        .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                } else {
                    WAVPlayer(videoURL: self.mediaItemsToPost[0].tempUrl!)
                        .zIndex(20.0)
                        .frame(maxHeight: 200)
                        .background(Color.gray)
                        .cornerRadius(10)
                        .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                        .cornerRadius(10)
                }
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

                if (self.isReadyToPost) {
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

        .onDisappear {
            self.cancellableSet.forEach {
                $0.cancel()
            }
            self.cancellableSet.removeAll()
        }
        .background(Color(UIColor.systemBackground))
    }
}
