//
//  UIApplication.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIApplication {
    
    var version: String {
        get {
            guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                return ""
            }
            guard let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
                return "\(version)"
            }
            return "\(version) (\(buildNumber))"
        }
    }
}
