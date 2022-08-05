//
//  NSAttributedString.swift
//  HalloApp
//
//  Created by Tanveer on 8/4/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

extension NSMutableAttributedString {
    /// - Returns: An attributed string that is prefixed with the image and wrapped with isolates for compatibility
    ///            with right-to-left languages.
    class func string(_ string: String,
                    with image: UIImage,
                       spacing: Int = 1,
               imageAttributes: [NSAttributedString.Key: Any] = [:],
                textAttributes: [NSAttributedString.Key: Any] = [:]) -> NSMutableAttributedString {

        let spaces = spacing < 0 ? 0 : spacing
        var spacer = ""
        for _ in 0..<spaces { spacer += " " }

        let base = NSMutableAttributedString(attachment: NSTextAttachment(image: image))
        let text = NSMutableAttributedString(string: spacer + string)

        base.addAttributes(imageAttributes, range: NSMakeRange(0, base.length))
        text.addAttributes(textAttributes, range: NSMakeRange(0, text.length))

        base.append(text)
        base.insert(NSAttributedString(string: "\u{2068}"), at: 0) // first strong isolate
        base.insert(NSAttributedString(string: "\u{2069}"), at: base.length - 1) // pop directional isolate

        return base
    }
}
