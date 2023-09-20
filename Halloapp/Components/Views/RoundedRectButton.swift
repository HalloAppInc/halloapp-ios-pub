//
//  RoundedRectButton.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

// Prefer to set configuration = .filledCapsule() over this subclass unless you need to maintain these custom highlighted / disabled states
class RoundedRectButton: UIButton {

    private struct Constants {
        static let defaultBackgroundColor: UIColor = .lavaOrange
    }

    var backgroundTintColor: UIColor {
        get {
            configuration?.baseBackgroundColor ?? Constants.defaultBackgroundColor
        }
        set {
            configuration?.baseBackgroundColor = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        configuration = .filledCapsule(backgroundColor: Constants.defaultBackgroundColor)
        configurationUpdateHandler = { button in
            guard let button = button as? RoundedRectButton, var configuration = button.configuration else {
                return
            }

            if let backgroundColor = configuration.baseBackgroundColor {
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                if backgroundColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
                    if !button.isEnabled {
                        saturation = 0.10
                        brightness -= 0.24
                    } else if button.isHighlighted {
                        brightness -= 0.2
                    }
                    configuration.background.backgroundColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
                }
            }

            button.configuration = configuration
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return super.point(inside: point, with: event) || bounds.insetBy(dx: min(0, bounds.width - 44) / 2,
                                                                         dy: min(0, bounds.width - 44) / 2).contains(point)
    }
}
