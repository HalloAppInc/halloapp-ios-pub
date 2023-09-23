//
//  ScaledFont.swift
//  HalloApp
//
//  Created by Tanveer on 9/15/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI

struct ScaledFont: ViewModifier {

    @Environment(\.sizeCategory) private var sizeCategory

    let size: CGFloat
    let weight: Font.Weight
    let scaler: UIFont.TextStyle

    func body(content: Content) -> some View {
        let size = UIFontMetrics(forTextStyle: scaler).scaledValue(for: size)

        return content.font(.system(size: size, weight: weight))
    }
}

extension View {
    
    func scaledFont(ofSize: CGFloat, weight: Font.Weight = .regular, scaler: UIFont.TextStyle = .body) -> some View {
        self.modifier(ScaledFont(size: ofSize, weight: weight, scaler: scaler))
    }
}
