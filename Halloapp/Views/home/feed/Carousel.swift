//
//  Carousel.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct Carousel: View {
    
    @ObservedObject var item: FeedDataItem
    var mediaHeight: CGFloat
    
    let landscapeHeight: CGFloat = 300 // seems optimal, 260?
    
    @State var scroll = ""
    
    @State var media: [FeedMedia] = []
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State var height: CGFloat = 525.33 // change to desired height to reduce screen shift, can customize for different devices
    
    @State var pageNum: Int = 0
    
    init(_ item: FeedDataItem, _ mediaHeight: CGFloat) {
        
        self.item = item
        self.mediaHeight = mediaHeight
        self._media = State(initialValue: self.item.media)
       
    }
    
    func calHeight() {
        
        var maxHeight = 0
        var width = 0
        
        for med in self.media {
            if med.height > maxHeight {

                maxHeight = med.height
                width = med.width
            }
        }
        
        if maxHeight < 1 {
            return
        }
        
        let desiredAspectRatio: Float = 4/3 // 1.33 for portrait
        
        // can be customized for different devices
        let desiredViewWidth = Float(UIScreen.main.bounds.width) - 20 // account for padding on left and right
        
        let desiredTallness = desiredAspectRatio * desiredViewWidth
        
        let ratio = Float(maxHeight)/Float(width) // image ratio

        let actualTallness = ratio * desiredViewWidth

        if actualTallness >= desiredTallness {
            self.height = CGFloat(desiredTallness)
        } else {
            self.height = CGFloat(actualTallness + 10)
        }
        
    }
    

    
    var body: some View {
        
        DispatchQueue.main.async {

            self.media = self.item.media
     
            self.calHeight()
            
            self.cancellableSet.insert(

                /* for new items */
                self.item.objectWillChange.sink(receiveValue: { iq in
                    
                    self.media = self.item.media
                    
                    self.calHeight()
                    

                    
                })

            )
            
        }
        
        return HStack() {
            
            VStack(spacing: 0) {
                
                
                WMediaSlider (
                    media: $media,
                    scroll: $scroll,
                    height: $height,
                    pageNum: $pageNum)

                    .frame(height: self.height)
                
                

                if (self.media.count > 1) {
                    HStack() {
                        Spacer()
                        
                        ForEach(self.media) { med in
                            
                            Image(systemName: "circle.fill")
                                .resizable()
                             
                                .scaledToFit()
                                .foregroundColor(self.pageNum == self.media.firstIndex(of: med) ? Color(red:  0/255, green: 128/255, blue:  255/255) : Color(red:  220/255, green: 220/255, blue:  220/255))
                                .clipShape(Circle())
                             
                                .frame(width: 5, height: 5, alignment: .center)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            
        
                        }
                        
                        Spacer()
                    }
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))
                }
                
            }

            
        
//            ForEach(self.item.media) { med in
//
//                Image(uiImage: med.image)
//
//                    .resizable()
//                    .aspectRatio(med.image.size, contentMode: .fit)
//                    .background(Color.gray)
//                    .cornerRadius(10)
//                    .padding(EdgeInsets(top: 10, leading: 10, bottom: 15, trailing: 10))
//
//            }


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


