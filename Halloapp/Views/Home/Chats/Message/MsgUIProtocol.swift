//
//  MsgUIProtocol.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/16/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol MsgUIProtocol {
    var TextFontStyle: UIFont.TextStyle { get }
    var MaxWidthOfMsgBubble: CGFloat { get }

    func preferredSize(for media: [ChatMedia]) -> CGSize
}

extension MsgUIProtocol {
    var TextFontStyle: UIFont.TextStyle { return .subheadline }
    var MaxWidthOfMsgBubble: CGFloat { return UIScreen.main.bounds.width * 0.8 }

    func preferredSize(for media: [ChatMedia]) -> CGSize {
        guard !media.isEmpty else { return CGSize(width: 0, height: 0) }

        let maxRatio: CGFloat = 5/4 // height/width
        // should be smaller than bubble width to avoid constraint conflicts
        let maxWidth = MaxWidthOfMsgBubble - 10
        let maxHeight = maxWidth*maxRatio

        var tallest: CGFloat = 0
        var widest: CGFloat = 0
        for med in media {
            let ratio = med.size.height/med.size.width
            let height = maxWidth*ratio
            let width = maxHeight/ratio

            tallest = max(tallest, height)
            widest = max(widest, width)
        }

        tallest = min(tallest, maxHeight)
        widest = min(widest, maxWidth)
        return CGSize(width: widest, height: tallest)
    }
}
