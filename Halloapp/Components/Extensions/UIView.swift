//
//  UIView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIView {

    func alignedCenter(from center: CGPoint, flippedForRTL flipForRTL: Bool = false) -> CGPoint {
        let screenScale = UIScreen.main.scale
        let size = self.bounds.size
        let originX = center.x - size.width * 0.5
        var alignedCenter = center
        alignedCenter.x += (originX * screenScale).rounded()/screenScale - originX
        let originY = center.y - size.height * 0.5
        alignedCenter.y += (originY * screenScale).rounded()/screenScale - originY
        if flipForRTL && self.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            if let superView = self.superview {
                alignedCenter.x = superView.bounds.size.width - center.x
            }
        }
        return alignedCenter
    }
    
    // MARK: Constraint helpers
    
    enum ConstraintAnchor {
        case top
        case bottom
        case leading
        case trailing
    }
    
    enum ConstraintDimension {
        case height
        case width
    }
    
    @discardableResult
    func constrain(anchor: ConstraintAnchor, to otherView: UIView, constant: CGFloat = 0) -> NSLayoutConstraint {
        let constraint: NSLayoutConstraint
        switch anchor {
        case .top:
            constraint = topAnchor.constraint(equalTo: otherView.topAnchor, constant: constant)
        case .bottom:
            constraint = bottomAnchor.constraint(equalTo: otherView.bottomAnchor, constant: constant)
        case .leading:
            constraint = leadingAnchor.constraint(equalTo: otherView.leadingAnchor, constant: constant)
        case .trailing:
            constraint = trailingAnchor.constraint(equalTo: otherView.trailingAnchor, constant: constant)
        }
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func constrainMargin(anchor: ConstraintAnchor, to otherView: UIView, constant: CGFloat = 0) -> NSLayoutConstraint {
        let constraint: NSLayoutConstraint
        switch anchor {
        case .top:
            constraint = topAnchor.constraint(equalTo: otherView.layoutMarginsGuide.topAnchor, constant: constant)
        case .bottom:
            constraint = bottomAnchor.constraint(equalTo: otherView.layoutMarginsGuide.bottomAnchor, constant: constant)
        case .leading:
            constraint = leadingAnchor.constraint(equalTo: otherView.layoutMarginsGuide.leadingAnchor, constant: constant)
        case .trailing:
            constraint = trailingAnchor.constraint(equalTo: otherView.layoutMarginsGuide.trailingAnchor, constant: constant)
        }
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    func constrain(_ anchors: [ConstraintAnchor] = [.top, .bottom, .leading, .trailing], to otherView: UIView) -> [NSLayoutConstraint] {
        return anchors.map { constrain(anchor: $0, to: otherView) }
    }

    @discardableResult
    func constrainMargins(_ anchors: [ConstraintAnchor] = [.top, .bottom, .leading, .trailing], to otherView: UIView) -> [NSLayoutConstraint] {
        return anchors.map { constrainMargin(anchor: $0, to: otherView) }
    }
}
