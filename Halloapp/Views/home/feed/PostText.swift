
import SwiftUI

struct PostText: View {
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @EnvironmentObject var userData: UserData
    
    @ObservedObject var feedData: FeedData
    
    var imageUrl = ""
    
    
    @State var msgToSend = ""
    
    var body: some View {
        VStack {

            Spacer()

            HStack {
                TextField("", text: $msgToSend, onEditingChanged: { (changed) in
                    if changed {
                        
                    } else {
            
                    }
                }) {


                }
                .padding(.all)
                .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                .cornerRadius(10)
            }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))

            Spacer()
            
            Button(action: {
                
                if (self.msgToSend != "") {
                    self.feedData.postText(self.userData.phone, self.msgToSend, self.imageUrl)
                    
                    self.msgToSend = ""
                    
                    self.homeRouteData.gotoPage(page: "feed")
                }

            }) {
//                    Image(systemName: "paperplane.fill")
//                        .imageScale(.large)
//                        .foregroundColor(Color.blue)
                Text("Post")

                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
   
            }
            
            Spacer()
            
            Navi()
        }
    }
}

struct PostText_Previews: PreviewProvider {
    static var previews: some View {
        PostText(feedData: FeedData(xmpp: XMPP(userData: UserData(), metaData: MetaData())))
            .environmentObject(HomeRouteData())
   
    }
}
