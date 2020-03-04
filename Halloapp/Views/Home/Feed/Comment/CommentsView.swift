//
//  CommentsView.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/13/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct CommentsView: View {
    @EnvironmentObject var feedData: FeedData
    @EnvironmentObject var contacts: Contacts
    
    var itemToBe: FeedDataItem
    
    @State var item: FeedDataItem
    
    @State var comments: [FeedComment] = []
    
    @State var msgToSend = ""
    @State var scroll = ""
    @State var replyTo = ""
    @State var replyToName = ""
    @State var cancellableSet: Set<AnyCancellable> = []

    @State private var showNetworkAlert = false

    init(_ item: FeedDataItem) {
        self.itemToBe = item
        self._item = State(initialValue: item)
    }
    
    var body: some View {
        
        DispatchQueue.main.async {
            // needed or else 1st post doesn't seem to update?!?!
            let filteredComments = self.feedData.feedCommentItems.filter {
                return $0.feedItemId == self.item.itemId
            }

            self.comments = Utils().sortComments(comments: filteredComments)
            
//            let filteredComments = FeedCommentCore().get(feedItemId: self.item.itemId)
//            self.comments = Utils().sortComments(comments: filteredComments)
            
            if self.comments.count > 0 {
                if self.item.unreadComments > 0 {
                    self.feedData.markFeedItemUnreadComments(comment: self.comments[0])
                }
            }
            
            self.cancellableSet.forEach {
                $0.cancel()
            }
            self.cancellableSet.removeAll()
            
            self.cancellableSet.insert(
                self.feedData.objectWillChange.sink(receiveValue: { iq in
                    let filteredComments = self.feedData.feedCommentItems.filter {
                        return $0.feedItemId == self.item.itemId
                    }
                    
                    self.comments = Utils().sortComments(comments: filteredComments)
                    
//                    let filteredComments = FeedCommentCore().get(feedItemId: self.item.itemId)
//                    self.comments = Utils().sortComments(comments: filteredComments)
                })
            )
        }
        
        return VStack() {
            CommentsCollectionView(
                item: $item,
                comments: $comments,
                scroll: $scroll,
                replyTo: $replyTo,
                replyToName: $replyToName,
                msgToSend: $msgToSend,
                contacts: contacts)
                .background(Color.red)
        }
        .navigationBarTitle("Comments", displayMode: .inline)

        // Compose box
        .overlay(
            VStack(spacing: 0) {
                Divider()

                // "Replying to" panel
                if (replyTo != "") {
                    HStack() {
                        Text("Replying to \(replyToName != "Me" ? replyToName : "myself" )")
                            .foregroundColor(Color.secondary)
                        Spacer(minLength: 15)

                        ///TODO: v-align this with text
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
                    .padding(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 15))
                }

                // Text field + Post button
                HStack {
                    TextField("Add a comment", text: self.$msgToSend, onEditingChanged: { (changed) in
                        if changed {
                         
                        } else {

                        }
                    }) {
                        if (self.msgToSend != "") {
                            self.feedData.postComment(self.item.itemId, self.item.username, self.msgToSend, self.replyTo)
                            
                            self.msgToSend = ""
                            self.replyTo = ""
                            self.replyToName = ""
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.scroll = "0"
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(15)

                    Button(action: {
                        if (self.feedData.isConnecting) {
                            self.showNetworkAlert = true
                            return
                        }
                        
                        if (self.msgToSend != "") {
                            
                            self.feedData.postComment(self.item.itemId, self.item.username, self.msgToSend, self.replyTo)
                            
                            self.msgToSend = ""
                            self.replyTo = ""
                            self.replyToName = ""
                        
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.scroll = "0"
                            }
                        }
                        
                        // slight delay for better UX
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            let keyWindow = UIApplication.shared.connectedScenes
                                    .filter({$0.activationState == .foregroundActive})
                                    .map({$0 as? UIWindowScene})
                                    .compactMap({$0})
                                    .first?.windows
                                    .filter({$0.isKeyWindow}).first
                            keyWindow?.endEditing(true)
                        }
                    }) {
                        Text("Post")
                            .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                            .background(self.msgToSend == "" ? Color.gray : Color.blue)
                            .foregroundColor(Color.white)
                            .cornerRadius(15)
                            .shadow(radius: 2)
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15))
            }
            .background(BlurView(style: .systemChromeMaterial))
            .padding(.zero),
            alignment: .bottom
        )
        
        .background(Color(UIColor.systemGray6))
            
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

        .alert(isPresented: $showNetworkAlert) {
            Alert(title: Text("Couldn't connect to Halloapp"), message: Text("We'll keep trying, but there may be a problem with your connection"), dismissButton: .default(Text("Ok")))
        }
            
        .onDisappear {
            self.cancellableSet.forEach {
                $0.cancel()
            }
            self.cancellableSet.removeAll()
        }
    }
}
