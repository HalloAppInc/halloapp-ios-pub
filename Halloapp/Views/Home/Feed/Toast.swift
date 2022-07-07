//
//  Toast.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/9/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import UIKit

class Toast: UIView {

    enum ToastType {
        case activityIndicator, icon(UIImage?)
    }

    private static let transitionDuration: TimeInterval = 0.4

    private var hideTimer: Timer?

    private let activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true
        return activityIndicator
    }()

    private let iconImageView: UIImageView = {
        let iconImageView = UIImageView()
        iconImageView.setContentHuggingPriority(UILayoutPriority(999), for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        iconImageView.tintColor = .label.withAlphaComponent(0.7)
        return iconImageView
    }()

    private let textLabel: UILabel = {
        let textLabel = UILabel()
        let fd = UIFont.systemFont(ofSize: 17, weight: .medium).fontDescriptor.withSymbolicTraits(.traitExpanded)
        textLabel.font = UIFont(descriptor: fd!, size: 17)
        textLabel.numberOfLines = 0
        textLabel.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
        textLabel.textColor = .label.withAlphaComponent(0.7)
        return textLabel
    }()

    init(type: ToastType, text: String) {
        super.init(frame: .zero)

        backgroundColor = .toastBackground
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let stackView = UIStackView(arrangedSubviews: [activityIndicator, iconImageView, textLabel])
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        updateWithoutAnimation(type: type, text: text)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hide)))

        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let cornerRadius = min(bounds.width, bounds.height, 40) / 2
        layer.cornerRadius = cornerRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderColor()
        }
    }

    private func updateBorderColor() {
        layer.borderColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(0.25).cgColor
    }

    func update(type: ToastType, text: String, shouldAutodismiss: Bool = true) {
        hideTimer?.invalidate()

        guard self.window != nil else {
            show(shouldAutodismiss: shouldAutodismiss)
            return
        }

        // this is a bit distracting when part of the animation...
        activityIndicator.stopAnimating()

        UIView.transition(with: self, duration: Self.transitionDuration * 0.5, options: .transitionCrossDissolve) {
            self.updateWithoutAnimation(type: type, text: text)
        } completion: { [weak self] _ in
            if shouldAutodismiss {
                self?.setupDismissTimer()
            }
        }
    }

    private func updateWithoutAnimation(type: ToastType, text: String) {
        switch type {
        case .activityIndicator:
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            iconImageView.isHidden = true
        case .icon(let icon):
            iconImageView.image = icon
            iconImageView.isHidden = false
            activityIndicator.stopAnimating()
        }
        textLabel.text = text
    }

    @objc func hide() {
        hideTimer?.invalidate()
        UIView.animate(withDuration: Self.transitionDuration, delay: 0, options: .curveEaseInOut) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    /// - Parameter viewController: Use this when displaying over a modally presented view controller.
    func show(viewController: UIViewController? = nil, shouldAutodismiss: Bool = true) {
        hideTimer?.invalidate()

        guard window == nil else {
            if shouldAutodismiss {
                setupDismissTimer()
            }
            return
        }

        let rootView: UIView
        let rootViewTopAnchor: NSLayoutYAxisAnchor
        if let viewController = viewController {
            rootView = viewController.view
            rootViewTopAnchor = rootView.safeAreaLayoutGuide.topAnchor
        } else {
            var keyWindow: UIWindow?
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
                for window in scene.windows {
                    if window.isKeyWindow {
                        keyWindow = window
                        break
                    }
                }
            }

            guard let keyWindow = keyWindow else {
                DDLogError("Unable to find view to present toast")
                return
            }
            rootView = keyWindow

            // Make space for call bar if contained in RootViewController
            if let rootViewController = keyWindow.rootViewController as? RootViewController, rootViewController.view.isDescendant(of: keyWindow) {
                rootViewTopAnchor = rootViewController.primaryViewContainer.safeAreaLayoutGuide.topAnchor
            } else {
                rootViewTopAnchor = rootView.safeAreaLayoutGuide.topAnchor
            }
        }

        translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(self)

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(greaterThanOrEqualTo: rootView.readableContentGuide.leadingAnchor, constant: -8),
            centerXAnchor.constraint(equalTo: rootView.readableContentGuide.centerXAnchor),
            topAnchor.constraint(equalTo: rootViewTopAnchor, constant: 52),
        ])

        alpha = 0
        UIView.animate(withDuration: Self.transitionDuration, delay: 0, options: .curveEaseInOut) { [weak self] in
            self?.alpha = 1
        } completion: { [weak self] _ in
            if shouldAutodismiss {
                self?.setupDismissTimer()
            }
        }
    }

    private func setupDismissTimer() {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 3, target: self, selector: #selector(hide), userInfo: nil, repeats: false)
        RunLoop.current.add(timer, forMode: .common)
        hideTimer = timer
    }

    static func show(type: ToastType, text: String) {
        Toast(type: type, text: text).show()
    }
}
