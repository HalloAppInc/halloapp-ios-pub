//
//  ViewfinderView.swift
//  HalloApp
//
//  Created by Tanveer on 9/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import AVFoundation

protocol ViewfinderViewDelegate: AnyObject {
    func viewfinder(_ view: ViewfinderView, focusedOn point: CGPoint)
    func viewfinder(_ view: ViewfinderView, zoomedTo scale: CGFloat)
}

fileprivate class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

final class ViewfinderView: UIView, UIGestureRecognizerDelegate {

    private(set) fileprivate var isObscured = false
    private var cancellables: Set<AnyCancellable> = []

    var previewLayer: AVCaptureVideoPreviewLayer {
        previewView.previewLayer
    }

    var cameraPosition: AVCaptureDevice.Position? {
        previewLayer.connection?.inputPorts.first?.sourceDevicePosition
    }

    private lazy var previewView: PreviewView = {
        let view = PreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }()

    private lazy var toggleButtonTopConstraint = toggleButton.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor)
    private lazy var toggleButtonBottomConstraint = toggleButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)

    fileprivate private(set) lazy var toggleButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var focusIndicator: CircleView = {
        let diameter: CGFloat = 30
        let view = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
        view.fillColor = .clear
        view.lineWidth = 1.75
        view.strokeColor = .white
        view.alpha = 0
        return view
    }()

    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private var hideFocusIndicator: DispatchWorkItem?
    weak var delegate: ViewfinderViewDelegate?

    private var previewingCancellable: AnyCancellable?
    private var placeholderSnapshot: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true

        addSubview(previewView)
        addSubview(focusIndicator)
        addSubview(toggleButton)
        addSubview(blurView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor),

            toggleButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(focusTap))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchToZoom))

        tap.delegate = self
        addGestureRecognizer(tap)
        addGestureRecognizer(pinch)

        previewLayer.publisher(for: \.isPreviewing)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.animateConnectionChange()
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func animateConnectionChange() {
        let isPreviewing = previewLayer.isPreviewing
        if !isPreviewing {
            prepareForObfuscation()
        }

        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut) {
            if isPreviewing {
                self.clear()
            } else {
                self.obscure()
            }
        }
    }

    fileprivate func prepareForObfuscation() {
        guard !isObscured else {
            return
        }

        setPlaceholderSnapshot()
        placeholderSnapshot?.alpha = 0
    }

    private func setPlaceholderSnapshot() {
        guard let snapshot = snapshotView(afterScreenUpdates: false) else {
            return
        }

        snapshot.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(snapshot, belowSubview: blurView)
        NSLayoutConstraint.activate([
            snapshot.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            snapshot.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
        ])

        placeholderSnapshot?.removeFromSuperview()
        placeholderSnapshot = snapshot
    }

    fileprivate func obscure() {
        blurView.effect = UIBlurEffect(style: .prominent)
        placeholderSnapshot?.alpha = 1

        isObscured = true
    }

    fileprivate func clear() {
        guard previewLayer.isPreviewing else {
            return
        }

        blurView.effect = nil
        placeholderSnapshot?.alpha = 0

        isObscured = false
    }

    fileprivate func updateButtonPosition(for newLayout: ViewfinderLayout) {
        var image: UIImage?
        var activateTopConstraint = true

        switch newLayout {
        case .splitPortrait(leading: _):
            image = UIImage(systemName: "arrow.right.circle.fill")?.imageFlippedForRightToLeftLayoutDirection()
        case .fullPortrait(_):
            image = UIImage(systemName: "arrow.left.circle.fill")?.imageFlippedForRightToLeftLayoutDirection()
        case .splitLandscape(top: _):
            image = UIImage(systemName: "arrow.down.circle.fill")
            activateTopConstraint = false
        case .fullLandscape(_):
            image = UIImage(systemName: "arrow.up.circle.fill")
            activateTopConstraint = false
        }

        toggleButton.setImage(image, for: .normal)

        toggleButtonTopConstraint.isActive = activateTopConstraint
        toggleButtonBottomConstraint.isActive = !activateTopConstraint
    }

    @objc
    private func focusTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let converted = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        showFocusIndicator(for: point)
        delegate?.viewfinder(self, focusedOn: converted)
    }

    private func showFocusIndicator(for point: CGPoint) {
        hideFocusIndicator?.cancel()

        focusIndicator.alpha = 0
        focusIndicator.center = point
        focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)

        UIView.animate(withDuration: 0.15,
                              delay: 0,
             usingSpringWithDamping: 0.7,
              initialSpringVelocity: 0.5,
                            options: [.allowUserInteraction])
        {
            self.focusIndicator.transform = .identity
            self.focusIndicator.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleFocusIndicatorHide()
        }
    }

    private func scheduleFocusIndicatorHide() {
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.15,
                                  delay: 0,
                 usingSpringWithDamping: 0.7,
                  initialSpringVelocity: 0.5,
                                options: [.allowUserInteraction])
            {
                self?.focusIndicator.alpha = 0
                self?.focusIndicator.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                self?.hideFocusIndicator = nil
            }
        }

        hideFocusIndicator = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    @objc
    private func pinchToZoom(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        gesture.scale = 1

        delegate?.viewfinder(self, zoomedTo: scale)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer, toggleButton.frame.insetBy(dx: -10, dy: -10).contains(gestureRecognizer.location(in: self)) {
            return false
        }

        return true
    }
}

// MARK: - ViewfinderContainer implementation

class ViewfinderContainer: UIView, CameraPresetConfigurable {

    typealias State = CameraViewModel.ViewfinderState
    private var cancellables: Set<AnyCancellable> = []

    private(set) lazy var primaryViewfinder: ViewfinderView = {
        let view = ViewfinderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    private(set) lazy var secondaryViewfinder: ViewfinderView = {
        let view = ViewfinderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var changeLayoutButton: OverlayButton = {
        let button = OverlayButton(type: .system)
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = UIImage(systemName: "square.split.1x2.fill", withConfiguration: configuration)?
            .withRenderingMode(.alwaysOriginal)
            .withTintColor(.white)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(prepareFeedbackGenerator), for: .touchDown)
        button.addTarget(self, action: #selector(changeLayoutButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var feedbackGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        return generator
    }()

    private var viewfinderConstraints: [ViewfinderView: [NSLayoutConstraint]] = [:]

    weak var delegate: ViewfinderContainerDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true

        addSubview(primaryViewfinder)
        addSubview(secondaryViewfinder)
        addSubview(changeLayoutButton)
        addSubview(blurView)

        var minimizers = [NSLayoutConstraint]()
        for viewfinder in [primaryViewfinder, secondaryViewfinder] {
            makeViewfinderConstraints(for: viewfinder)

            minimizers.append(contentsOf: [
                viewfinder.widthAnchor.constraint(equalToConstant: 0),
                viewfinder.heightAnchor.constraint(equalToConstant: 0),
            ])

            viewfinder.toggleButton.addTarget(self, action: #selector(prepareFeedbackGenerator), for: .touchDown)
            viewfinder.toggleButton.addTarget(self, action: #selector(viewfinderToggleButtonPushed), for: .touchUpInside)
        }

        minimizers.forEach { $0.priority = .defaultLow }
        let constraints = [
            changeLayoutButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            changeLayoutButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        fatalError("ViewfinderContainer coder init not implemented...")
    }

    private func makeViewfinderConstraints(for viewfinder: ViewfinderView) {
        let constraints = [
            viewfinder.leadingAnchor.constraint(equalTo: leadingAnchor),
            viewfinder.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewfinder.topAnchor.constraint(equalTo: topAnchor),
            viewfinder.bottomAnchor.constraint(equalTo: bottomAnchor),

            viewfinder.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),
            viewfinder.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),

            // for when one view finder is not visible on screen
            viewfinder.leadingAnchor.constraint(equalTo: trailingAnchor),
            viewfinder.topAnchor.constraint(equalTo: bottomAnchor),
            viewfinder.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1),
            viewfinder.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1),
        ]

        for constraint in constraints {
            constraint.priority = .defaultHigh
        }

        viewfinderConstraints[viewfinder] = constraints
    }

    func change(from state: State, to newState: State, updateLayout: Bool) {
        guard updateLayout, state.layout != newState.layout else {
            return updateButtons(with: newState)
        }

        let currentPrimary = state.layout.positions.primary
        let newPrimary = newState.layout.positions.primary

        for button in [primaryViewfinder.toggleButton, secondaryViewfinder.toggleButton] {
            button.isHidden = true
        }

        changeLayoutButton.isEnabled = false

        switch newPrimary {
        case currentPrimary.flipped:
            // just switch the viewfinders
            change(primaryViewfinder, to: newPrimary)
            change(secondaryViewfinder, to: newPrimary.flipped)
            updateButtons(with: newState)

        case currentPrimary.next?.next:
            // more complex 2-step animation to change from portrait to landscape or vice versa
            let completion: () -> Void = { [weak self] in
                guard let self else { return }
                self.delegate?.viewfinderContainerDidCompleteLayoutChange(self)
                self.updateButtons(with: newState, animated: true)
            }

            if let next = currentPrimary.next {
                obscureAndAnimate(to: (next, next.flipped), completion)
            }

        case currentPrimary.toggled:
            // expand one viewfinder to full-screen
            let completion: () -> Void = { [weak self] in
                self?.updateButtons(with: newState, animated: false)
            }

            obscureAndAnimate(to: (newPrimary, newPrimary.flipped), completion)

        default:
            break
        }
    }

    private func updateButtons(with state: State, animated: Bool = false) {
        if animated {
            return UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0) {
                self.updateButtons(with: state)
            }
        }

        let layout = state.layout
        let allowsTogglingLayout = state.allowsTogglingLayout
        let allowsChangingLayout = state.allowsChangingLayout

        var transform = changeLayoutButton.transform
        var angle: CGFloat = 0
        var shouldShowToggleOnPrimary = true
        let shouldShowToggleOnSecondary: Bool
        var canChangeLayout = true

        switch (layout, layout.primaryCameraPosition) {
        case (.splitPortrait(leading: _), .back):
            angle = 0
        case (.splitPortrait(leading: _), _):
            angle = .pi
            shouldShowToggleOnPrimary = false
        case (.splitLandscape(top: _), .back):
            angle = .pi / 2
        case (.splitLandscape(top: _), _):
            angle = .pi * 3 / 2
            shouldShowToggleOnPrimary = false
        case (.fullPortrait(_), .back), (.fullLandscape(_), .back):
            canChangeLayout = false
        case (.fullPortrait(_), _), (.fullLandscape(_), _):
            canChangeLayout = false
            shouldShowToggleOnPrimary = false
        }

        transform = .init(rotationAngle: angle)
        shouldShowToggleOnSecondary = !shouldShowToggleOnPrimary

        changeLayoutButton.transform = transform
        changeLayoutButton.isHidden = !(canChangeLayout && allowsChangingLayout)
        changeLayoutButton.isEnabled = true

        primaryViewfinder.updateButtonPosition(for: layout)
        secondaryViewfinder.updateButtonPosition(for: layout)
        primaryViewfinder.toggleButton.isHidden = !(shouldShowToggleOnPrimary && allowsTogglingLayout)
        secondaryViewfinder.toggleButton.isHidden = !(shouldShowToggleOnSecondary && allowsTogglingLayout)
    }

    func set(preset: CameraPreset, animator: UIViewPropertyAnimator?) {
        let positions = preset.initialLayout.positions
        change(primaryViewfinder, to: positions.primary)
        change(secondaryViewfinder, to: positions.secondary)

        guard let animator, let snapshot = snapshotView(afterScreenUpdates: false) else {
            return
        }

        insertSubview(snapshot, belowSubview: blurView)
        snapshot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snapshot.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: trailingAnchor),
            snapshot.topAnchor.constraint(equalTo: topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        UIView.animate(withDuration: 0.15, delay: 0) {
            self.blurView.effect = UIBlurEffect(style: .prominent)
        }

        animator.addCompletion { [weak self] _ in
            snapshot.removeFromSuperview()

            UIView.animate(withDuration: 0.25, delay: 0) {
                self?.blurView.effect = nil
            }
        }
    }

    private func animators(for position: ViewfinderPosition) -> (layoutAnimator: UIViewPropertyAnimator, stateAnimator: UIViewPropertyAnimator?) {
        let layoutAnimator: UIViewPropertyAnimator
        let stateAnimator: UIViewPropertyAnimator?

        if position.isIntermediate {
            layoutAnimator = UIViewPropertyAnimator(duration: 0.2,
                                               controlPoint1: .init(x: 0.16, y: 0.84),
                                               controlPoint2: .init(x: 0.44, y: 1))
            stateAnimator = nil
        } else {
            layoutAnimator = UIViewPropertyAnimator(duration: 0.25,
                                               controlPoint1: .init(x: 0.19, y: 1),
                                               controlPoint2: .init(x: 0.22, y: 1))
            stateAnimator = UIViewPropertyAnimator(duration: 0.1, curve: .linear)
        }

        layoutAnimator.addAnimations {
            self.layoutIfNeeded()
        }

        stateAnimator?.addAnimations {
            self.primaryViewfinder.clear()
            self.secondaryViewfinder.clear()
        }

        return (layoutAnimator, stateAnimator)
    }

    @objc
    private func prepareFeedbackGenerator(_ button: UIButton) {
        
    }

    @objc
    private func viewfinderToggleButtonPushed(_ button: UIButton) {
        delegate?.viewfinderContainerDidToggleExpansion(self)
    }

    @objc
    private func changeLayoutButtonPushed(_ button: UIButton) {
        delegate?.viewfinderContainerDidSelectLayoutChange(self)
    }

    private func obscureAndAnimate(to positions: (ViewfinderPosition, ViewfinderPosition), _ completion: @escaping () -> Void) {
        primaryViewfinder.prepareForObfuscation()
        secondaryViewfinder.prepareForObfuscation()

        UIView.animate(withDuration: 0.1) {
            self.primaryViewfinder.obscure()
            self.secondaryViewfinder.obscure()
        } completion: { _ in
            self.animateLayout(positions.0, positions.1, completion)
        }
    }

    private func animateLayout(_ primaryLayout: ViewfinderPosition, _ secondaryLayout: ViewfinderPosition, _ completion: @escaping () -> Void) {
        let (layoutAnimator, stateAnimator) = animators(for: primaryLayout)

        change(primaryViewfinder, to: primaryLayout)
        change(secondaryViewfinder, to: secondaryLayout)
        layoutAnimator.startAnimation()

        if let stateAnimator {
            DispatchQueue.main.asyncAfter(deadline: .now() + layoutAnimator.duration * 0.65) {
                stateAnimator.startAnimation()
            }
        }

        if !primaryLayout.isIntermediate {
            DispatchQueue.main.asyncAfter(deadline: .now() + layoutAnimator.duration * 0.6) {
                completion()
            }
        }

        guard
            primaryLayout.isIntermediate,
            let nextPrimaryLayout = primaryLayout.next,
            let nextSecondaryLayout = secondaryLayout.next
        else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + layoutAnimator.duration * 0.8) { [weak self] in
            self?.animateLayout(nextPrimaryLayout, nextSecondaryLayout, completion)
        }
    }

    private func change(_ viewfinder: ViewfinderView, to layout: ViewfinderPosition) {
        guard let constraints = viewfinderConstraints[viewfinder] else {
            return
        }

        var leading = true
        var trailing = true
        var top = true
        var bottom = true
        var width = true
        var height = true
        var fullHeight = false
        var fullWidth = false
        var leadingToTrailing = false
        var topToBottom = false

        switch layout {
        case .leading:
            trailing = false
            height = false
        case .trailing:
            leading = false
            height = false
        case .top:
            bottom = false
            width = false
        case .bottom:
            top = false
            width = false

        case .topLeading:
            trailing = false
            bottom = false
        case .topTrailing:
            leading = false
            bottom = false
        case .bottomTrailing:
            leading = false
            top = false
        case .bottomLeading:
            trailing = false
            top = false

        case .fullPortrait, .fullLandscape:
            width = false
            height = false

        case .collapsedPortrait:
            leading = false
            trailing = false
            width = false
            height = false
            leadingToTrailing = true
            fullWidth = true
            fullHeight = true
        case .collapsedLandscape:
            top = false
            bottom = false
            width = false
            height = false
            topToBottom = true
            fullWidth = true
            fullHeight = true
        }

        for constraint in constraints {
            let isActive: Bool

            switch constraint.firstAttribute {
            case .leading where constraint.secondAttribute == .trailing:
                isActive = leadingToTrailing
            case .top where constraint.secondAttribute == .bottom:
                isActive = topToBottom
            case .leading:
                isActive = leading
            case .trailing:
                isActive = trailing
            case .top:
                isActive = top
            case .bottom:
                isActive = bottom
            case .width where constraint.multiplier == 1:
                isActive = fullWidth
            case .height where constraint.multiplier == 1:
                isActive = fullHeight
            case .width:
                isActive = width
            case .height:
                isActive = height
            default:
                isActive = constraint.isActive
            }

            constraint.isActive = isActive
        }
    }

    private func updateLayoutButton(with layout: ViewfinderPosition, animated: Bool = false) {
        if animated {
            return UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
                self.updateLayoutButton(with: layout)
            }
        }

        var transform = changeLayoutButton.transform
        var isHidden = false

        switch layout {
        case .fullPortrait, .fullLandscape, .collapsedPortrait, .collapsedLandscape:
            isHidden = true
        case .leading:
            transform = .identity
        case .top:
            transform = .init(rotationAngle: .pi / 2)
        case .trailing:
            transform = .init(rotationAngle: .pi)
        case .bottom:
            transform = .init(rotationAngle: .pi * 3 / 2)
        default:
            break
        }

        changeLayoutButton.isHidden = isHidden
        changeLayoutButton.transform = transform
    }
}

// MARK: -

fileprivate class OverlayButton: UIButton {

    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentEdgeInsets = .init(top: 8, left: 8, bottom: 8, right: 8)
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayButton coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        blurView.layer.cornerRadius = min(blurView.bounds.width, blurView.bounds.height) / 2

        if subviews.first !== blurView {
            sendSubviewToBack(blurView)
        }
    }
}

extension ViewfinderContainer: ViewfinderViewDelegate {

    func viewfinder(_ view: ViewfinderView, focusedOn point: CGPoint) {
        delegate?.viewfinder(view, focusedOn: point)
    }

    func viewfinder(_ view: ViewfinderView, zoomedTo scale: CGFloat) {
        delegate?.viewfinder(view, zoomedTo: scale)
    }
}

protocol ViewfinderContainerDelegate: ViewfinderViewDelegate {
    func viewfinderContainerDidToggleExpansion(_ container: ViewfinderContainer)
    func viewfinderContainerDidSelectLayoutChange(_ container: ViewfinderContainer)
    func viewfinderContainerDidCompleteLayoutChange(_ container: ViewfinderContainer)
}
