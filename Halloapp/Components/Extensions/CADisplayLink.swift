//
//  CADisplayLink.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 1/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import QuartzCore

extension CADisplayLink {

    private class WeakTargetHolder {
        weak var target: AnyObject?
        var selector: Selector

        init(target: AnyObject, selector sel: Selector) {
            self.target = target
            self.selector = sel
        }

        @objc func step(_ displaylink: CADisplayLink) {
            _ = target?.perform(selector, with: displaylink)
        }
    }

    convenience init(weakTarget: AnyObject, selector sel: Selector) {
        let holder = WeakTargetHolder(target: weakTarget, selector: sel)
        self.init(target: holder, selector: #selector(WeakTargetHolder.step(_:)))
    }
}
