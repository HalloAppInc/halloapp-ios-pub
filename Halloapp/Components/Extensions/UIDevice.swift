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
            guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return false }
            return keyWindow.safeAreaInsets.bottom > 0
        }
    }

}
