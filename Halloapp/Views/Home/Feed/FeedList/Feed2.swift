import SwiftUI
import Combine

struct Feed2: View {
    
    @EnvironmentObject var feedRouterData: FeedRouterData
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    @EnvironmentObject var userData: UserData

    @ObservedObject var feedData: FeedData
    @ObservedObject var contacts: Contacts
    
    @State private var showSheet = false
    
    @State private var showMediaPicker = false
    @State private var showPostMedia = false
    
    @State private var showImagePicker = false
    @State private var showNotifications = false
    @State private var showPostText = false

    @State private var isJustText = true

    @State private var showMoreActions = false

    @State private var showNetworkAlert = false
    @State private var postId = ""
    @State private var username = ""
    @State private var showMessages = false
    
    @State private var pickedImages: [FeedMedia] = []
    
    @EnvironmentObject var metaData: MetaData
    
    @State private var detailsPage = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State private var commentClickable = true
    @State private var lastClickedComment = ""
    
    @State private var scroll: String = ""
    
    @State private var pageNum: Int = 0
    
    init(feedData: FeedData, contacts: Contacts) {
        
        self.feedData = feedData
        self.contacts = contacts
            
    }
    
    var body: some View {
        
        return VStack() {
            
            WFeedList(
                isOnProfilePage: false,
                items: self.feedData.feedDataItems,
                showSheet: $showSheet,
                showMessages: $showMessages,
                lastClickedComment: $lastClickedComment,
                scroll: $scroll,
                pageNum: $pageNum,
                homeRouteData: homeRouteData,
                contacts: contacts,
                paging: { num in
//                   print("pagenum: \(num)")
                },
                getItemMedia: { itemId in
                    self.feedData.getItemMedia(itemId)
                },
                removeItemMedia: { itemId in
//                   let idx = self.items.firstIndex(where: {$0.itemId == itemId})
//                   if idx != nil {
//                       self.items[idx!].media = []
//                       self.items[idx!].media.removeAll()
//                   }
//                    self.feedData.removeItemMedia(itemId)
                },
                setItemCellHeight: { itemId, cellHeight in
                    self.feedData.setItemCellHeight(itemId, cellHeight)
                }
            )
            
        }
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
            
            
            
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 76 : 96),
                alignment: .top
        )
        .overlay(
            HStack() {
                
                Text("Home")
                    .font(.custom("Arial", size: 36))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                
                if (self.feedData.isConnecting) {
                    Text("connecting...")
                        .font(.custom("Arial", size: 16))
                        .foregroundColor(Color.green)
                }
                
                Spacer()

                ZStack() {
                    HStack {
                        
                        Button(action: {
                            self.showNotifications = true
                            self.showSheet = true
                        }) {
                            Image(systemName: "bell")
                                .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)
                        }
                        .padding()
                        .padding(.trailing, 0)
                        
                        
                        Button(action: {
                            if (self.feedData.isConnecting) {
                                self.showNetworkAlert = true
                            } else {
                                self.showMoreActions = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)

                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 25))

                        }
                        
                    }
                }
               
                
            }
            .padding(EdgeInsets(top: UIScreen.main.bounds.height < 812 ? 5 : 25, leading: 0, bottom: 0, trailing: 0))
            
            .background(Color.clear),
            alignment: .top
        )

        .overlay(
            BlurView(style: .extraLight)
                .frame(height: UIScreen.main.bounds.height < 812 ? 60 : 85),
            alignment: .bottom
        )
        .overlay(
          Navi(),
          alignment: .bottom
        )
            
        .edgesIgnoringSafeArea(.all)

        .sheet(isPresented: self.$showSheet, content: {
        
            if (self.showImagePicker) {

                ImagePicker(showPostText: self.$showPostText,
                            showSheet: self.$showSheet,
                            showImagePicker: self.$showImagePicker,
                            pickedImages: self.$pickedImages,
                            goToPostMedia: {
                                Utils().requestMultipleUploadUrl(xmppStream: self.feedData.xmppController.xmppStream, num: self.pickedImages.count)
                            }
                )
                
            } else if (self.showNotifications) {
                Notifications(onDismiss: {
                    self.showNotifications = false
                    self.showSheet = false
                })
            } else if (self.showPostText) {
                
                PostMedia(
                    feedData: self.feedData,
                    pickedImages: self.pickedImages,
                    onDismiss: {
                        
                        self.pickedImages.removeAll()
                        
                        self.showSheet = false
                        self.showPostText = false
                    }
                )
                .environmentObject(self.homeRouteData)
                
            } else {
                MessageUser(onDismiss: {
                    self.showSheet = false
                    self.showPostText = false
                    
                })
            }
        })
            
        .actionSheet(isPresented: self.$showMoreActions) {
            ActionSheet(
                title: Text(""),
                buttons: [
                    .default(Text("Photo Library"), action: {
                          self.isJustText = false
                          self.homeRouteData.gotoPage(page: "media")
                    }),
                    .default(Text("Camera"), action: {
                        self.isJustText = false
        
                        self.showImagePicker = true
                        self.showSheet = true
                        self.showMoreActions = false
                    }),
                    .default(Text("Text"), action: {
                        self.isJustText = true
                        self.showPostText = true
                        self.showSheet = true
                        self.showMoreActions = false
                        
                    }),
                    .destructive(Text("Cancel"), action: {
                        self.showMoreActions = false
                    })
                ]
            )
        }
        .alert(isPresented: $showNetworkAlert) {
            Alert(title: Text("Couldn't connect to Halloapp"), message: Text("We'll keep trying, but there may be a problem with your connection"), dismissButton: .default(Text("Ok")))
        }


    }
    
}

