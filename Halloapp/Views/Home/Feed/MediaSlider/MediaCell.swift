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
        return HStack {
            if (media.type == .image) {
                if media.isMediaAvailable {
                    Image(uiImage: media.image!)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(media.displayAspectRatio, contentMode: .fit)
                        .pinchToZoom()
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            } else if (media.type == .video) {

                if media.isMediaAvailable {
                    /* note: in the simulator, this debug message appears when scrolling:
                     [framework] CUICatalog: Invalid asset name supplied: '(null)'
                     */
                    WAVPlayer(videoURL: media.fileURL!)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "video")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
        }
    }
}

