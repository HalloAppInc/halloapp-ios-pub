//
//  RegistrationSplashScreenViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/30/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class RegistrationSplashScreenViewController: UIViewController {

    let registrationManager: RegistrationManager

    private lazy var backgroundImageView: UIImageView = {
        let view = UIImageView()
        view.layer.compositingFilter = "colorBurnBlendMode"
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "SplashScreenDoodle")?.withRenderingMode(.alwaysTemplate).resizableImage(withCapInsets: .zero, resizingMode: .tile)
        view.tintColor = .black.withAlphaComponent(0.12)
        return view
    }()

    private lazy var iconContainerCenterYConstraint = iconContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    private lazy var iconContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "AppIconBig")
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var iconTitle: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "ShadowedAppName")
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var descriptionLabel: ShadowedLabel = {
        let label = ShadowedLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .quicksandFont(ofFixedSize: 33, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white.withAlphaComponent(0.95)
        label.text = Localizations.yourPrivateSocialNetwork
        label.adjustsFontSizeToFitWidth = true

        label.shadowColor = UIColor(red: 1.00, green: 0.27, blue: 0.00, alpha: 0.25)
        label.shadowOffset = CGSize(width: 0, height: 1.5)
        label.layer.shadowRadius = 0.5

        label.alpha = 0
        return label
    }()

    private lazy var whiteLinearGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        let color = UIColor.white
        gradient.compositingFilter = "screenBlendMode"

        gradient.colors = [
            color.withAlphaComponent(0.25).cgColor,
            color.withAlphaComponent(0).cgColor,
        ]

        gradient.locations = [0, 1]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        return gradient
    }()

    private lazy var redLinearGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        let color = UIColor.red
        gradient.compositingFilter = "screenBlendMode"

        gradient.colors = [
            color.withAlphaComponent(0.8).cgColor,
            color.withAlphaComponent(0.6).cgColor,
        ]

        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = .zero
        return gradient
    }()

    init(registrationManager: RegistrationManager) {
        self.registrationManager = registrationManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.delegate = self
        navigationController?.setNavigationBarHidden(true, animated: false)

        view.backgroundColor = UIColor(red: 1.00, green: 0.40, blue: 0.27, alpha: 1.00).withAlphaComponent(1)
        view.addSubview(backgroundImageView)
        view.layer.addSublayer(whiteLinearGradient)
        view.layer.addSublayer(redLinearGradient)

        let gradient = RadialGradientView()
        gradient.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(descriptionLabel)
        view.addSubview(iconContainer)
        iconContainer.addSubview(gradient)
        iconContainer.addSubview(iconImageView)
        iconContainer.addSubview(iconTitle)

        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            gradient.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            gradient.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            gradient.widthAnchor.constraint(equalToConstant: 350),
            gradient.heightAnchor.constraint(equalToConstant: 350),

            iconContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconContainerCenterYConstraint,
            iconContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            iconContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),

            iconImageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.45),
            iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),

            iconTitle.topAnchor.constraint(equalTo: iconImageView.bottomAnchor),
            iconTitle.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            iconTitle.widthAnchor.constraint(equalTo: iconImageView.widthAnchor),
            iconTitle.heightAnchor.constraint(equalToConstant: 100),
            iconTitle.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),

            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            descriptionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)

        let distance = iconContainer.frame.midY / 2
        iconContainerCenterYConstraint.constant = -distance

        UIView.animate(withDuration: 0.45, delay: 0.4, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: .curveEaseOut) {
            self.iconContainer.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
            self.descriptionLabel.alpha = 1
            self.view.layoutIfNeeded()
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.goToNextScreen()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        whiteLinearGradient.frame = view.bounds
        redLinearGradient.frame = view.bounds
    }

    private func goToNextScreen() {
        let vc = PhoneNumberEntryViewController(registrationManager: registrationManager)

        navigationController?.pushViewController(vc, animated: true)
        navigationController?.delegate = nil
    }
}

// MARK: - RadialGradientView implementation

fileprivate class RadialGradientView: UIView {

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else {
            return
        }

        layer.compositingFilter = "screenBlendMode"

        gradient.type = .radial
        gradient.colors = [
            UIColor.white.withAlphaComponent(0.125).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]

        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("RadialGradientView coder init not implemented...")
    }
}

// MARK: - ShadowedLabel implementation

fileprivate class ShadowedLabel: UILabel {

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }
}

// MARK: - UINavigationControllerDelegate methods

extension RegistrationSplashScreenViewController: UINavigationControllerDelegate {

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        if case .push = operation, fromVC is RegistrationSplashScreenViewController {
            return SplashScreenPushTransition()
        }

        return nil
    }
}

// MARK: - SplashScreenPushTransition implementation

fileprivate class SplashScreenPushTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.275
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let to = transitionContext.viewController(forKey: .to),
            let from = transitionContext.viewController(forKey: .from)
        else {
            return
        }

        to.view.frame = transitionContext.finalFrame(for: to)
        transitionContext.containerView.insertSubview(to.view, at: 0)

        UIView.animate(withDuration: transitionDuration(using: nil)) {
            from.view.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            from.view.alpha = 0
        } completion: { _ in
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - Localization

extension Localizations {

    static var yourPrivateSocialNetwork: String {
        NSLocalizedString("your.private.social.network",
                   value: "Welcome to your private social network",
                 comment: "Text that appears on the splash screen prior to registration.")
    }
}
