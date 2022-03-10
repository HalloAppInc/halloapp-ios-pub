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

    private static let fadeDuration: TimeInterval = 0.4

    private let iconImageView: UIImageView = {
        let iconImageView = UIImageView()
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
        textLabel.textColor = .label.withAlphaComponent(0.7)
        return textLabel
    }()

    init(icon: UIImage? = nil, text: String) {
        super.init(frame: .zero)

        backgroundColor = .toastBackground
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let stackView = UIStackView()
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

        if let icon = icon {
            iconImageView.image = icon
            stackView.addArrangedSubview(iconImageView)
        }

        textLabel.text = text
        stackView.addArrangedSubview(textLabel)

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

    @objc private func hide() {
        UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: .curveEaseInOut) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    static func show(icon: UIImage? = nil, text: String) {
        var keyWindow: UIWindow?
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
            for window in scene.windows {
                if window.isKeyWindow {
                    keyWindow = window
                    break
                }
            }
        }

        guard let rootView = keyWindow?.rootViewController?.view else {
            DDLogError("Unable to find view to present toast")
            return
        }

        let toast = Toast(icon: icon, text: text)
        toast.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(toast)

        // Make space for call bar if contained in RootViewController
        let topAnchor: NSLayoutYAxisAnchor
        if let rootViewController = keyWindow?.rootViewController as? RootViewController {
            topAnchor = rootViewController.primaryViewContainer.safeAreaLayoutGuide.topAnchor
        } else {
            topAnchor = rootView.safeAreaLayoutGuide.topAnchor
        }

        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.readableContentGuide.leadingAnchor, constant: -8),
            toast.centerXAnchor.constraint(equalTo: rootView.readableContentGuide.centerXAnchor),
            toast.topAnchor.constraint(equalTo: topAnchor, constant: 52),
        ])

        toast.alpha = 0
        UIView.animate(withDuration: fadeDuration, delay: 0, options: .curveEaseInOut) {
            toast.alpha = 1
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) { [weak toast] in
                toast?.hide()
            }
        }
    }
}
