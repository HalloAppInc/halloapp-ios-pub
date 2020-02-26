//
//  FontExtension.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 2/25/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

extension Font {
    static let gothamBody = Font.custom("GothamBook", size: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).pointSize)
    
    public static func gotham(_ size: CGFloat) -> Font {
        return Font.custom("GothamBook", size: size)
    }

    public static func gothamMedium(_ size: CGFloat) -> Font {
        return Font.custom("GothamMedium", size: size)
    }

}
