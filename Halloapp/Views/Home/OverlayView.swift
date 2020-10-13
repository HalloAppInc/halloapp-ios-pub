//
//  OverlayView.swift
//  HalloApp
//
//  Created by Garrett on 9/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import UIKit

final class NUXItem: UIView {
    typealias Action = (NUXItem) -> Void
    typealias NUXLink = (text: String, action: Action)

    init(message: String, icon: UIImage? = nil, link: NUXLink? = nil, didClose: (() -> Void)? = nil) {

        self.link = link
        self.didClose = didClose

        super.init(frame: .zero)

        addSubview(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .nux
        panel.layer.cornerRadius = 15
        panel.layoutMargins = .init(top: 20, left: 20, bottom: 20, right: 20)
        panel.constrainMargins([.leading, .trailing, .bottom], to: self)

        addSubview(label)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .callout, weight: .bold)
        label.constrainMargins([.leading, .trailing], to: panel)

        if let link = link {
            addSubview(linkButton)
            linkButton.translatesAutoresizingMaskIntoConstraints = false
            linkButton.setTitle(link.text, for: .normal)
            linkButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .bold)
            linkButton.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
            linkButton.constrainMargins([.trailing, .bottom], to: panel)
            linkButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4).isActive = true
            linkButton.addTarget(self, action: #selector(didTapLink), for: .touchUpInside)
        } else {
            label.constrainMargins([.bottom], to: panel)
        }

        if let icon = icon {
            addSubview(imageView)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = icon

            imageView.constrainMargins([.leading], to: panel)
            imageView.constrainMargins([.top], to: self)
            imageView.constrain(anchor: .top, to: panel, constant: -24)
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor).isActive = true
        } else {
            panel.constrainMargin(anchor: .top, to: self)
            label.constrainMargin(anchor: .top, to: panel)
        }

        addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        closeButton.constrain(anchor: .trailing, to: panel, constant: -15)
        closeButton.constrain(anchor: .top, to: panel, constant: 15)
        closeButton.addTarget(self, action: #selector(didTapCloseButton), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismiss() -> Future<Void, Never> {
        Future { promise in
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: AnimationOptions(),
                animations: {
                    self.transform = .init(scaleX: 0.1, y: 0.1)
                    self.alpha = 0 },
                completion: { _ in
                    self.didClose?()
                    promise(.success(())) })
        }
    }

    // MARK: Private

    private let imageView = UIImageView()
    private let label = UILabel()
    private let linkButton = UIButton()
    private let closeButton = UIButton()
    private let panel = UIView()
    private let link: NUXLink?
    private let didClose: (() -> Void)?
    private var cancellableSet = Set<AnyCancellable>()

    @objc
    private func didTapLink() {
        link?.action(self)
    }

    @objc
    private func didTapCloseButton() {
        _ = dismiss()
    }
}

final class NUXPopover: UIView, Overlay {

    init(_ message: String, targetRect: CGRect? = nil, targetSpace: UICoordinateSpace? = nil, showButton: Bool = true, completion: (() -> Void)?) {
        self.completion = completion
        self.targetRect = targetRect
        self.targetSpace = targetSpace

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .nux
        panel.layer.cornerRadius = 15
        panel.layoutMargins = .init(top: 25, left: 25, bottom: 25, right: 25)
        panel.constrainMargins([.leading, .trailing], to: self)

        addSubview(arrow)
        arrow.tintColor = .nux
        arrow.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(label)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .callout)
        label.constrainMargins([.leading, .trailing, .top], to: panel)

        if showButton {
            panel.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("OK", for: .normal)
            button.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .medium)
            button.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
            button.constrainMargins([.trailing, .bottom], to: panel)
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4).isActive = true
            button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        } else {
            label.constrainMargin(anchor: .bottom, to: panel)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let label = UILabel()
    private let button = UIButton()
    private let panel = UIView()
    private let arrow = UIImageView(image: UIImage(named: "NUXArrow")?.withRenderingMode(.alwaysTemplate))
    private let completion: (() -> Void)?
    private let targetRect: CGRect?
    private let targetSpace: UICoordinateSpace?
    private let arrowSpacing: CGFloat = 8

    @objc
    func didTapButton() {
        overlayContainer?.dismiss(self)
    }

    // Overlay

    weak var overlayContainer: OverlayContainer?
    var overlayID = UUID().uuidString
    var dismissBehavior = DismissBehavior.dismissOnInteraction

    func display(in container: OverlayContainer) {
        overlayContainer = container
        constrainMargins([.leading, .trailing], to: container)

        // We need the container to be positioned correctly in order to convert coordinates
        container.superview?.layoutIfNeeded()

        if let targetRect = targetRect, let targetSpace = targetSpace {
            let convertedRect = container.convert(targetRect, from: targetSpace)
            arrow.centerXAnchor.constraint(equalTo: container.leftAnchor, constant: convertedRect.midX).isActive = true

            // Draw the popover above or below the target based on where more space is available
            let shouldPointDown = convertedRect.minY > container.bounds.maxY - convertedRect.maxY
            if shouldPointDown {
                bottomAnchor.constraint(equalTo: container.topAnchor, constant: convertedRect.minY).isActive = true
                topAnchor.constraint(greaterThanOrEqualTo: container.layoutMarginsGuide.topAnchor).isActive = true
                arrow.transform = .init(scaleX: 1, y: -1)
                arrow.topAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true
                arrow.constrain(anchor: .bottom, to: self, constant: -arrowSpacing)
                panel.constrain(anchor: .top, to: self)
            } else {
                topAnchor.constraint(equalTo: container.topAnchor, constant: convertedRect.maxY).isActive = true
                bottomAnchor.constraint(lessThanOrEqualTo: container.layoutMarginsGuide.bottomAnchor).isActive = true
                arrow.bottomAnchor.constraint(equalTo: panel.topAnchor).isActive = true
                arrow.constrain(anchor: .top, to: self, constant: arrowSpacing)
                panel.constrain(anchor: .bottom, to: self)
            }
        } else {
            // Center the popover and draw an arrow pointing up at nothing in particular
            arrow.bottomAnchor.constraint(equalTo: panel.topAnchor).isActive = true
            arrow.constrain([.top, .centerX], to: self)
            panel.constrain(anchor: .bottom, to: self)
            constrain(anchor: .centerY, to: container)
        }

        transform = .init(scaleX: 0, y: 0)
        alpha = 0

        UIView.animate(
            withDuration: 0.5,
            delay: 0.2,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0,
            options: AnimationOptions(),
            animations: {
                self.transform = .identity
                self.alpha = 1 },
            completion: { _ in })
    }

    func _dismiss() -> Future<Void, Never> {
        Future { promise in
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: AnimationOptions(),
                animations: {
                    self.transform = .init(scaleX: 0.1, y: 0.1)
                    self.alpha = 0 },
                completion: { _ in
                    self.completion?()
                    promise(.success(())) })
        }
    }
}

final class BottomSheet: UIView, Overlay {

    init(innerView: UIView, completion: (() -> Void)?) {
        self.completion = completion
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layoutMargins = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        backgroundColor = .systemBackground
        layer.cornerRadius = 15

        // TODO: Create scrollable container for innerview
        addSubview(innerView)
        innerView.translatesAutoresizingMaskIntoConstraints = false
        innerView.constrainMargins(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let completion: (() -> Void)?

    let overlayID = UUID().uuidString
    weak var overlayContainer: OverlayContainer?
    var dismissBehavior = DismissBehavior.dismissOnInteraction

    func display(in container: OverlayContainer) {
        overlayContainer = container
        constrain([.leading, .trailing, .bottom], to: container)
        topAnchor.constraint(greaterThanOrEqualTo: container.layoutMarginsGuide.topAnchor).isActive = true

        layoutIfNeeded()
        transform = .init(translationX: 0, y: frame.height)
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: AnimationOptions(),
            animations: {
                self.transform = .identity
                container.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            },
            completion: { _ in })
    }

    func _dismiss() -> Future<Void, Never> {
        Future { promise in
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: AnimationOptions(),
                animations: {
                    self.transform = .init(translationX: 0, y: self.frame.height)
                    self.overlayContainer?.backgroundColor = .clear
            },
                completion: { _ in
                    self.completion?()
                    promise(.success(())) })
        }
    }


}

protocol Overlay: UIView {

    /// Unique identifier
    var overlayID: String { get }

    /// Describes if and when overlay container should dismiss overlay
    var dismissBehavior: DismissBehavior { get }

    /// Called after being added to the container
    func display(in container: OverlayContainer)

    /// Called before being removed from the container. Should only be called by container.
    func _dismiss() -> Future<Void, Never>
}

enum DismissBehavior {
    /// Container should dismiss on any interaction with the view underneath
    case dismissOnInteraction

    /// Container should not dismiss until requested
    case dismissOnExplicitRequest
}

final class OverlayContainer: UIView {

    private var overlays = [Overlay]()
    private var cancellableSet = Set<AnyCancellable>()

    func display(_ overlay: Overlay) {
        overlays.append(overlay)
        addSubview(overlay)
        overlay.display(in: self)
    }

    func dismiss(_ overlay: Overlay) {
        cancellableSet.insert(
            overlay._dismiss().sink() {
                overlay.removeFromSuperview()
            }
        )
        overlays.removeAll(where: { $0.overlayID == overlay.overlayID })
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result: UIView? = overlays.reduce(nil) { hitView, target in
            let convertedPoint = self.convert(point, to: target)
            return hitView ?? target.hitTest(convertedPoint, with: event)
        }
        if result == nil {
            overlays
                .filter { $0.dismissBehavior == .dismissOnInteraction }
                .forEach { dismiss($0) }
        }
        return result
    }
}

