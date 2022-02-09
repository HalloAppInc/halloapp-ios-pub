//
//  FloatingMenu.swift
//  HalloApp
//
//  Created by Garrett on 8/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import UIKit

final class FloatingMenuButton: UIView {
    init(
        button: UIControl,
        action: ((FloatingMenu) -> Future<Void, Never>)?,
        transition: ((FloatingMenu.ExpansionState, FloatingMenu.AccessoryState) -> Void)? = nil)
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
    let button: UIControl

    /// Closure called when button tapped. Returns a future so we can hande async actions.
    let action: ((FloatingMenu) -> Future<Void, Never>)?

    /// Closure called by menu when its state changes (e.g., so we can animate button color or icon change alongside menu)
    let transition: ((FloatingMenu.ExpansionState, FloatingMenu.AccessoryState) -> Void)?

    weak var menu: FloatingMenu?

    @objc func didTapButton() {
        guard let action = action else { return }
        guard let menu = menu else {
            DDLogError("Floating menu button requires menu to function")
            return
        }
        _ = action(menu).sink() {}
    }

    /// Rotates icon by specified number of degrees when expanded (e.g., 45 degrees from + to X, 180 degrees from up arrow to down arrow)
    static func rotatingToggleButton(collapsedIconTemplate: UIImage?, accessoryView: UIView, expandedRotation: CGFloat) -> FloatingMenuButton {
        let button = AccessorizedFloatingButton(icon: collapsedIconTemplate, accessoryView: accessoryView)
        return FloatingMenuButton(
            button: button,
            action: { menu in menu.toggleExpanded() },
            transition: { expansionState, accessoryState in
                switch expansionState {
                case .collapsed:
                    button.pillView.backgroundColor = .lavaOrange
                    button.imageView.tintColor = .white
                    button.imageView.transform = .init(rotationAngle: 0)
                    let shouldHideAccessory = accessoryState == .plain
                    if button.accessoryView.isHidden != shouldHideAccessory {
                        // NB: Encountered a weird issue in iOS 15.2: Setting isHidden to
                        //     true when it was already true made the setting permanent;
                        //     later attempts to set isHidden to false had no effect. Therefore
                        //     we check and only set isHidden if it needs to change.
                        button.accessoryView.isHidden = shouldHideAccessory
                    }
                case .expanded:
                    button.pillView.backgroundColor = .white
                    button.imageView.tintColor = .lavaOrange
                    button.imageView.transform = .init(rotationAngle: expandedRotation * (CGFloat.pi / 180))
                    button.accessoryView.isHidden = true
                }
        })
    }

    /// Standard action button with no state transition and a synchronous action. Closes menu if expanded.
    static func standardActionButton(iconTemplate: UIImage?, accessibilityLabel: String, action: @escaping () -> Void) -> FloatingMenuButton {
        let button = LabeledFloatingButton(icon: iconTemplate, text: accessibilityLabel)
        return FloatingMenuButton(
            button: button,
            action: { menu in
                action()
                return menu.setExpansionState(.collapsed, animated: true) },
            transition: { (state, _) in
                switch state {
                case .collapsed:
                    button.label.alpha = 0
                    button.circleView.layer.shadowOpacity = 0
                case .expanded:
                    button.label.alpha = 1
                    button.circleView.layer.shadowOpacity = FloatingMenu.ShadowOpacity
                }
            })
    }
}

final class FloatingMenu: UIView {

    static var ButtonDiameter: CGFloat = 55
    static var ButtonSpacing: CGFloat = 15
    static var PermanentButtonExtraSpacing: CGFloat = 5
    static var HeaderSpacing: CGFloat = 20
    static var ShadowOpacity: Float = 0.2
    static var ExpandedBackgroundColor: UIColor = .feedBackground.withAlphaComponent(0.9)

    init(permanentButton: FloatingMenuButton, expandedButtons: [FloatingMenuButton] = [], expandedHeader: String? = nil) {
        self.permanentButton = permanentButton
        self.expandedButtons = expandedButtons
        if let expandedHeader = expandedHeader {
            self.expandedHeader = Self.makeLabel(text: expandedHeader, textStyle: .body)
        }
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let permanentButton: FloatingMenuButton
    let expandedButtons: [FloatingMenuButton]

    // NB: These are private(set) so we can update them in a custom animation block.
    private(set) var expansionState = ExpansionState.collapsed
    private(set) var accessoryState = AccessoryState.accessorized

    var suggestedContentInsetHeight: CGFloat {
        layoutIfNeeded()
        let margin = bounds.maxY - permanentButton.frame.maxY
        return permanentButton.frame.height + (2 * margin)
    }

    @discardableResult
    func toggleExpanded() -> Future<Void, Never> {
        return setExpansionState(isCollapsed ? .expanded : .collapsed, animated: true)
    }

    @discardableResult
    func setExpansionState(_ newState: ExpansionState, animated: Bool) -> Future<Void, Never> {
        guard newState != expansionState else {
            return Future<Void, Never>.guarantee(())
        }
        expansionState = newState
        if animated {
            return animateLayout()
        } else {
            layoutSubviews()
            return Future<Void, Never>.guarantee(())
        }
    }

    @discardableResult
    func setAccessoryState(_ newState: AccessoryState, animated: Bool) -> Future<Void, Never> {
        guard newState != accessoryState else {
            return Future<Void, Never>.guarantee(())
        }
        accessoryState = newState
        if animated {
            return animateLayout()
        } else {
            layoutSubviews()
            return Future<Void, Never>.guarantee(())
        }
    }

    @discardableResult
    private func animateLayout() -> Future<Void, Never> {

        // Use full damping (i.e., don't bounce) when collapsing
        let damping: CGFloat = isCollapsed ? 1 : 0.75
        let animationDuration: TimeInterval = 0.3
        
        return Future { promise in
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: 0,
                options: .allowUserInteraction,
                animations: { self.layoutSubviews() },
                completion: { _ in promise(.success(())) })
        }
    }

    // UIView

    override func layoutSubviews() {
        super.layoutSubviews()

        orderedButtons.forEach { $0.transition?(expansionState, accessoryState) }
        backgroundColor = isCollapsed ? .clear : Self.ExpandedBackgroundColor

        for (i, button) in orderedButtons.enumerated() {
            let castsShadow = button == permanentButton
            let needsSpacing = !isCollapsed && button != permanentButton
            button.layer.shadowOpacity = castsShadow ? Self.ShadowOpacity : 0
            button.center = CGPoint(
                x: permanentButton.center.x - (button.bounds.width - permanentButton.bounds.width) / 2,
                y: permanentButton.center.y)
            if needsSpacing {
                let deltaY = Self.PermanentButtonExtraSpacing + CGFloat(i) * (Self.ButtonDiameter + Self.ButtonSpacing)
                button.center.y -= deltaY
            }
        }

        if let header = expandedHeader {
            let topButton = orderedButtons.last ?? permanentButton
            let headerCenterY = isCollapsed ? permanentButton.center.y : topButton.frame.minY - Self.HeaderSpacing - header.bounds.height/2
            header.center = CGPoint(
                x: permanentButton.center.x - (header.bounds.width - permanentButton.bounds.width) / 2,
                y: headerCenterY)
            header.alpha = isCollapsed ? 0 : 1
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled else {
            return nil
        }
        let hitTargets: [UIView] = isCollapsed ? [permanentButton] : orderedButtons
        let result: UIView? = hitTargets.reduce(nil) { hitView, target in
            let convertedPoint = self.convert(point, to: target)
            return hitView ?? target.hitTest(convertedPoint, with: event)
        }
        if result == nil, !isCollapsed {
            // Block interaction with view below
            return self
        }
        return result
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isCollapsed {
            setExpansionState(.collapsed, animated: true)
        }
    }

    enum ExpansionState {
        case collapsed
        case expanded
    }

    enum AccessoryState {
        case accessorized
        case plain
    }

    static func makeLabel(text: String, textStyle: UIFont.TextStyle = .footnote) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft ? .left : .right
        label.textColor = .label
        label.font = .gothamFont(forTextStyle: textStyle, weight: .medium)
        label.text = text
        return label
    }

    // MARK: Private

    private var isCollapsed: Bool { self.expansionState == .collapsed }

    private var orderedButtons: [FloatingMenuButton] {
        [permanentButton] + expandedButtons
    }

    private var expandedHeader: UIView?

    private func setup() {

        orderedButtons.reversed().forEach { button in
            addSubview(button)
            button.menu = self
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowRadius = 6
            button.layer.shadowOpacity = Self.ShadowOpacity
            button.layer.shadowOffset = CGSize(width: 0, height: 5)
        }
        if let header = expandedHeader {
            addSubview(header)
        }

        permanentButton.constrainMargin(anchor: .bottom, to: self, constant: -4)
        permanentButton.constrainMargin(anchor: .trailing, to: self, constant: -4)
        setNeedsLayout()
    }
}

extension Future {
    // Converts a known value into a Future so you can use it in an async API.
    // Not sure if something like this already exists in Combine?
    static func guarantee(_ value: Output) -> Future<Output, Never> {
        return Future<Output, Never> { promise in
            promise(.success(value))
        }
    }
}

final class AccessorizedFloatingButton: UIControl {
    init(icon: UIImage?, accessoryView: UIView) {
        self.accessoryView = accessoryView
        super.init(frame: .zero)

        imageView.image = icon
        imageView.heightAnchor.constraint(equalToConstant: icon?.size.height ?? 0).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: icon?.size.width ?? 0).isActive = true
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillView)
        pillView.constrain(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let accessoryView: UIView
    let imageView = UIImageView()

    lazy var pillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view.backgroundColor = .lavaOrange
        view.layer.cornerRadius = FloatingMenu.ButtonDiameter / 2
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 5)

        let stackView = UIStackView(arrangedSubviews: [accessoryView, imageView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 9
        view.addSubview(stackView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -FloatingMenu.ButtonDiameter/2).isActive = true
        imageView.constrain([.centerY], to: view)
        accessoryView.constrainMargins([.leading, .centerY], to: view)

        view.heightAnchor.constraint(equalToConstant: FloatingMenu.ButtonDiameter).isActive = true
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: FloatingMenu.ButtonDiameter).isActive = true
        return view
    }()
}

final class LabeledFloatingButton: UIControl {
    init(icon: UIImage?, text: String, isCollapsed: Bool = true) {
        self.label = FloatingMenu.makeLabel(text: text)

        super.init(frame: .zero)

        label.alpha = isCollapsed ? 0 : 1
        imageView.image = icon
        circleView.layer.shadowOpacity = isCollapsed ? 0 : FloatingMenu.ShadowOpacity

        addSubview(circleView)
        addSubview(label)

        label.constrain([.leading, .top, .bottom], to: self)
        circleView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 20).isActive = true
        circleView.constrain([.centerY, .trailing], to: self)
        heightAnchor.constraint(greaterThanOrEqualTo: circleView.heightAnchor).isActive = true

        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            imageView.alpha = isEnabled ? 1.0 : 0.42
        }
    }

    private let imageView = UIImageView()
    lazy var circleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .lavaOrange
        view.layer.cornerRadius = FloatingMenu.ButtonDiameter / 2
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 5)
        view.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: FloatingMenu.ButtonDiameter, height: FloatingMenu.ButtonDiameter)),
            cornerRadius: FloatingMenu.ButtonDiameter/2).cgPath
        view.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.constrain([.centerX, .centerY], to: view)

        view.heightAnchor.constraint(equalToConstant: FloatingMenu.ButtonDiameter).isActive = true
        view.widthAnchor.constraint(equalToConstant: FloatingMenu.ButtonDiameter).isActive = true
        return view
    }()

    let label: UILabel
}
