//
//  HalloApp
//
//  Created by Tony Jiang on 7/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class UnknownContactActionBanner: UIView {

    var acceptAction: (() -> ()) = {}
    var addToContactBookAction: (() -> ()) = {}
    var blockAction: (() -> ()) = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        addSubview(mainView)
        mainView.constrain(to: self)
        mainView.backgroundColor = .primaryBg
    }

    private lazy var mainView: UIStackView = {
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        let bottomSpacer = UIView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ topSpacer, userNotInContactBookTextBubble, acceptToMessageBubble, addToContactBookButton, blockBubble, bottomSpacer ])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 15

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 265).isActive = true

        return view
    }()

    private lazy var userNotInContactBookTextBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ userNotInContactBookLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.clear

        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAcceptAction)))

        return view
    }()

    private lazy var userNotInContactBookLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label

        label.text = Localizations.unknownContactNotInContactBook

        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var acceptToMessageBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ acceptToMessageLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.primaryBlue
        view.layer.cornerRadius = 25

        view.layoutMargins = UIEdgeInsets(top: 10, left: 50, bottom: 13, right: 50)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 232).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAcceptAction)))

        return view
    }()

    private lazy var acceptToMessageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 17)
        label.textColor = .primaryWhiteBlack

        label.text = Localizations.unknownContactAcceptToMessage

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var addToContactBookButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ addToContactBookLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.primaryWhiteBlack
        view.layer.cornerRadius = 25

        view.layoutMargins = UIEdgeInsets(top: 10, left: 5, bottom: 13, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 232).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAddToContactBookAction)))

        return view
    }()

    private lazy var addToContactBookLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 17)
        label.textColor = .primaryBlue

        label.text = Localizations.addToContactBook

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var blockBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ blockLabel ])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapBlockAction)))

        return view
    }()

    private lazy var blockLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 20)
        label.textColor = .red

        label.text = Localizations.blockButton

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    // MARK: Actions

    @objc private func tapAcceptAction() {
        acceptAction()
    }

    @objc private func tapAddToContactBookAction() {
        addToContactBookAction()
    }

    @objc private func tapBlockAction() {
        blockAction()
    }
}

private extension Localizations {

    static var unknownContactNotInContactBook: String {
        NSLocalizedString("unknown.contact.not.in.contact.book", value: "This sender is not in your contact book.", comment: "Informational label that's shown in the banner for an unknown contact when they message the user for the first time")
    }
    
    static var unknownContactAcceptToMessage: String {
        NSLocalizedString("unknown.contact.accept.to.message", value: "Accept Message", comment: "Text for action label that lets the user accept messages from unknown contacts")
    }

}
