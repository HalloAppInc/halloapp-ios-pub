//
//  NSAttributedString.swift
//  Core
//
//  Created by Garrett on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import UIKit

public extension NSAttributedString {
    var fullExtent: NSRange { NSRange(location: 0, length: length) }

    func with(font: UIFont) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: self)
        mutableString.addAttribute(.font, value: font, range: fullExtent)
        return mutableString
    }
}

public extension NSAttributedString.Key {
    static let userMention = NSAttributedString.Key("userMention")
}
