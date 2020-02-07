
import SwiftUI

struct Background<Content: View>: View {
    private var content: Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color.white
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .overlay(content)
    }
}

struct PostTextSheet: View {
    
    @ObservedObject var feedData: FeedData
    
    @Binding var imageUrl: String
    
    @Binding var gotImage: Image
    @Binding var pickedUIImage: UIImage
    
    @Binding var pickerStatus: String
    @Binding var isJustText: Bool
    
    var onDismiss: () -> ()
    
    
    @EnvironmentObject var userData: UserData
    

    @State var msgToSend = ""
    

    
    var body: some View {
        Background {
            VStack {
                
                Divider()
                    .frame(height: UIScreen.main.bounds.height < 812 ? 10 : 40)
                    .hidden()
                
                HStack() {
                    Spacer()
                    Button(action: {
                        if (!self.isJustText) {
                            ImageServer().deleteImage(imageUrl: self.imageUrl)
                            self.isJustText = true
                        }
                        self.onDismiss()
                        
                    }) {
                        Text("Cancel")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.gray)
                            .padding(EdgeInsets(top: 15, leading: 20, bottom: 0, trailing: 15))
                    }
                }
                
                
                Divider()
                    .frame(height: self.isJustText ? 15 : 0)
                    .hidden()


                if (!self.isJustText) {
                    
                    self.gotImage
                            .resizable()
                            .aspectRatio(self.pickedUIImage.size, contentMode: .fit)
                            .frame(maxHeight: 200)
                        
                            .background(Color.gray)
                            .cornerRadius(10)
                            .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))

                }
                
    //
                
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
                        
                    if (
                        (self.isJustText && self.msgToSend != "") ||
                            (!self.isJustText && self.pickerStatus != "uploading")
                        ) {
                        
                        
                        var media: [FeedMedia] = []
                        
                        var imageWidth = 0
                        var imageHeight = 0
                        
                         if !self.isJustText {
                            imageWidth = Int(self.pickedUIImage.size.width)
                            imageHeight = Int(self.pickedUIImage.size.height)
                            
                            let mediaItem: FeedMedia = FeedMedia()
                            mediaItem.type = "image"
                            mediaItem.width = Int(imageWidth)
                            mediaItem.height = Int(imageHeight)
                            mediaItem.url = self.imageUrl
                            media.append(mediaItem)
                            
                        }
                        
                        
                        self.feedData.postText(self.userData.phone, self.msgToSend, media)
                        
                        
                        self.msgToSend = ""
                        
                        self.isJustText = true
                        self.onDismiss()

                    }

                }) {

                    Text("SHARE")

                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .background(
                            (
                                (self.isJustText && self.msgToSend != "") ||
                                (!self.isJustText && self.pickerStatus != "uploading")
                            )
                            ? Color.blue : Color.gray)
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
