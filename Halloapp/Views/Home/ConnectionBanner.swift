//
//  ConnectionBanner.swift
//  HalloApp
//
//  Created by Garrett on 2/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

final class ConnectionBanner: UIView {
    init() {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.text = Localizations.noConnection
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)

        let blurEffect = UIBlurEffect(style: .dark)
        let blurredEffectView = UIVisualEffectView(effect: blurEffect)
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        addSubview(blurredEffectView)
        addSubview(label)

        blurredEffectView.constrain(to: self)
        label.constrainMargins(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension Localizations {
    static var noConnection: String {
        return NSLocalizedString("banner.no.connection", value: "No internet connection", comment: "Text to show on banner when no connection is available")
    }
}
