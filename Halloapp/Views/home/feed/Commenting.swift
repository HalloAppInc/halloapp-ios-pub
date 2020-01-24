//
//  Details.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/13/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct Commenting: View {
    
    @EnvironmentObject var homeRouteData: HomeRouteData

    @EnvironmentObject var feedRouterData: FeedRouterData
    
    @ObservedObject var feedData: FeedData
    
    @ObservedObject var contacts: Contacts
    
    var itemToBe: FeedDataItem
    
    @State var item: FeedDataItem
    
    @State var comments: [FeedComment] = []
    
    @State var msgToSend = ""
    
    @State var scroll = ""
    
    @State var replyTo = ""
    @State var replyToName = ""
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    
    init(_ feedData: FeedData, _ item: FeedDataItem, _ contacts: Contacts) {
        self.feedData = feedData
        self.itemToBe = item
        self.contacts = contacts
        
        self._item = State(initialValue: item)
        

        
//        self._comments = State(initialValue: self.feedData.feedCommentItems.filter {
//            $0.feedItemId == self.itemToBe.itemId
//        })
       
    }
    
    var body: some View {
        
        DispatchQueue.main.async {

            // needed or else 1st post doesn't seem to update?!?!
            let filteredComments = self.feedData.feedCommentItems.filter {
                return $0.feedItemId == self.item.itemId
            }
            
            self.comments = Utils().sortComments(comments: filteredComments)
            
            if self.comments.count > 0 {
                if self.item.unreadComments > 0 {
                    print("marking")
                    self.feedData.markFeedItemUnreadComments(comment: self.comments[0])
                }
            }
            
            self.cancellableSet.insert(

                self.feedData.objectWillChange.sink(receiveValue: { iq in
                    
                    let filteredComments = self.feedData.feedCommentItems.filter {
                        return $0.feedItemId == self.item.itemId
                    }
                    
                    self.comments = Utils().sortComments(comments: filteredComments)
                    
                    
                })

            )
            
        }
        
        return VStack() {

            
            
            WUICollectionView(
                item: $item,
                comments: $comments,
                scroll: $scroll,
                replyTo: $replyTo,
                replyToName: $replyToName,
                msgToSend: $msgToSend,
                contacts: contacts)
                .background(Color.red)
            
        }
  

        
        .overlay(
            BlurView(style: .extraLight)
                .frame(height: 96),
                alignment: .top
        )
                      
        .overlay(
            HStack() {
              
                ZStack() {
                    HStack {
                        
                        Button(action: {
                            
                            self.homeRouteData.setIsGoingBack(value: true)
                            
                            self.homeRouteData.lastClickedComment = self.item.itemId
                            
                            let keyWindow = UIApplication.shared.connectedScenes
                                    .filter({$0.activationState == .foregroundActive})
                                    .map({$0 as? UIWindowScene})
                                    .compactMap({$0})
                                    .first?.windows
                                    .filter({$0.isKeyWindow}).first
                            keyWindow?.endEditing(true)
                            
                            self.homeRouteData.gotoPage(page: "feed")
                        }) {
                            Image(systemName: "chevron.left")
                              .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)
                                
                                .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 25))

                        }
                        
            
                        
                    }
                }
                
                Spacer()
                
                Text("Comments")
                    .font(.custom("Arial", size: 30))
                    .fontWeight(.heavy)
                    .foregroundColor(Color(red: 220/255, green: 220/255, blue: 220/255))
                    .padding()
                
                Spacer()

                ZStack() {
                    HStack {
                        
                        Button(action: {
                        }) {
                            Image(systemName: "plus")
                              .font(Font.title.weight(.regular))
                                .foregroundColor(Color.black)
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 25))
                        }
                        .hidden()
                        
                    }
                }
                
              
            }
            .padding(EdgeInsets(top: 30, leading: 0, bottom: 0, trailing: 0))
            .background(Color.clear),
            alignment: .top

        )

        .overlay(
            BlurView(style: .extraLight)
                .frame(height: 100),
                alignment: .bottom
        )
        .overlay(
            VStack(spacing: 0) {
                
                if (replyTo != "") {
                    
                    HStack() {
                        Text("Replying to \(replyToName)")
                            .foregroundColor(Color.gray)
                            
                            .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 15))
                        Spacer()
                        
                        
                        Button(action: {
                            
                            self.replyTo = ""
                            self.replyToName = ""
                            self.msgToSend = ""
                            
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.gray)
                                .padding()
                        }
                        
                        
                    
                    }
                    .background(Color(red: 248/255, green: 248/255, blue: 248/255, opacity: 0.9))
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 13, trailing: 0))
                   
                }
                
                HStack {
                    TextField("Add a comment", text: self.$msgToSend, onEditingChanged: { (changed) in
                        if changed {
                         
                        } else {

                        }
                    }) {

                        if (self.msgToSend != "") {
                            self.scroll = "0"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.feedData.postComment(self.item.itemId, self.item.username, self.msgToSend, self.replyTo)
                                
                                self.msgToSend = ""
                                self.replyTo = ""
                                self.replyToName = ""
                            }
                        }
                        
                    }
                    .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                    .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                    .cornerRadius(15)


                    Button(action: {
                        
                        if (self.msgToSend != "") {
                            self.scroll = "0"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.feedData.postComment(self.item.itemId, self.item.username, self.msgToSend, self.replyTo)
                                
                                self.msgToSend = ""
                                self.replyTo = ""
                                self.replyToName = ""
                            }
                            
                        }
                        
                        // slight delay for better UX
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let keyWindow = UIApplication.shared.connectedScenes
                                    .filter({$0.activationState == .foregroundActive})
                                    .map({$0 as? UIWindowScene})
                                    .compactMap({$0})
                                    .first?.windows
                                    .filter({$0.isKeyWindow}).first
                            keyWindow?.endEditing(true)
                        }
                        
    //                    self.scroll = "doit"
    //
    //                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    //                        self.scroll = ""
    //                    }

                    }) {
                        Text("Post")

                            .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                            .background(self.msgToSend == "" ? Color.gray : Color.blue)
                            .foregroundColor(Color.white)
                            .cornerRadius(15)
                            .shadow(radius: 2)

                    }
                }
                .padding(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15))
            }
//            .padding(EdgeInsets(top: 10, leading: 15, bottom: 45, trailing: 15)),
            .padding(EdgeInsets(top: 10, leading: 0, bottom: 45, trailing: 0)),
            alignment: .bottom
        )
        
        .background(Color(red: 248/255, green: 248/255, blue: 248/255))
        .onTapGesture {
            let keyWindow = UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .map({$0 as? UIWindowScene})
                    .compactMap({$0})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first
            keyWindow?.endEditing(true)
            
        }
        .KeyboardAwarePadding()

        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            
        .edgesIgnoringSafeArea(.all)
    }
    

}

//struct Commenting_Previews: PreviewProvider {
//    static var previews: some View {
//        Commenting()
//    }
//}
