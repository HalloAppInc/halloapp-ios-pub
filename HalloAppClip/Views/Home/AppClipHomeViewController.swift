//
//  HomeViewController.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/10/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjack
import Combine
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 30
}

class AppClipHomeViewController: UIViewController {
    let logo = UIImageView()
    var inputVerticalCenterConstraint: NSLayoutConstraint?

    let scrollView = UIScrollView()
    var scrollViewBottomMargin: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        navigationItem.backButtonTitle = ""

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        let welcomeLabel = UILabel()
        welcomeLabel.text = "Welcome"
        welcomeLabel.font = .systemFont(forTextStyle: .title1, weight: .medium, maximumPointSize: Constants.MaxFontPointSize)

        let stackView = UIStackView(arrangedSubviews: [welcomeLabel])
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .feedBackground

        // View hierarchy
        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)

        view.addSubview(scrollView)

        // Constraints
        scrollView.constrain([.leading, .trailing, .top], to: view)
        scrollViewBottomMargin = scrollView.constrain(anchor: .bottom, to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 100)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 32).isActive = true
        inputVerticalCenterConstraint = stackView.constrain(anchor: .centerY, to: scrollView, priority: .defaultHigh)

    }
}
