//
//  UIView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIView {

    func alignedCenter(from center: CGPoint, flippedForRTL flipForRTL: Bool = false) -> CGPoint {
        let screenScale = UIScreen.main.scale
        let size = self.bounds.size
        let originX = center.x - size.width * 0.5
        var alignedCenter = center
        alignedCenter.x += (originX * screenScale).rounded()/screenScale - originX
        let originY = center.y - size.height * 0.5
        alignedCenter.y += (originY * screenScale).rounded()/screenScale - originY
        if flipForRTL && self.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            if let superView = self.superview {
                alignedCenter.x = superView.bounds.size.width - center.x
            }
        }
        return alignedCenter
    }

}
