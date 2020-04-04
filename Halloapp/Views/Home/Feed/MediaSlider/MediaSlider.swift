
//  Halloapp
//
//  Created by Tony Jiang on 1/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import SwiftUI

struct MediaSlider: View {
    @ObservedObject var item: FeedDataItem

    @State var media: [FeedMedia]
    @State var cancellableSet: Set<AnyCancellable> = []
    @State var pageNum: Int = 0
    
    init(_ item: FeedDataItem) {
        DDLogDebug("MediaSlider/init [\(item.itemId)]")
        self.item = item
        self._media = State(initialValue: item.media)
    }
    
    var body: some View {        
        DispatchQueue.main.async {
            self.media = self.item.media

            self.cancellableSet.insert(
                /* for new items */
                self.item.objectWillChange.sink { _ in
                    DDLogDebug("MediaSlider/objectWillChange [\(self.item.itemId)]")
                    self.media = self.item.media
                }
            )
        }

        DDLogDebug("MediaSlider/body [\(item.itemId)]: \(self.media.count) items")
        return
            VStack(spacing: 5) {
                WMediaSlider(media: $media, pageNum: $pageNum)

                if (self.media.count > 1) {
                    HStack {
                        Spacer()

                        /* media indicator dots */
                        ForEach(self.media.indices) { index in
                            Image(systemName: "circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(self.pageNum == index ? Color.blue : Color(UIColor.systemGray4))
                                .frame(width: 5, height: 5, alignment: .center)
                        }

                        Spacer()
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
