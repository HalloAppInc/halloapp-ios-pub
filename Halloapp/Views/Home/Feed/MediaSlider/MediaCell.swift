//
//  MediaCell.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/31/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import SwiftUI

struct MediaCell: View {
    @ObservedObject var media: FeedMedia

    var body: some View {
        DDLogDebug("MediaCell/body [\(media.feedItemId)]:[\(media.order)]")
        return HStack {

            if ((media.type == "image" || media.type == "") && media.image.size.width > 0) { // important, app crashes without this check

                Image(uiImage: media.image)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(media.image.size, contentMode: .fit)
                    .background(Color.gray)
                    .cornerRadius(10)
                    .pinchToZoom()

            } else if (media.type == "video") {

                if (media.tempUrl != nil) {
                    /* note: in the simulator, this debug message appears when scrolling:
                     [framework] CUICatalog: Invalid asset name supplied: '(null)'
                     */
                    WAVPlayer(videoURL: media.tempUrl!)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "video")
                            .foregroundColor(Color.gray)
                        Spacer()
                    }
                }

            } else {

                VStack {
                    Spacer()
                    Image(systemName: "photo")
                        .foregroundColor(Color.gray)
                    Spacer()
                }
            }
        }
    }
}

