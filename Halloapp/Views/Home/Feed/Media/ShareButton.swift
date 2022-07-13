//
//  ShareButton.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 12/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import SwiftUI

struct ShareButton: View {
    let showTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if showTitle {
                    Text(Localizations.buttonShare)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.leading, 12)
                }
                Image("icon_share")
                    .renderingMode(.template)
            }
            .foregroundColor(.white)
            .padding(.horizontal, showTitle ? 6 : 0)
            .padding(.vertical, showTitle ? -4 : 0)
            .background(Capsule())
            .accentColor(.lavaOrange)
        }
        .accessibility(label: Text(Localizations.buttonShare))
    }
}
