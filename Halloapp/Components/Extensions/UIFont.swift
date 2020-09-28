//
//  UIFont.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIFont {

    class func gothamFont(ofSize fontSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let suffix: String = {
        switch weight {
        case  .ultraLight: return "Ultra"

        case .thin:  return "Thin"

        case .light:  return "Light"

        case .regular:  return "Book"

        case .medium, .semibold:  return "Medium"

        case .bold:  return "Bold"

        case .heavy, .black:  return "Black"

        default: return "Book"
        }}()
        guard let font = UIFont(name: "Gotham-\(suffix)", size: fontSize) else {
            return UIFont.systemFont(ofSize: fontSize, weight: weight)
        }
        return font
    }

    class func gothamFont(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.gothamFont(ofSize: fontDescriptor.pointSize, weight: weight))
    }

    class func gothamFont(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular, maximumPointSize: CGFloat) -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.gothamFont(ofSize: fontDescriptor.pointSize, weight: weight), maximumPointSize: maximumPointSize)
    }

    class func systemFont(forTextStyle style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.systemFont(ofSize: fontDescriptor.pointSize, weight: weight))
    }
}
