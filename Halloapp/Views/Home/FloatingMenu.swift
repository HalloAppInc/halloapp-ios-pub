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
            action: { menu in menu.toggle() },
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
                menu.presenter?.dismiss(animated: true)
                action()
                return Future<Void, Never>.guarantee(()) },
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

// MARK: - FloatingMenuPresenter protocol

protocol FloatingMenuPresenter: UIViewController {
    var floatingMenu: FloatingMenu { get }
    func makeTriggerButton() -> FloatingMenuButton
    func toggledFloatingMenu(_ menu: FloatingMenu, to state: FloatingMenu.ExpansionState) -> Future<Void, Never>
}

// MARK: - FloatingMenuPresenter default implementation

extension FloatingMenuPresenter {
    func toggledFloatingMenu(_ menu: FloatingMenu, to state: FloatingMenu.ExpansionState) -> Future<Void, Never> {
        switch state {
        case .collapsed:
            guard presentedViewController === floatingMenu else { return Future<Void, Never>.guarantee(()) }
            return Future { [weak self] promise in
                self?.dismiss(animated: true) {
                    promise(.success(()))
                }
            }
        case .expanded:
            guard presentedViewController == nil else { return Future<Void, Never>.guarantee(()) }
            return Future { [weak self] promise in
                guard let self = self else {
                    return
                }
                
                self.present(self.floatingMenu, animated: true) {
                    promise(.success(()))
                }
            }
        }
    }
}

// MARK: - FloatingMenu implementation

final class FloatingMenu: UIViewController, UIViewControllerTransitioningDelegate {

    static var ButtonDiameter: CGFloat = 55
    static var ButtonSpacing: CGFloat = 15
    static var PermanentButtonExtraSpacing: CGFloat = 5
    static var HeaderSpacing: CGFloat = 20
    static var ShadowOpacity: Float = 0.2
    static var ExpandedBackgroundColor: UIColor = .feedBackground.withAlphaComponent(0.9)
    
    weak var presenter: FloatingMenuPresenter?

    init(presenter: FloatingMenuPresenter, expandedButtons: [FloatingMenuButton] = [], expandedHeader: String? = nil) {
        self.triggerButton = presenter.makeTriggerButton()
        self.anchorButton = presenter.makeTriggerButton()
        self.expandedButtons = expandedButtons
        self.presenter = presenter
        
        if let expandedHeader = expandedHeader {
            self.expandedHeader = Self.makeLabel(text: expandedHeader, textStyle: .body)
        }
        
        super.init(nibName: nil, bundle: nil)
        
        modalPresentationStyle = .custom
        transitioningDelegate = self
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Identical in appearance to `anchorButton`. This button lives on the presenting view controller.
    let triggerButton: FloatingMenuButton
    let anchorButton: FloatingMenuButton
    let expandedButtons: [FloatingMenuButton]

    // NB: These are private(set) so we can update them in a custom animation block.
    private(set) var expansionState = ExpansionState.collapsed
    private(set) var accessoryState = AccessoryState.accessorized

    var suggestedContentInsetHeight: CGFloat {
        view.layoutIfNeeded()
        let margin = view.bounds.maxY - anchorButton.frame.maxY
        return anchorButton.frame.height + (2 * margin)
    }

    @discardableResult
    func toggle() -> Future<Void, Never> {
        let nextState = isCollapsed ? ExpansionState.expanded : ExpansionState.collapsed
        return presenter?.toggledFloatingMenu(self, to: nextState) ?? Future<Void, Never>.guarantee(())
    }

    /// - note: `fileprivate` protection because we only want to call this method during view controller presentation.
    @discardableResult
    fileprivate func setExpansionState(_ newState: ExpansionState, animated: Bool) -> Future<Void, Never> {
        guard newState != expansionState else {
            return Future<Void, Never>.guarantee(())
        }
        expansionState = newState
        if animated {
            return animateLayout()
        } else {
            viewDidLayoutSubviews()
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
            viewDidLayoutSubviews()
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
                animations: { self.viewDidLayoutSubviews() },
                completion: { _ in promise(.success(())) })
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        allButtons.forEach { $0.transition?(expansionState, accessoryState) }
        view.backgroundColor = isCollapsed ? .clear : Self.ExpandedBackgroundColor
        
        for (i, button) in orderedButtons.enumerated() {
            let castsShadow = button == anchorButton
            let needsSpacing = !isCollapsed && button != anchorButton

            var buttonDifference = (button.bounds.width - anchorButton.bounds.width) / 2
            if case .rightToLeft = view.effectiveUserInterfaceLayoutDirection {
                buttonDifference = -buttonDifference
            }
            
            button.layer.shadowOpacity = castsShadow ? Self.ShadowOpacity : 0
            button.center = CGPoint(
                x: anchorButton.center.x - buttonDifference,
                y: anchorButton.center.y)
            if needsSpacing {
                let deltaY = Self.PermanentButtonExtraSpacing + CGFloat(i) * (Self.ButtonDiameter + Self.ButtonSpacing)
                button.center.y -= deltaY
            }
        }

        if let header = expandedHeader {
            let topButton = orderedButtons.last ?? anchorButton
            let headerCenterY = isCollapsed ? anchorButton.center.y : topButton.frame.minY - Self.HeaderSpacing - header.bounds.height/2
            header.center = CGPoint(
                x: anchorButton.center.x - (header.bounds.width - anchorButton.bounds.width) / 2,
                y: headerCenterY)
            header.alpha = isCollapsed ? 0 : 1
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        if !isCollapsed {
            _ = presenter?.toggledFloatingMenu(self, to: .collapsed)
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
        label.textColor = .overlayLabel
        label.font = .gothamFont(forTextStyle: textStyle, weight: .medium)
        label.text = text
        return label
    }

    // MARK: Private

    private var isCollapsed: Bool { self.expansionState == .collapsed }

    private var orderedButtons: [FloatingMenuButton] {
        [anchorButton] + expandedButtons
    }
    
    private var allButtons: [FloatingMenuButton] {
        [triggerButton] + orderedButtons
    }

    // NB: Not in use as of 3/8/22. We used to show a "New Post" menu header but it was confusing users.
    private var expandedHeader: UIView?

    private func setup() {
        for button in allButtons.reversed() {
            button.menu = self
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowRadius = 6
            button.layer.shadowOpacity = Self.ShadowOpacity
            button.layer.shadowOffset = CGSize(width: 0, height: 5)
            
            if button === triggerButton {
                continue
            }
            
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }

        if let header = expandedHeader {
            view.addSubview(header)
        }

        view.setNeedsLayout()
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return FloatingMenuPresentController()
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return FloatingMenuDismissController()
    }
}

// MARK: - custom view controller presentation

fileprivate final class FloatingMenuPresentController: NSObject, UIViewControllerAnimatedTransitioning {
    private var presentFinishedListener: AnyCancellable?
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let menu = transitionContext.viewController(forKey: .to) as? FloatingMenu else {
            transitionContext.completeTransition(false)
            return
        }
        
        transitionContext.containerView.addSubview(menu.view)
        // align the menu w/ the trigger button that's on the presenting vc
        NSLayoutConstraint.activate([
            menu.anchorButton.trailingAnchor.constraint(equalTo: menu.triggerButton.trailingAnchor),
            menu.anchorButton.bottomAnchor.constraint(equalTo: menu.triggerButton.bottomAnchor),
        ])
        
        menu.triggerButton.layer.shadowOpacity = 0
        menu.view.layoutIfNeeded()
        
        // we use the menu's animation method
        presentFinishedListener = menu.setExpansionState(.expanded, animated: true).sink {
            transitionContext.completeTransition(true)
        }
    }
}

fileprivate final class FloatingMenuDismissController: NSObject, UIViewControllerAnimatedTransitioning {
    private var dismissFinishedListener: AnyCancellable?
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let from = transitionContext.viewController(forKey: .from) as! FloatingMenu
        
        dismissFinishedListener = from.setExpansionState(.collapsed, animated: true).sink {
            from.triggerButton.layer.shadowOpacity = FloatingMenu.ShadowOpacity
            from.anchorButton.layer.shadowOpacity = 0
            
            transitionContext.completeTransition(true)
        }
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

// MARK: - AccessorizedFloatingButton implementation

final class AccessorizedFloatingButton: UIControl {
    init(icon: UIImage?, accessoryView: UIView) {
        self.accessoryView = accessoryView
        super.init(frame: .zero)

        imageView.image = icon
        imageView.contentMode = .scaleAspectFit
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillView)
        pillView.constrain(to: self)
        
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 7
        view.addSubview(stackView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white

        // using a less than constraint here adds a little bit of padding to the left, making the image off-center
        // instead, we now use a fixed value and a lower priority
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: FloatingMenu.ButtonDiameter)
        widthConstraint.priority = .defaultLow
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -FloatingMenu.ButtonDiameter/2),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            accessoryView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            accessoryView.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: FloatingMenu.ButtonDiameter),
            widthConstraint,
        ])
        
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
