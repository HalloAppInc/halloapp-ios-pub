//
//  Media.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI


struct Media: View {
    
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    @ObservedObject var feedData: FeedData
    
    @State private var showPostMedia = false
    @State private var pickedImages: [UIImage] = []
    
    var body: some View {
        return VStack(spacing: 0) {
            if (!self.showPostMedia) {
                PickerWrapper(
                    pickedImages: self.$pickedImages,
                    goBack: {
                        self.homeRouteData.gotoPage(page: "feed")
                    },
                    requestUrls: {
                        Utils().requestMultipleUploadUrl(xmppStream: self.feedData.xmppController.xmppStream, num: self.pickedImages.count)
                    },
                    goToPostMedia: {
                        self.showPostMedia = true
                    }
                )
            } else {
                
                PostMedia(
                    feedData: feedData,
                    pickedImages: self.pickedImages
                )
                .environmentObject(homeRouteData)
                
            }
        }
    }
}

//struct Media_Previews: PreviewProvider {
//    static var previews: some View {
//        Media()
//    }
//}
