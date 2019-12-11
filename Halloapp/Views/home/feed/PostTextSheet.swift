
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
 
        VStack {

            HStack() {
                Spacer()
                Button(action: {
                    self.isJustText = true
                    self.onDismiss()
                    
                }) {
                    Text("Cancel")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.gray)
                        .padding()
                }
            }
            
            
            Divider()
                .frame(height: isJustText ? 30 : 0)
                .hidden()


            if (!isJustText) {
                
                gotImage
                        .resizable()
                        .aspectRatio(self.pickedUIImage.size, contentMode: .fit)
                        .frame(maxHeight: 200)
                    
                        .background(Color.gray)
                        .cornerRadius(10)
                        .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))

            }
            
//
            
            HStack {
                TextView(text: $msgToSend)
                    
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: isJustText ? 100 : 70)
                .cornerRadius(10)
            }.padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            Divider()
                .frame(height: isJustText ? 20 : 5)
                .hidden()
            
            Button(action: {
                    
                if (
                    (self.isJustText && self.msgToSend != "") ||
                        (!self.isJustText && self.pickerStatus != "uploading")
                    ) {
                    self.feedData.postText(self.userData.phone, self.msgToSend, self.imageUrl)
                    
                    
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
