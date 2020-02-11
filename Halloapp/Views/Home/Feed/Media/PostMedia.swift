
import SwiftUI
import Combine

struct urlContainer {
    var getUrl: String = ""
    var putUrl: String = ""
}

struct PostMedia: View {
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @ObservedObject var feedData: FeedData
    
    var pickedImages: [UIImage] = []
    
    var isJustText: Bool = false

    @State var msgToSend = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State var fetchedUrls: [urlContainer] = []
    
    @State var isShareClicked: Bool = false
    
    var body: some View {

        DispatchQueue.main.async {

            self.cancellableSet.forEach {
//                print("cancelling")
                $0.cancel()
            }
            self.cancellableSet.removeAll()
            
            print("cancellable count: \(self.cancellableSet.count)")
            
            /* important: this needs to be cancelled in onDisappear as the sinks remains even after */
            self.cancellableSet.insert(

                self.feedData.xmppController.didGetUploadUrl.sink(receiveValue: { iq in
                    
                    var urlCon: urlContainer = urlContainer()
                    
                    (urlCon.getUrl, urlCon.putUrl) = Utils().parseMediaUrl(iq)
                    
                    print("got url: \(urlCon.getUrl)")
                    self.fetchedUrls.append(urlCon)
                    
                    
                    // preemptive uploads
                    if (self.fetchedUrls.count != 0 && self.pickedImages.count != 0) {
                        if (self.fetchedUrls.count == self.pickedImages.count) {

                            var arr: [FeedMedia] = []
                            var index = 0

                            for img in self.pickedImages {
                                
                                let feedMedia = FeedMedia()
                                feedMedia.type = "image"
                                feedMedia.url = self.fetchedUrls[index].putUrl
                                feedMedia.image = img
                                arr.append(feedMedia)
 
                                index += 1
                            }
                            
                            
                            ImageServer().uploadMultiple(media: arr)
                            
                        }
                    }
                    
                    
                    
                })
                

            )
        }
        
        return Background {
            VStack {
                
                Divider()
                    .frame(height: UIScreen.main.bounds.height < 812 ? 10 : 40)
                    .hidden()
                
                HStack() {

                    Button(action: {
//                        if (!self.isJustText) {
//                            ImageServer().deleteImage(imageUrl: self.imageUrl)
//                            self.isJustText = true
//                        }
//                        self.onDismiss()
                        self.homeRouteData.gotoPage(page: "feed")
                        
                    }) {
                        Text("Cancel")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.gray)
                            .padding(EdgeInsets(top: 15, leading: 20, bottom: 0, trailing: 15))
                    }
                    Spacer()
                }
                
                
                Divider()
                    .frame(height: self.isJustText ? 15 : 0)
                    .hidden()

//                if item.media.count > 0 {
//
//                    MediaSlider(item, item.mediaHeight)
//                }
              
                if (self.pickedImages.count > 1) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(self.pickedImages, id: \.self) { img in
                                Image(uiImage: img)
                                          .resizable()
                                          .aspectRatio(img.size, contentMode: .fit)
                                          .frame(maxHeight: 200)
                                      
                                          .background(Color.gray)
                                          .cornerRadius(10)
                                          .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                            }
                        }
                    }
                } else if self.pickedImages.count == 1 {
                    Image(uiImage: self.pickedImages[0])
                        .resizable()
                        .aspectRatio(self.pickedImages[0].size, contentMode: .fit)
                        .frame(maxHeight: 200)

                        .background(Color.gray)
                        .cornerRadius(10)
                        .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                }

                
                HStack {
                    TextView(text: self.$msgToSend)
                        
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                    
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: self.isJustText ? 100 : 70)
                    .cornerRadius(10)
                }.padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

                Divider()
                    .frame(height: self.isJustText ? 20 : 5)
                    .hidden()
                
                Button(action: {
                        
                    if self.isShareClicked {
                        return
                    }
                    
                    if (self.fetchedUrls.count >= self.pickedImages.count) {
                        
                        self.isShareClicked = true
                        
                        var media: [FeedMedia] = []
                        var index: Int = 0
                        
                        self.pickedImages.forEach {
                            
                            var imageWidth = 0
                            var imageHeight = 0
               
                            imageWidth = Int($0.size.width)
                            imageHeight = Int($0.size.height)

                            let mediaItem: FeedMedia = FeedMedia()
                            mediaItem.type = "image"
                            mediaItem.width = Int(imageWidth)
                            mediaItem.height = Int(imageHeight)
                            mediaItem.url = self.fetchedUrls[index].getUrl
                            media.append(mediaItem)
                            index += 1
                        }

                        self.feedData.postText2(self.feedData.xmpp.userData.phone, self.msgToSend, media)

                        self.homeRouteData.gotoPage(page: "feed")
                        
                        self.msgToSend = ""

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.isShareClicked = false
                        }

                    }

                }) {

                    Text("SHARE")

                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .background(self.fetchedUrls.count >= self.pickedImages.count ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
       
                }
                
                Spacer()
                
            }
        }
        .onTapGesture {
            let keyWindow = UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .map({$0 as? UIWindowScene})
                    .compactMap({$0})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first
            keyWindow?.endEditing(true)
        }
        .onDisappear {
            self.cancellableSet.forEach {
//                print("cancelling")
                $0.cancel()
            }
            self.cancellableSet.removeAll()
        }

    }
}

//struct PostTextSheet_Previews: PreviewProvider {
//    static var previews: some View {
//        PostTextSheet(
//            feedData: FeedData(
//                xmpp: XMPP(userData: UserData())
//            )
//        )
//            .environmentObject(HomeRouteData())
//
//    }
//}
