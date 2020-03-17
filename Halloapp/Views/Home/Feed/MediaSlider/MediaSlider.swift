
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Combine

struct MediaSlider: View {
    
    @ObservedObject var item: FeedDataItem
    
    let landscapeHeight: CGFloat = 300 // seems optimal, 260?
    
    @State var scroll = ""
    
    @State var media: [FeedMedia] = []
    
    @State var cancellableSet: Set<AnyCancellable> = []
    
    @State var mediaHeight: CGFloat
    
    @State var pageNum: Int = 0
    
    init(_ item: FeedDataItem, _ mediaHeight: Int) {
        self.item = item
        
        self._mediaHeight = State(initialValue: CGFloat(mediaHeight))
        self._media = State(initialValue: self.item.media)
    }
    
    var body: some View {
        
        DispatchQueue.main.async {

            self.media = self.item.media
     
            self.cancellableSet.insert(

                /* for new items */
                self.item.objectWillChange.sink(receiveValue: { iq in
                    
                    self.media = self.item.media
                    
//                    self.calHeight()
                    
                })

            )
            
        }
        
        return HStack() {
            
            VStack(spacing: 0) {
                
                WMediaSlider (
                    media: $media,
                    scroll: $scroll,
                    height: $mediaHeight,
                    pageNum: $pageNum)
                    .frame(height: self.mediaHeight)
                
                
                if (self.media.count > 1) {
                    HStack() {
                        Spacer()
            
                        /* media indicator dots */
                        ForEach(self.media.indices) { index in
            
                            Image(systemName: "circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(self.pageNum == index ? Color.blue : Color(UIColor.systemGray4))
                                .clipShape(Circle())
                             
                                .frame(width: 5, height: 5, alignment: .center)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            
                        }
                        
                        Spacer()
                    }
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))
                }
                
            }

        }
        .onDisappear {
            self.cancellableSet.forEach {
                $0.cancel()
            }
            DispatchQueue.main.async() {
                self.cancellableSet.removeAll()
            }
        }
    }
}
