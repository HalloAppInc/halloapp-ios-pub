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
        super.init(frame: .zero)

        let label = UILabel()
        label.textColor = .primaryWhiteBlack.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.text = Localizations.noConnection
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0

        let blurEffect = Self.makeBlurEffect(for: traitCollection)
        let blurredEffectView = UIVisualEffectView(effect: blurEffect)
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false
        blurredEffectView.layer.cornerRadius = 12
        blurredEffectView.layer.masksToBounds = true

        addSubview(blurredEffectView)
        addSubview(label)

        layoutMargins = UIEdgeInsets(top: 8, left: 36, bottom: 8, right: 36)
        heightAnchor.constraint(equalToConstant: 55).isActive = true

        blurredEffectView.constrain(to: self)
        label.constrainMargins(to: self)

        self.blurredEffectView = blurredEffectView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        blurredEffectView?.effect = Self.makeBlurEffect(for: traitCollection)
    }

    private var blurredEffectView: UIVisualEffectView?

    private static func makeBlurEffect(for traitCollection: UITraitCollection) -> UIBlurEffect {
        let style: UIBlurEffect.Style = traitCollection.userInterfaceStyle == .dark ? .light : .dark
        return UIBlurEffect(style: style)
    }
}

extension Localizations {
    static var noConnection: String {
        return NSLocalizedString("banner.no.connection", value: "No Connection", comment: "Text to show on banner when no connection is available")
    }
}
