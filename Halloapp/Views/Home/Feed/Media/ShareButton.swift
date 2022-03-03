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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("icon_share")
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(Circle())
                .accentColor(.lavaOrange)
        }
        .accessibility(label: Text(Localizations.buttonShare))
    }
}
