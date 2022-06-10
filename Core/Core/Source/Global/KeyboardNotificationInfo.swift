//
//  KeyboardNotificationInfo.swift
//  Core
//
//  Created by Chris Leonavicius on 6/9/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import UIKit

public struct KeyboardNotificationInfo {

    public let beginFrame: CGRect
    public let endFrame: CGRect
    public let animationDuration: Double
    public let animationCurve: UIView.AnimationCurve
    public let isLocalUser: Bool

    public var animationOptions: UIView.AnimationOptions {
        switch animationCurve {
        case .easeInOut:
            return .curveEaseInOut
        case .easeIn:
            return .curveEaseIn
        case .easeOut:
            return .curveEaseOut
        case .linear:
            return .curveLinear
        @unknown default:
            return .curveLinear
        }
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo,
              let beginFrame = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let animationCurve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int).flatMap({ UIView.AnimationCurve(rawValue: $0) }),
              let isLocalUser = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool else {
            return nil
        }

        self.beginFrame = beginFrame
        self.endFrame = endFrame
        self.animationDuration = animationDuration
        self.animationCurve = animationCurve
        self.isLocalUser = isLocalUser
    }
}

extension UIView {

    public class func animate(withKeyboardNotificationInfo info: KeyboardNotificationInfo, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        Self.animate(withDuration: info.animationDuration, delay: 0.0, options: info.animationOptions, animations: animations, completion: completion)
    }
}
