//
//  MigrationViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/28/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

class MigrationViewController: UIViewController {

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        return activityIndicator
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        let stackView = UIStackView()
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        // TODO: Get correct size image
        let logoImageView = UIImageView(image: UIImage(named: "AppIconBig"))
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(logoImageView)
        stackView.setCustomSpacing(40, after: logoImageView)

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.text = Localizations.migrationInProgress
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(label)
        stackView.setCustomSpacing(20, after: label)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(activityIndicator)

        let topLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(topLayoutGuide)

        let bottomLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(bottomLayoutGuide)

        let verticalPostitionConstraint = NSLayoutConstraint(item: topLayoutGuide,
                                                             attribute: .height,
                                                             relatedBy: .equal,
                                                             toItem: bottomLayoutGuide,
                                                             attribute: .height,
                                                             multiplier: 0.5,
                                                             constant: 0)
        verticalPostitionConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            verticalPostitionConstraint,
            topLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            topLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topLayoutGuide.bottomAnchor.constraint(equalTo: stackView.topAnchor),
            topLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomLayoutGuide.topAnchor.constraint(equalTo: stackView.bottomAnchor),
            bottomLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // TODO: remove with correct size image
            logoImageView.widthAnchor.constraint(equalToConstant: 120),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        activityIndicator.startAnimating()
    }
}

extension Localizations {

    static var migrationInProgress: String {
        NSLocalizedString("migration.inProgress",
                          value: "Optimizing Data…",
                          comment: "Text on loading screen while migrating data")
    }
}
