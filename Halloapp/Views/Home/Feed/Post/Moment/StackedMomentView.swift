//
//  StackedMomentView.swift
//  HalloApp
//
//  Created by Tanveer on 7/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

enum MomentStackItem: Equatable, Hashable {
    case moment(FeedPost)
    case prompt

    var moment: FeedPost? {
        switch self {
        case .moment(let moment):
            return moment
        case .prompt:
            return nil
        }
    }
}

class StackedMomentView: UIView {

    typealias Item = MomentStackItem
    private enum AnimationDirection { case left, right }

    private var items: [Item] = []
    private var iterator: ItemIterator?

    private lazy var unusedViews: [MomentView] = {
        var views = [MomentView]()
        for i in 1...5 {
            let momentView = MomentView()
            momentView.translatesAutoresizingMaskIntoConstraints = false

            momentView.delegate = self
            views.append(momentView)
        }

        return views
    }()

    private var visibleViews: [MomentView] = []
    private var topView: MomentView? {
        return visibleViews.first
    }

    private var gestureStartPoint: CGPoint?
    private var topMomentRotationAngle: CGFloat?

    var actionCallback: ((MomentView, MomentView.Action) -> Void)?

    /// Appears when the user has never before swiped when there are > 1 items in the stack.
    private var ftuxLabel: UILabel?

    override init(frame: CGRect) {
        super.init(frame: frame)

        var constraints = [NSLayoutConstraint]()
        for view in unusedViews {
            addSubview(view)
            view.isHidden = true

            constraints.append(contentsOf: [
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("StackedMomentView coder init not implemented...")
    }

    func configure(with items: [Item]) {
        reset()

        self.items = items
        iterator = ItemIterator(items)

        for _ in (items.count == 1 ? 1...1 : 1...3) {
            if let item = iterator?.next() {
                insertItemAtBottom(item)
            }
        }

        if items.count > 1, !Self.hasSwipedStack {
            installFTUX()
        }
    }

    private func reset() {
        unusedViews.append(contentsOf: visibleViews)
        visibleViews = []
        unusedViews.forEach { $0.isHidden = true }
    }

    private func insertItemAtBottom(_ item: Item) {
        guard let view = dequeueMomentView() else {
            return
        }

        switch item {
        case .moment(let post):
            view.configure(with: post)
        case .prompt:
            view.configure(with: nil)
        }

        let aboveViewAngle = visibleViews.last?.transform.rotationAngle ?? 1
        view.transform = CGAffineTransform(rotationAngle: aboveViewAngle == .zero ? -0.05 : .zero)

        sendSubviewToBack(view)
        view.isHidden = false
        visibleViews.append(view)
    }

    private func dequeueMomentView() -> MomentView? {
        return unusedViews.popLast()
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let momentView = topView else {
            return
        }

        switch gesture.state {
        case .began:
            gestureStartPoint = gesture.location(in: self)
            topMomentRotationAngle = momentView.transform.rotationAngle
            fallthrough

        case .changed:
            let translation = gesture.translation(in: gesture.view).x
            let angle = rotationAngle(translation)
            momentView.transform = CGAffineTransform(translationX: translation, y: 0)
                .concatenating(CGAffineTransform(rotationAngle: (topMomentRotationAngle ?? .zero) + angle))

        case .ended, .failed, .cancelled:
            completeStackAnimation(gesture)
            gestureStartPoint = nil
            topMomentRotationAngle = nil

        default:
            break
        }
    }

    private func rotationAngle(_ xTranslation: CGFloat) -> CGFloat {
        guard let startPoint = gestureStartPoint else {
            return .zero
        }

        let multiplier: CGFloat = startPoint.y < bounds.midY ? 1 : -1
        let rotation = min(xTranslation / UIScreen.main.bounds.width, 1) * (.pi / 10)

        return rotation * multiplier
    }

    private func completeStackAnimation(_ gesture: UIPanGestureRecognizer) {
        guard let topMoment = topView else { return }
        let initialRotation = topMomentRotationAngle ?? .zero
        let direction = animationDirection(gesture)
        var distance: CGFloat = .zero

        if let direction = direction {
            distance = animationDistance(for: topMoment, direction: direction)
            didSwipe()
        }

        let timing = UISpringTimingParameters(gesture: gesture, distance: distance)
        let firstAnimatorDuration = 0.3
        let animator = UIViewPropertyAnimator(duration: firstAnimatorDuration, timingParameters: timing)

        animator.addAnimations {
            switch direction {
            case .left:
                topMoment.transform = topMoment.transform.translatedBy(x: -distance, y: 0)
            case .right:
                topMoment.transform = topMoment.transform.translatedBy(x: distance, y: 0)
            default:
                topMoment.transform = .identity.rotated(by: initialRotation)
            }
        }

        guard direction != nil else {
            return animator.startAnimation()
        }

        let resetAnimator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) {
            topMoment.alpha = 0
            topMoment.transform = .identity.rotated(by: initialRotation)
        }

        resetAnimator.addCompletion { [weak self] _ in
            topMoment.isHidden = true
            topMoment.alpha = 1
            self?.unusedViews.append(topMoment)
        }

        animator.startAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + firstAnimatorDuration * 0.55) { [weak self] in
            // to avoid the slight hitch/pause that is caused by starting the reset animator in the first animator's
            // completion block, we start the reset animator just before the initial one finishes.
            // (property animators support this gracefully)
            self?.sendSubviewToBack(topMoment)
            resetAnimator.startAnimation()
        }
    }

    private func animationDirection(_ gesture: UIPanGestureRecognizer) -> AnimationDirection? {
        guard items.count > 1 else {
            return nil
        }

        let velocity = gesture.velocity(in: gesture.view).x
        let translation = gesture.translation(in: gesture.view).x

        if velocity >= 400 {
            return .right
        } else if velocity <= -400 {
            return .left
        }

        if translation >= 50 {
            return .right
        } else if translation <= -50 {
            return .left
        }

        return nil
    }

    private func animationDistance(for momentView: MomentView, direction: AnimationDirection) -> CGFloat {
        let additionalTranslation: CGFloat = 30

        switch direction {
        case .left:
            return (momentView.frame.maxX - bounds.minX) + additionalTranslation
        case .right:
            return (bounds.maxX - momentView.frame.minX) + additionalTranslation
        }
    }

    private func didSwipe() {
        let previousTopMoment = visibleViews.remove(at: 0)
        guard let item = iterator?.next() else {
            return
        }

        insertItemAtBottom(item)
        removeFTUXIfNecessary(previousTopMoment)
    }

    /// Arranges the stack so that the moment with `postID` is at the top.
    @discardableResult
    func scroll(to postID: FeedPostID) -> Bool {
        if topView?.feedPost?.id == postID {
            return true
        }

        guard let target = items.firstIndex(where: { $0.moment?.id == postID }) else {
            return false
        }

        // rotate the array so that the target item as at the start
        var items = items
        let startIndex = items.startIndex
        let endIndex = items.endIndex
        let index = items.index(startIndex, offsetBy: target, limitedBy: endIndex) ?? endIndex
        let slice = items[..<index]

        items.removeSubrange(..<index)
        items.insert(contentsOf: slice, at: items.endIndex)

        configure(with: items)
        return true
    }
}

// MARK: - FTUX methods

extension StackedMomentView {

    @UserDefault(key: "shown.moment.stack.indicator", defaultValue: false)
    static private var hasSwipedStack: Bool

    private func installFTUX() {
        guard
            let topMoment = topView,
            let momentFooterView = topMoment.footerLabel.superview,
            let swipeImage = UIImage(systemName: "hand.draw")
        else {
            return
        }

        if let ftuxLabel = ftuxLabel, let momentView = ftuxLabel.superview as? MomentView {
            // it's possible that the FTUX was attached to a view that is now somewhere else in the stack
            ftuxLabel.removeFromSuperview()
            momentView.footerLabel.alpha = 1
        }

        topMoment.footerLabel.alpha = 0
        let string = NSMutableAttributedString.string(Localizations.swipeForMore,
                                                with: swipeImage,
                                             spacing: 2,
                                     imageAttributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.lavaOrange],
                                      textAttributes: [.font: UIFont.gothamFont(ofFixedSize: 16, weight: .medium), .foregroundColor: UIColor.lavaOrange])

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = string
        label.textAlignment = .center

        topMoment.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: momentFooterView.topAnchor),
            label.bottomAnchor.constraint(equalTo: momentFooterView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: topMoment.leadingAnchor, constant: MomentView.Layout.mediaPadding),
            label.trailingAnchor.constraint(equalTo: topMoment.trailingAnchor, constant: -MomentView.Layout.mediaPadding),
        ])

        ftuxLabel = label
    }

    private func removeFTUXIfNecessary(_ momentView: MomentView) {
        guard let ftuxLabel = ftuxLabel else {
            return
        }

        momentView.footerLabel.alpha = 1
        ftuxLabel.removeFromSuperview()
        self.ftuxLabel = nil

        Self.hasSwipedStack = true
    }
}

// MARK: - MomentViewDelegate methods

extension StackedMomentView: MomentViewDelegate {

    func momentView(_ momentView: MomentView, didSelect action: MomentView.Action) {
        actionCallback?(momentView, action)
    }
}

// MARK: - UIGestureRecognizerDelegate implementation

extension StackedMomentView: UIGestureRecognizerDelegate {

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return unusedViews.count > 0 && items.count > 1
    }
}

// MARK: - ItemIterator implementation

fileprivate struct ItemIterator: IteratorProtocol {

    private let items: [MomentStackItem]
    private var index: Int

    init(_ items: [MomentStackItem]) {
        self.items = items
        self.index = items.startIndex
    }

    public mutating func next() -> MomentStackItem? {
        guard !items.isEmpty else {
            return nil
        }

        let item = items[index]
        let next = items.index(after: index)
        index = next == items.endIndex ? items.startIndex : next

        return item
    }
}

// MARK: - CGAffineTransform extension

extension CGAffineTransform {
    /// The transform's current rotation.
    var rotationAngle: CGFloat {
        atan2(b, a)
    }
}

// MARK: - UISpringTimingParameters extension

fileprivate extension UISpringTimingParameters {

    convenience init(gesture: UIPanGestureRecognizer, distance: CGFloat, damping: CGFloat = 1) {
        var velocity = CGVector.zero
        let distance = distance

        if distance != 0 {
            velocity.dx = gesture.velocity(in: gesture.view).x / distance
        }

        self.init(dampingRatio: damping, initialVelocity: velocity)
    }
}

// MARK: - localization

extension Localizations {

    static var swipeForMore: String {
        NSLocalizedString("moments.swipe.for.more",
                   value: "swipe for more",
                 comment: "Text shown on the moments stack to indicate that the stack is interactive. Only shown the first time.")
    }
}
