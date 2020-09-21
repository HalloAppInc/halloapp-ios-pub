//
//  FontExtension.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 2/25/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

extension Font {

    fileprivate static func uiFontWeight(for fontWeight: Font.Weight) -> UIFont.Weight {
        switch fontWeight {
        case  .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    fileprivate static func uiFontTextStyle(for textStyle: Font.TextStyle) -> UIFont.TextStyle {
        switch textStyle {
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        case .headline: return .headline
        case .largeTitle: return .largeTitle
        case .subheadline: return .subheadline
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        @unknown default:
            fatalError("Unknown text style \(textStyle)")
        }
    }

    static func gotham(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        return Font(UIFont.gothamFont(forTextStyle: Font.uiFontTextStyle(for: style), weight: Font.uiFontWeight(for: weight)))
    }

    static func gotham(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font(UIFont.gothamFont(ofSize: size, weight: Font.uiFontWeight(for: weight)))
    }

}
