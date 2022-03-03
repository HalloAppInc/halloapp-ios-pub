//
//  InitializingViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/7/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit

final class InitializingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground
        view.layoutMargins = UIEdgeInsets(top: 16, left: 80, bottom: 16, right: 80)

        progressBackground.addSubview(progressBar)

        progressBackground.translatesAutoresizingMaskIntoConstraints = false
        progressBackground.heightAnchor.constraint(equalToConstant: 5).isActive = true
        progressBackground.backgroundColor = .primaryWhiteBlack
        progressBackground.alpha = 0

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.backgroundColor = .systemBlue

        titleLabel.alpha = 0

        let stackView = UIStackView(arrangedSubviews: [titleLabel, progressBackground])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 32
        view.addSubview(stackView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        titleLabel.constrain([.centerY], to: view)

        progressBar.constrain([.top, .leading, .bottom], to: progressBackground)
        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true

        cancellableSet.insert(
            MainAppContext.shared.syncManager.syncProgress.sink { [weak self] progress in
                DispatchQueue.main.async {
                    self?.updateSyncProgress(progress)
                }
            }
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestPermissions()
    }

    private var cancellableSet: Set<AnyCancellable> = []

    private let titleLabel = makeLabel(text: Localizations.settingUpHalloApp, textColor: .label)
    private let progressBackground = UIView()
    private let progressBar = UIView()
    private var progressWidthConstraint: NSLayoutConstraint?

    private var syncStart: Date?

    static func makeLabel(text: String, textColor: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = textColor
        label.font = .preferredFont(forTextStyle: .callout)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func updateProgressVisibility() {
        guard let syncStart = syncStart else {
            DDLogInfo("InitializingViewController/updateProgressVisibility/startTimer")
            self.syncStart = Date()
            return
        }

        if progressBackground.alpha == 0 && Date() > syncStart.addingTimeInterval(3) {
            DDLogInfo("InitializingViewController/updateProgressVisibility/revealing")
            UIView.animate(withDuration: 0.5) {
                self.progressBackground.alpha = 1
                self.titleLabel.alpha = 1
            }
        }
    }

    private func updateSyncProgress(_ syncProgress: Double) {
        // Allocate 25% of the bar for loading contacts
        let displayRatio = CGFloat(syncProgress == 0 ? 0 : 0.25 + 0.75 * syncProgress)

        guard displayRatio >= 0 && displayRatio <= 1 else {
            // Don't clamp, just bail out of update if the progress value doesn't make sense.
            return
        }

        progressWidthConstraint?.isActive = false
        progressWidthConstraint = progressBar.widthAnchor.constraint(equalTo: progressBackground.widthAnchor, multiplier: displayRatio)
        progressWidthConstraint?.isActive = true

        updateProgressVisibility()
    }

    private func requestPermissions() {
        guard ContactStore.contactsAccessRequestNecessary else {
            DDLogInfo("InitializingViewController/requestPermissions/skipping [reloading contacts to trigger sync]")
            // TODO: Automatically trigger contact sync if needed instead of waiting for UI to reload contacts
            MainAppContext.shared.contactStore.reloadContactsIfNecessary()
            return
        }
        DDLogInfo("InitializingViewController/requestPermissions/begin")

        let alert = UIAlertController(title: Localizations.registrationContactPermissionsTitle, message: Localizations.registrationContactPermissionsContent, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonNext, style: .default, handler: { _ in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
                DDLogError("InitializingViewController/requestPermissions/error app delegate unavailable")
                return
            }
            appDelegate.requestAccessToContactsAndNotifications()
        }))
        present(alert, animated: true, completion: nil)
    }
}

extension Localizations {
    static var settingUpHalloApp: String {
        NSLocalizedString("setting.up.halloapp", value: "Setting up HalloApp", comment: "Displayed while syncing account immediately after registration")
    }
}
