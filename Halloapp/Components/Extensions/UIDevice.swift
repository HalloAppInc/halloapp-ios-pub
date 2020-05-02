//
//  UIDevice.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIDevice {

    var hasNotch: Bool {
        get {
            let screen = UIScreen.main
            let screenHeight = max(screen.bounds.width, screen.bounds.height)

            // Unfortunately hardcoding is the only way to go because we sometimes need to know if
            // the device screen has a notch before the view controller's view is attached to the view
            // hierarchy or early on in the lifecycle of an extension process, before newly created
            // UIWindow instances are given valid safeAreaInsets.

            let heightX: CGFloat = 812
            let heightXR_Max: CGFloat = 896

            // Don't check UIScreen.scale -- these could be different if the user has enabled
            // Display Zoom on a large screen device. We expect iPhone XR and iPhone XS Max
            // to report a screen height of heightX if Display Zoom is enabled.
            let result = screenHeight == heightX || screenHeight == heightXR_Max
            return result
        }
    }

}
