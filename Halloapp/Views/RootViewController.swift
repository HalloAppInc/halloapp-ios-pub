//
//  RootViewController.swift
//  HalloApp
//
//  Created by Garrett on 12/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

enum UserInterfaceState {
    case expiredVersion
    case initializing
    case registration
    case mainInterface
}

protocol RootViewControllerDelegate: AnyObject {
    func didTapCallBar()
}

final class RootViewController: UIViewController {

    var callBar = CallBar()
    var callBarHeightConstraint: NSLayoutConstraint?
    var callViewController: CallViewController?

    var primaryViewContainer = UIView()
    var primaryViewController = UIViewController()

    var state: UserInterfaceState = .initializing
    weak var delegate: RootViewControllerDelegate?

    override func viewDidLoad() {
        view.addSubview(callBar)
        view.addSubview(primaryViewContainer)

        callBar.backgroundColor = .lavaOrange
        callBar.translatesAutoresizingMaskIntoConstraints = false
        callBar.constrain([.top, .leading, .trailing], to: view)
        callBar.addTarget(self, action: #selector(didTapCallBar), for: .touchUpInside)

        callBarHeightConstraint = callBar.heightAnchor.constraint(equalToConstant: 0)
        callBarHeightConstraint?.isActive = true

        primaryViewContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryViewContainer.constrain([.leading, .trailing, .bottom], to: view)

        callBar.bottomAnchor.constraint(equalTo: primaryViewContainer.topAnchor).isActive = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait]
    }

    func transition(to newState: UserInterfaceState) {
        guard newState != state else { return }
        DDLogInfo("RootViewController/transition [\(newState)]")
        state = newState

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

    private func updateCallBarVisibility(_ isVisible: Bool, animated: Bool) {
        let barHeight: CGFloat = isVisible ? 80 : 0
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.callBarHeightConstraint?.constant = barHeight
            self.view.layoutIfNeeded()
        }
    }

    private func viewController(forUserInterfaceState state: UserInterfaceState) -> UIViewController {
        switch state {
        case .initializing:
            return InitializingViewController()

        case .registration:
            return VerificationViewController(registrationManager: makeRegistrationManager())

        case .mainInterface:
            return HomeViewController()

        case .expiredVersion:
            return ExpiredVersionViewController()
        }
    }

    private func makeRegistrationManager() -> RegistrationManager {
        // TODO: Move this to AppContext
        guard let noiseKeys = MainAppContext.shared.userData.loggedOutNoiseKeys else {
            // Fatal error... we can't register without keys
            fatalError("RootViewController/makeRegistrationManager/error [no-noise-keys]")
        }
        let noiseService = NoiseRegistrationService(noiseKeys: noiseKeys)
        return DefaultRegistrationManager(registrationService: noiseService)
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

    var call: Call? {
        didSet {
            update(with: call)
        }
    }

    func updateCallDuration(seconds: Int) {
        durationLabel.text = durationString(seconds: seconds)
    }

    // MARK: Private

    private let phoneIcon = UIImageView(image: UIImage(systemName: "phone.circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal))
    private let nameLabel = UILabel()
    private let durationLabel = UILabel()

    private func commonInit() {
        phoneIcon.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(forTextStyle: .body, weight: .bold)
        nameLabel.textColor = .white

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .systemFont(forTextStyle: .body)
        durationLabel.textColor = .white

        addSubview(nameLabel)
        addSubview(durationLabel)
        addSubview(phoneIcon)

        phoneIcon.constrainMargins([.top, .bottom, .leading], to: self)
        phoneIcon.heightAnchor.constraint(equalTo: phoneIcon.widthAnchor).isActive = true

        nameLabel.constrainMargins([.top, .bottom], to: self)
        nameLabel.leadingAnchor.constraint(equalTo: phoneIcon.trailingAnchor, constant: 8).isActive = true

        durationLabel.constrainMargins([.top, .bottom, .trailing], to: self)
        durationLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8).isActive = true
    }

    private func update(with call: Call?) {
        guard let call = call else {
            nameLabel.text = nil
            durationLabel.text = nil
            return
        }
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: call.peerUserID)
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
