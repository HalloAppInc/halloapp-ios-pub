//
//  RootViewController.swift
//  HalloApp
//
//  Created by Garrett on 12/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

enum UserInterfaceState {
    case expiredVersion
    case onboarding
    case mainInterface
    case initial
    case migrating
    case goodbye
}

protocol RootViewControllerDelegate: AnyObject {
    func didTapCallBar()
}

final class RootViewController: UIViewController {

    var callBar = CallBar()
    var callBarCollapsedConstraint: NSLayoutConstraint?
    var callViewController: CallViewController?

    var primaryViewContainer = UIView()
    var primaryViewController = UIViewController()

    @UserDefault(key: "shownRegistrationSplashScreen", defaultValue: false)
    private var hasShownRegistrationSplashScreen: Bool

    var state: UserInterfaceState = .initial
    weak var delegate: RootViewControllerDelegate?

    override func viewDidLoad() {
        view.addSubview(callBar)
        view.addSubview(primaryViewContainer)

        callBar.backgroundColor = .lavaOrange
        callBar.translatesAutoresizingMaskIntoConstraints = false
        callBar.constrain([.top, .leading, .trailing], to: view)
        callBar.addTarget(self, action: #selector(didTapCallBar), for: .touchUpInside)

        callBarCollapsedConstraint = callBar.heightAnchor.constraint(equalToConstant: 0)
        callBarCollapsedConstraint?.isActive = true

        primaryViewContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryViewContainer.constrain([.leading, .trailing, .bottom], to: view)

        callBar.bottomAnchor.constraint(equalTo: primaryViewContainer.topAnchor).isActive = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait]
    }

    func transition(to newState: UserInterfaceState, completion: (() -> Void)? = nil) {
        guard newState != .initial else {
            DDLogError("RootViewController/transition/aborting [should-not-transition-to-initial-state]")
            return
        }
        guard newState != state else {
            DDLogInfo("RootViewController/transition/skipping [\(state) == \(newState)]")
            return
        }

        DDLogInfo("RootViewController/transition [\(state) => \(newState)]")
        let oldState = state
        state = newState

        switch (oldState, newState) {
        case (.onboarding, .mainInterface):
            return animateMainInterfaceAfterRegistration(completion)
        default:
            break
        }

        // Remove old view
        primaryViewController.willMove(toParent: nil)
        primaryViewController.view.removeFromSuperview()
        primaryViewController.removeFromParent()

        // Add new view
        primaryViewController = viewController(forUserInterfaceState: newState)
        addChild(primaryViewController)
        primaryViewController.view.translatesAutoresizingMaskIntoConstraints = false
        primaryViewContainer.addSubview(primaryViewController.view)
        primaryViewController.view.constrain(to: primaryViewContainer)
        primaryViewController.didMove(toParent: self)

        completion?()
    }

    private func animateMainInterfaceAfterRegistration(_ completion: (() -> Void)? = nil) {
        let nextViewController = viewController(forUserInterfaceState: state)
        let currentViewController = primaryViewController

        primaryViewContainer.insertSubview(nextViewController.view, belowSubview: currentViewController.view)
        nextViewController.view.translatesAutoresizingMaskIntoConstraints = false
        nextViewController.view.constrain(to: primaryViewContainer)
        addChild(nextViewController)
        nextViewController.didMove(toParent: self)

        currentViewController.willMove(toParent: nil)
        currentViewController.removeFromParent()

        primaryViewController = nextViewController

        UIView.animate(withDuration: 0.35) {
            currentViewController.view.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            currentViewController.view.alpha = 0
        } completion: { _ in
            currentViewController.view.removeFromSuperview()
            completion?()
        }
    }

    func updateCallUI(with call: Call?, animated: Bool) {
        guard let call = call else {
            updateCallBarVisibility(false, animated: animated)
            return
        }

        callBar.call = call
        updateCallBarVisibility(true, animated: animated)
    }


    func updateCallDuration(seconds: Int) {
        callBar.updateCallDuration(seconds: seconds)
    }

    private var callBarVisible: Bool {
        guard let callBarCollapsedConstraint = callBarCollapsedConstraint else {
            return false
        }
        return !callBarCollapsedConstraint.isActive
    }

    private func updateCallBarVisibility(_ isVisible: Bool, animated: Bool) {
        guard callBarVisible != isVisible else {
            return
        }
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.callBarCollapsedConstraint?.isActive = !isVisible
            self.view.layoutIfNeeded()
        }
    }

    private func viewController(forUserInterfaceState state: UserInterfaceState) -> UIViewController {
        switch state {
        case .goodbye:
            return GoodbyeViewController()

        case .initial:
            return UIViewController()

        case .onboarding:
            let vc = makeOnboardingViewController()
            return UINavigationController(rootViewController: vc)

        case .mainInterface:
            return HomeViewController()

        case .expiredVersion:
            return ExpiredVersionViewController()

        case .migrating:
            return MigrationViewController()
        }
    }

    private func makeOnboarder() -> RegistrationOnboarder {
        guard let noiseKeys = MainAppContext.shared.userData.loggedOutNoiseKeys else {
            // Fatal error... we can't register without keys
            fatalError("RootViewController/makeRegistrationManager/error [no-noise-keys]")
        }

        let noiseService = NoiseRegistrationService(noiseKeys: noiseKeys)
        return RegistrationOnboarder(registrationService: noiseService)
    }

    private func makeOnboardingViewController() -> UIViewController {
        guard let viewController = makeOnboarder().nextViewController() else {
            fatalError("RootViewController/makeOnboardingViewController/could not get view controller")
        }

        return viewController
    }

    @objc
    private func didTapCallBar() {
        delegate?.didTapCallBar()
    }
}

final class CallBar: UIControl {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    weak var call: Call? {
        didSet {
            update(with: call)
        }
    }

    func updateCallDuration(seconds: Int) {
        durationLabel.text = durationString(seconds: seconds)
    }

    // MARK: Private

    private let phoneIcon = UIImageView(image: UIImage(systemName: "phone.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal))
    private let titleLabel = UILabel()
    private let durationLabel = UILabel()

    private lazy var titleView: UIView = {

        phoneIcon.translatesAutoresizingMaskIntoConstraints = false
        phoneIcon.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(forTextStyle: .callout)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.addSubview(phoneIcon)
        view.addSubview(titleLabel)

        phoneIcon.constrain([.top, .bottom, .leading], to: view)

        titleLabel.constrain([.top, .bottom, .trailing], to: view)
        titleLabel.leadingAnchor.constraint(equalTo: phoneIcon.trailingAnchor, constant: 8).isActive = true
        return view
    }()

    private func commonInit() {
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .systemFont(forTextStyle: .body)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right

        addSubview(titleView)
        addSubview(durationLabel)

        titleView.constrainMargins([.top, .bottom, .leading], to: self, priority: .ifPossible)
        titleView.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: 8).isActive = true
        titleView.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true
        durationLabel.constrainMargins([.top, .bottom, .trailing], to: self, priority: .ifPossible)
    }

    private func update(with call: Call?) {
        guard call != nil else {
            titleLabel.text = nil
            durationLabel.text = nil
            return
        }
        titleLabel.text = Localizations.tapToReturnToCall
        durationLabel.text = nil
    }

    private func durationString(seconds : Int) -> String {
        let ss = (seconds % 3600) % 60
        let mm = (seconds % 3600) / 60
        let hh = seconds / 3600
        if hh > 0 {
            return String(format: "%02d:%02d:%02d", hh, mm, ss)
        } else {
            return String(format: "%02d:%02d", mm, ss)
        }
    }
}

private extension Localizations {
    static var tapToReturnToCall: String {
        NSLocalizedString("tap.return.call", value: "tap to return to call", comment: "Label for call bar (shows at top of screen during active call). Returns user to call screen when tapped.")
    }
}

private extension UILayoutPriority {
    static var ifPossible: UILayoutPriority {
        return UILayoutPriority(rawValue: 999)
    }
}
