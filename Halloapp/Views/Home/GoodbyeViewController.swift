//
//  GoodbyeViewController.swift
//  HalloApp
//
//  Created by Garrett on 3/27/24.
//  Copyright © 2024 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

final class GoodbyeViewController: UIViewController {
    lazy var logo: UIView = {
        let view = UIImageView(image: UIImage(named: "AppIconBig")?.fastResized(to: CGSize(width: 50, height: 50)))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .feedBackground
        view.contentMode = .center
        view.heightAnchor.constraint(equalToConstant: 100).isActive = true
        view.widthAnchor.constraint(equalToConstant: 100).isActive = true
        view.layer.cornerRadius = 50
        view.clipsToBounds = true
        return view
    }()

    lazy var messageView: UIView = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = Localizations.goodbyeMessage
        label.font = .systemFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }()

    lazy var titleView: UIView = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = Localizations.goodbyeTitle
        label.font = .gothamFont(forTextStyle: .title1, weight: .medium)
        return label
    }()

    lazy var okButton: UIButton = {
        let button = UIButton(type: .system)
        button.configuration = .filledCapsule(backgroundColor: .primaryBlue)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Localizations.buttonOK, for: .normal)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        let stackView = UIStackView(arrangedSubviews: [
            logo,
            titleView,
            messageView,
            okButton,
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        stackView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40).isActive = true
        stackView.constrain([.centerX, .centerY], to: view)
    }
}

extension Localizations {

    static var goodbyeTitle: String {
        NSLocalizedString("goodbye.title",
                   value: "This is Goodbye, For Now",
                 comment: "Title on goodbye screen")
    }

    static var goodbyeMessage: String {
        let paragraphs = [
            NSLocalizedString("goodbye.message.1",
                       value: "All things come to an end, even the good ones. It’s been our absolute privilege to provide HalloApp service to you guys.",
                     comment: "First paragraph on goodbye screen"),
            NSLocalizedString("goodbye.message.2",
                       value: "Unfortunately, not all things can last forever. So we’ll have to stop the support of HalloApp after April 15th.",
                     comment: "Second paragraph on goodbye screen"),
            NSLocalizedString("goodbye.message.3",
                       value: "If you would like, you can download the media from your posts under Profile > My Posts.",
                     comment: "Third paragraph on goodbye screen"),
            NSLocalizedString("goodbye.message.4",
                       value: "Wishing you all the best, HalloApp Team.",
                     comment: "Fourth paragraph on goodbye screen"),
        ]
        return paragraphs.joined(separator: "\n\n")
    }
}
