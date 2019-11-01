//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

import XMPPFramework

class FeedData: ObservableObject {
    
    @Published var feedDataItems : [FeedDataItem] = []
    var cancellables = [AnyCancellable]()
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    @Published var firstItemId = ""
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(xmpp: XMPP) {
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController
        
        self.feedDataItems = [
            FeedDataItem(username: "Robert",
                          imageUrl: "https://cdn.pixabay.com/photo/2015/12/01/20/28/road-1072823_960_720.jpg",
                          userImageUrl: "https://cdn.pixabay.com/photo/2016/11/18/19/07/happy-1836445_1280.jpg",
                          text: ""),
            FeedDataItem(username: "Jessica",
                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/24/01/05/flower-4499972_640.jpg",
                          userImageUrl: "https://cdn.pixabay.com/photo/2018/01/25/14/12/nature-3106213_1280.jpg",
                          text: ""),
            FeedDataItem(username: "Timothy",
                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/21/06/59/dog-4493182_640.jpg",
                          userImageUrl: "https://cdn.pixabay.com/photo/2012/05/29/00/43/car-49278_1280.jpg",
                          text: ""),
            FeedDataItem(username: "Ashley",
                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/25/15/12/chapel-4503926_640.jpg",
                          userImageUrl: "https://cdn.pixabay.com/photo/2016/11/23/17/25/beach-1853939_1280.jpg",
                          text: "")
        ]
        
        
        self.feedDataItems.forEach({
            let c = $0.objectWillChange.sink(receiveValue: {
                self.firstItemId = self.feedDataItems[0].id.uuidString
                self.objectWillChange.send()
                
            })

            self.cancellables.append(c)
        })
        
        

//        do {
//            try self.xmppController = XMPPController(
//                                        hostName: "d.halloapp.dev",
//                                        userJIDString: "14154121848@s.halloapp.net/iphone",
//                                        password: "11111111")
//
//            self.xmppController.xmppStream.addDelegate(self, delegateQueue: DispatchQueue.main)
//            self.xmppController.connect()
//
//        } catch {
//            print("Something went wrong")
//        }

        
        cancellableSet.insert(
            
            xmppController.didChangeMessage.sink(receiveValue: { value in
            
                let a = ""
                let b = ""
                let c = ""
                let d = Utils().parseFeedItem(value)
                self.feedDataItems.insert(FeedDataItem(username: (a ?? ""), imageUrl: b, userImageUrl: c, text: (d ?? "")), at: 0)
                
                if let from = value.attribute(forName: "from")?.stringValue {
                    print("=== from: \(from)")
                }

            })
       
        )
    

    }
    
    
    func pushItem(username a: String, imageUrl b: String, userImageUrl c: String, text d: String) {
        self.feedDataItems.append(FeedDataItem(username: a, imageUrl: b, userImageUrl: c, text: d))
    }
    
    func sendMessage(text: String) {
        print("sendMessage: " + text)
//        let user = XMPPJID(string: "14154121848@s.halloapp.net")
//        let msg = XMPPMessage(type: "chat", to: user)
//        msg.addBody(text)
//        self.xmppController.xmppStream.send(msg)
//
//
      /* storing private data */
        
//        let item = XMLElement(name: "item", stringValue: "Rebecca")

//        let wrapper = XMLElement(name: "list")
//        wrapper.addAttribute(withName: "xmlns", stringValue: "feed:disallow")
////        wrapper.addChild(item)
//
//        let query = XMLElement(name: "query")
//        query.addAttribute(withName: "xmlns", stringValue: "jabber:iq:private")
//        query.addChild(wrapper)
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "set")
//        iq.addAttribute(withName: "id", stringValue: "1")
//        iq.addChild(query)
//        print("sending: \(iq)")
//        self.xmppController.xmppStream.send(iq)
        
        
        // get private data
//        let wrapper = XMLElement(name: "list")
//        wrapper.addAttribute(withName: "xmlns", stringValue: "feed:disallow")
//
//        let query = XMLElement(name: "query")
//        query.addAttribute(withName: "xmlns", stringValue: "jabber:iq:private")
//
//        query.addChild(wrapper)
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "get")
//        iq.addAttribute(withName: "id", stringValue: "1")
//        iq.addChild(query)
//        print("sending: \(iq)")
//        self.xmppController.xmppStream.send(iq)

        // let user2 = XMPPJID(string: "14154121848@s.halloapp.net")
        // self.xmppController.xmppRoster.addUser(user2!, withNickname: nil)
        
//        if let user2 = XMPPJID(string: "14154121848@s.halloapp.net")
//        {
//            self.xmppController.xmppRoster.addUser(user2)
//        }
        
        
    }
    
//   func getRoster() {
//        print("getRoster")
//        let user = XMPPJID(string: "14088922686@s.halloapp.net")
//
//        self.xmppController.xmppStream.send(msg)
//    }
    
//    func addEntryToRoster(id: String) {
//
//    }
    
}


class FeedDataItem: Identifiable, ObservableObject, Equatable {
    var id = UUID()
    var username: String
    var userImageUrl: String
    
    var text: String
    
    @Published var userImage: UIImage = UIImage()
//    @Published var userImageRatio: Double = Double()
    
    var imageUrl: String
    @Published var image: UIImage = UIImage()
//    @Published var imageRatio: Double = Double()
    
    @ObservedObject var imageLoader: ImageLoader
    @ObservedObject var userImageLoader: ImageLoader
    
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    static func == (lhs: FeedDataItem, rhs: FeedDataItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(username: String, imageUrl: String, userImageUrl: String, text: String) {

        self.username = username
        self.userImageUrl = userImageUrl
        userImageLoader = ImageLoader(urlString: self.userImageUrl)
        self.imageUrl = imageUrl
        imageLoader = ImageLoader(urlString: self.imageUrl)
        
        self.text = text
        
        cancellableSet.insert(
            userImageLoader.didChange.sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                self.userImage = UIImage(data: self.userImageLoader.data) ?? UIImage()
//                self.userImageRatio = Double(self.userImage.size.width / self.userImage.size.height)
            })
        )
        
        cancellableSet.insert(
            imageLoader.didChange.sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                self.image = UIImage(data: self.imageLoader.data) ?? UIImage()
//                self.imageRatio = Double(self.image.size.width / self.image.size.height)
            })
        )
        
    }
    
    
}


