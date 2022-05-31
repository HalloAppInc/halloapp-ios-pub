//
//  UIFont.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIFont {

    class func gothamFont(ofFixedSize fontSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
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

    class func quicksandFont(ofFixedSize fontSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let suffix: String = {
        switch weight {
        case  .ultraLight, .thin, .light:
            return "Light"
        case .regular:
            return "Regular"
        case .medium:
            return "Medium"
        case .semibold:
            return "SemiBold"
        case .heavy, .black, .bold:
            return "Bold"
        default:
            return "Regular"
        }}()
        guard let font = UIFont(name: "Quicksand-\(suffix)", size: fontSize) else {
            return UIFont.systemFont(ofSize: fontSize, weight: weight)
        }
        return font
    }

    class func gothamFont(forTextStyle style: UIFont.TextStyle, pointSizeChange: CGFloat = 0, weight: UIFont.Weight = .regular, maximumPointSize: CGFloat? = nil) -> UIFont {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traitCollection)
        let baseFont = UIFont.gothamFont(ofFixedSize: fontDescriptor.pointSize + pointSizeChange, weight: weight)
        if let maximumPointSize = maximumPointSize {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont, maximumPointSize: maximumPointSize)
        } else {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont)
        }
    }

    class func scaledGothamFont(ofSize fontSize: CGFloat, weight: UIFont.Weight = .regular, scalingTextStyle: UIFont.TextStyle = .body) -> UIFont {
        return UIFontMetrics(forTextStyle: scalingTextStyle).scaledFont(for: .gothamFont(ofFixedSize: fontSize,weight: weight))
    }

    class func handwritingFont(ofFixedSize fontSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        // bold is the only available weight
        let name = "BradleyHandITCTT-Bold"
        let font = UIFont(name: name, size: fontSize)

        return font ?? .systemFont(ofSize: fontSize, weight: weight)
    }

    class func handwritingFont(forTextStyle style: UIFont.TextStyle, pointSizeChange: CGFloat = 0, weight: UIFont.Weight = .regular, maximumPointSize: CGFloat? = nil) -> UIFont {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traitCollection)
        let baseFont = UIFont.handwritingFont(ofFixedSize: fontDescriptor.pointSize + pointSizeChange, weight: weight)
        if let maximumPointSize = maximumPointSize {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont, maximumPointSize: maximumPointSize)
        } else {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont)
        }
    }

    class func systemFont(forTextStyle style: UIFont.TextStyle, pointSizeChange: CGFloat = 0, weight: UIFont.Weight = .regular, maximumPointSize: CGFloat? = nil) -> UIFont {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traitCollection)
        let baseFont = UIFont.systemFont(ofSize: fontDescriptor.pointSize + pointSizeChange, weight: weight)
        if let maximumPointSize = maximumPointSize {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont, maximumPointSize: maximumPointSize)
        } else {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont)
        }
    }

    class func scaledSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight = .regular, scalingTextStyle: UIFont.TextStyle = .body) -> UIFont {
        return UIFontMetrics(forTextStyle: scalingTextStyle).scaledFont(for: UIFont.systemFont(ofSize: fontSize, weight: weight))
    }

    var withItalicsIfAvailable: UIFont {
        guard let italicDescriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return self
        }
        return UIFont(descriptor: italicDescriptor, size: pointSize)
    }
}
