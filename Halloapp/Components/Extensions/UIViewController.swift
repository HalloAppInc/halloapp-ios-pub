//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIViewController {

    var largeTitleUsingGothamFont: NSAttributedString? {
        get {
            guard self.title != nil else { return nil }
            let attributes: [ NSAttributedString.Key : Any ] =
                [ .font: UIFont.gothamFont(ofSize: 33, weight: .bold),
                  .foregroundColor: UIColor.label.withAlphaComponent(0.1),
                  .kern: -1.5 ]
            return NSAttributedString(string: self.title!, attributes: attributes)
        }
    }
}
