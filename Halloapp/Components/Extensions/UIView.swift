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

    // MARK: RTL

    func getDirectionalUIEdgeInsets(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> UIEdgeInsets {
        // NOTE: this wil be deprecated when Apple use `NSDirectioanlEdgeInsets` (https://developer.apple.com/documentation/uikit/nsdirectionaledgeinsets) for your insets property instead of `UIEdgeInsets`
        if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight {
            return UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
        } else {
            return UIEdgeInsets(top: top, left: trailing, bottom: bottom, right: leading)
        }
    }

    // MARK: Hierarchy

    func traverseViewHierarchyDepthFirst(visit: (UIView) -> Void) {
        for subview in subviews {
            subview.traverseViewHierarchyDepthFirst(visit: visit)
        }
        visit(self)
    }
    
    // MARK: Constraint helpers
    
    enum ConstraintAnchor {
        case top
        case bottom
        case leading
        case trailing
        case centerX
        case centerY
    }
    
    enum ConstraintDimension {
        case height
        case width
    }

    @discardableResult
    func constrain(dimension: ConstraintDimension, to otherView: UIView, constant: CGFloat = 0, priority: UILayoutPriority = .required) -> NSLayoutConstraint {
        let constraint: NSLayoutConstraint
        switch dimension {
        case .height:
            constraint = heightAnchor.constraint(equalTo: otherView.heightAnchor, constant: constant)
        case .width:
            constraint = widthAnchor.constraint(equalTo: otherView.widthAnchor, constant: constant)
        }
        constraint.priority = priority
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func constrain(anchor: ConstraintAnchor, to otherView: UIView, constant: CGFloat = 0, priority: UILayoutPriority = .required) -> NSLayoutConstraint {
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
        case .centerX:
            constraint = centerXAnchor.constraint(equalTo: otherView.centerXAnchor, constant: constant)
        case .centerY:
            constraint = centerYAnchor.constraint(equalTo: otherView.centerYAnchor, constant: constant)
        }
        constraint.priority = priority
        constraint.isActive = true
        return constraint
    }

    @discardableResult
    func constrain(anchor: ConstraintAnchor, to layoutGuide: UILayoutGuide, constant: CGFloat = 0, priority: UILayoutPriority = .required) -> NSLayoutConstraint {
        let constraint: NSLayoutConstraint
        switch anchor {
        case .top:
            constraint = topAnchor.constraint(equalTo: layoutGuide.topAnchor, constant: constant)
        case .bottom:
            constraint = bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor, constant: constant)
        case .leading:
            constraint = leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor, constant: constant)
        case .trailing:
            constraint = trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor, constant: constant)
        case .centerX:
            constraint = centerXAnchor.constraint(equalTo: layoutGuide.centerXAnchor, constant: constant)
        case .centerY:
            constraint = centerYAnchor.constraint(equalTo: layoutGuide.centerYAnchor, constant: constant)
        }
        constraint.priority = priority
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    func constrain(_ anchors: [ConstraintAnchor] = [.top, .bottom, .leading, .trailing], to otherView: UIView, priority: UILayoutPriority = .required) -> [NSLayoutConstraint] {
        return anchors.map { constrain(anchor: $0, to: otherView, priority: priority) }
    }

    @discardableResult
    func constrainMargins(_ anchors: [ConstraintAnchor] = [.top, .bottom, .leading, .trailing], to otherView: UIView, priority: UILayoutPriority = .required) -> [NSLayoutConstraint] {
        return anchors.map { constrainMargin(anchor: $0, to: otherView, priority: priority) }
    }

    @discardableResult
    func constrain(_ anchors: [ConstraintAnchor] = [.top, .bottom, .leading, .trailing], to layoutGuide: UILayoutGuide, priority: UILayoutPriority = .required) -> [NSLayoutConstraint] {
        return anchors.map { constrain(anchor: $0, to: layoutGuide, priority: priority) }
    }

    @discardableResult
    func constrainMargin(anchor: ConstraintAnchor, to otherView: UIView, constant: CGFloat = 0, priority: UILayoutPriority = .required) -> NSLayoutConstraint {
        return constrain(anchor: anchor, to: otherView.layoutMarginsGuide, constant: constant, priority: priority)
    }

}
