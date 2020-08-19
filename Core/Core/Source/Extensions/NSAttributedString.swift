//
//  NSAttributedString.swift
//  Core
//
//  Created by Garrett on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import UIKit

public extension NSAttributedString {
    var utf16Extent: NSRange { NSRange(location: 0, length: length) }

    func with(font: UIFont? = nil, color: UIColor? = nil) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: self)
        if let font = font {
            mutableString.addAttribute(.font, value: font, range: utf16Extent)
        }
        if let color = color {
            mutableString.addAttribute(.foregroundColor, value: color, range: utf16Extent)
        }
        return mutableString
    }
}

public extension NSAttributedString.Key {
    static let userMention = NSAttributedString.Key("userMention")
}
