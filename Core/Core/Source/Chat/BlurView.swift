//
//  BlurView.swift
//  HalloApp
//
//  Created by Tony Jiang on 3/18/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Foundation
import UIKit

public class BlurView: UIVisualEffectView {

    private var animator = UIViewPropertyAnimator(duration: 1, curve: .easeInOut, animations: nil)

    private let visualEffect: UIVisualEffect
    private let customIntensity: CGFloat

    public init(effect: UIVisualEffect, intensity: CGFloat) {
        visualEffect = effect
        customIntensity = intensity
        super.init(effect: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        animateToIntensity()
    }

    private func animateToIntensity() {
        self.effect = nil
        self.animator.stopAnimation(true)
        self.animator.addAnimations { [weak self] in
            guard let self = self else { return }
            self.effect = self.visualEffect
        }
        self.animator.fractionComplete = self.customIntensity
        DispatchQueue.main.async {
            self.animator.stopAnimation(true)
        }
    }
}
