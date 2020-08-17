//
//  FloatingMenu.swift
//  HalloApp
//
//  Created by Garrett on 8/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import UIKit

final class FloatingMenuButton: UIView {
    init(
        button: UIButton,
        action: ((UIButton, FloatingMenu) -> Future<Void, Never>)?,
        transition: ((UIButton, FloatingMenu.State) -> Void)? = nil)
    {
        self.button = button
        self.action = action
        self.transition = transition
        super.init(frame: .zero)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.constrain(to: self)
        button.addTarget(self, action: #selector(Self.didTapButton), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Internal control view
    let button: UIButton

    /// Closure called when button tapped. Returns a future so we can hande async actions.
    let action: ((UIButton, FloatingMenu) -> Future<Void, Never>)?

    /// Closure called by menu when its state changes (e.g., so we can animate button color or icon change alongside menu)
    let transition: ((UIButton, FloatingMenu.State) -> Void)?

    weak var menu: FloatingMenu?

    @objc func didTapButton() {
        guard let action = action else { return }
        guard let menu = menu else {
            DDLogError("Floating menu button requires menu to function")
            return
        }
        _ = action(button, menu).sink() {}
    }

    /// Fades from one icon to the other when expanded
    static func fadingToggleButton(collapsedIconTemplate: UIImage?, expandedIconTemplate: UIImage) -> FloatingMenuButton {
        return FloatingMenuButton(
            button: makeUIButton(icon: collapsedIconTemplate, accessibilityLabel: "Menu"),
            action: { _, menu in menu.toggleExpanded() },
            transition: { button, state in
            switch state {
            case .collapsed:
                button.tintColor = .white
                button.backgroundColor = .lavaOrange
                button.setImage(collapsedIconTemplate, for: .normal)
            case .expanded:
                button.tintColor = .lavaOrange
                button.backgroundColor = .white
                button.setImage(expandedIconTemplate, for: .normal)
            }
        })
    }

    /// Rotates icon by specified number of degrees when expanded (e.g., 45 degrees from + to X, 180 degrees from up arrow to down arrow)
    static func rotatingToggleButton(collapsedIconTemplate: UIImage?, expandedRotation: CGFloat) -> FloatingMenuButton {
        return FloatingMenuButton(
            button: makeUIButton(icon: collapsedIconTemplate, accessibilityLabel: "Menu"),
            action: { _, menu in menu.toggleExpanded() },
            transition: { button, state in
                switch state {
                case .collapsed:
                    button.tintColor = .white
                    button.backgroundColor = .lavaOrange
                    button.transform = .init(rotationAngle: 0)
                case .expanded:
                    button.tintColor = .lavaOrange
                    button.backgroundColor = .white
                    button.transform = .init(rotationAngle: expandedRotation * (CGFloat.pi / 180))
                }
        })
    }

    /// Standard action button with no state transition and a synchronous action. Closes menu if expanded.
    static func standardActionButton(iconTemplate: UIImage?, accessibilityLabel: String, action: @escaping () -> Void) -> FloatingMenuButton {
        return FloatingMenuButton(
            button: makeUIButton(icon: iconTemplate, accessibilityLabel: accessibilityLabel),
            action: { _, menu in
                action()
                return menu.setState(.collapsed, animated: true) })
    }

    private static func makeUIButton(icon: UIImage?, accessibilityLabel: String) -> UIButton {
        if icon == nil {
            DDLogError("Missing image for floating button: \(accessibilityLabel)")
        }

        let diameter = FloatingMenu.ButtonDiameter
        let button = UIButton.systemButton(with: icon ?? UIImage(), target: nil, action: nil)
        button.accessibilityLabel = accessibilityLabel
        button.backgroundColor = .lavaOrange
        button.tintColor = .white
        button.layer.cornerRadius = diameter / 2
        button.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)),
            cornerRadius: diameter/2).cgPath
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        return button
    }
}

final class FloatingMenu: UIView {

    static var ButtonDiameter: CGFloat = 50
    static var ButtonSpacing: CGFloat = 15
    static var PermanentButtonExtraSpacing: CGFloat = 5
    static var ShadowOpacity: Float = 0.4

    init(permanentButton: FloatingMenuButton, expandedButtons: [FloatingMenuButton] = []) {
        self.permanentButton = permanentButton
        self.expandedButtons = expandedButtons
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let permanentButton: FloatingMenuButton
    let expandedButtons: [FloatingMenuButton]

    // NB: This is private(set) so we can update it in a custom animation block.
    private(set) var state = State.collapsed {
        didSet {
            orderedButtons.forEach { $0.transition?($0.button, state) }
            layoutSubviews()
        }
    }

    @discardableResult
    func toggleExpanded() -> Future<Void, Never> {
        return setState(isCollapsed ? .expanded : .collapsed, animated: true)
    }

    @discardableResult
    func setState(_ newState: State, animated: Bool) -> Future<Void, Never> {
        guard newState != state else {
            return Future<Void, Never>.guarantee(())
        }
        guard animated else {
            state = newState
            return Future<Void, Never>.guarantee(())
        }

        // Use full damping if expanded (i.e., don't bounce buttons when collapsing menu)
        let damping: CGFloat = isCollapsed ? 0.75 : 1
        let animationDuration: TimeInterval = 0.3
        
        return Future { promise in
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: 0,
                options: .allowUserInteraction,
                animations: { self.state = newState },
                completion: { _ in promise(.success(())) })
        }
    }

    // UIView

    override func layoutSubviews() {
        super.layoutSubviews()

        for (i, button) in orderedButtons.enumerated() {
            let castsShadow = button == permanentButton || !isCollapsed
            let needsSpacing = !isCollapsed && button != permanentButton
            button.layer.shadowOpacity = castsShadow ? Self.ShadowOpacity : 0
            button.center = permanentButton.center
            if needsSpacing {
                let deltaY = Self.PermanentButtonExtraSpacing + CGFloat(i) * (Self.ButtonDiameter + Self.ButtonSpacing)
                button.center.y -= deltaY
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitTargets: [UIView] = isCollapsed ? [permanentButton] : orderedButtons
        return hitTargets.reduce(nil) { hitView, target in
            let convertedPoint = self.convert(point, to: target)
            return hitView ?? target.hitTest(convertedPoint, with: event)
        }
    }

    enum State {
        case collapsed
        case expanded
    }

    // MARK: Private

    private var isCollapsed: Bool { self.state == .collapsed }

    private var orderedButtons: [FloatingMenuButton] {
        [permanentButton] + expandedButtons
    }

    private func setup() {

        orderedButtons.reversed().forEach { button in
            addSubview(button)
            button.menu = self
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowRadius = 5
            button.layer.shadowOpacity = Self.ShadowOpacity
            button.layer.shadowOffset = .zero
        }

        permanentButton.constrainMargin(anchor: .bottom, to: self, constant: -16)
        permanentButton.constrainMargin(anchor: .trailing, to: self, constant: -16)
        setNeedsLayout()
    }
}

private extension Future {
    // Converts a known value into a Future so you can use it in an async API.
    // Not sure if something like this already exists in Combine?
    static func guarantee(_ value: Output) -> Future<Output, Never> {
        return Future<Output, Never> { promise in
            promise(.success(value))
        }
    }
}
