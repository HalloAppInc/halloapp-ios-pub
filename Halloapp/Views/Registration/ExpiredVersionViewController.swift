//
//  ExpiredVersionViewController.swift
//  HalloApp
//
//  Created by Garrett on 2/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

final class ExpiredVersionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        updateButton.setTitle(Localizations.buttonUpdate, for: .normal)
        updateButton.setTitleColor(.systemBlue, for: .normal)
        updateButton.addTarget(self, action: #selector(didTapUpdate), for: .touchUpInside)
        updateButton.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [titleLabel, messageLabel, updateButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        view.addSubview(stackView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        messageLabel.constrain([.centerY], to: view)
    }

    private let titleLabel = makeLabel(text: Localizations.appUpdateNoticeTitle, textColor: .label)
    private let messageLabel = makeLabel(text: Localizations.appUpdateNoticeText, textColor: .secondaryLabel)
    private let updateButton = UIButton()

    static func makeLabel(text: String, textColor: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = textColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    @objc
    private func didTapUpdate() {
        guard let appStoreURL = AppContext.appStoreURL,
              UIApplication.shared.canOpenURL(appStoreURL) else
        {
            DDLogError("ExpiredVersionViewController/error opening App Store URL")
            return
        }

        DDLogInfo("ExpiredVersionViewController/opening App Store URL")
        UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
    }
}
