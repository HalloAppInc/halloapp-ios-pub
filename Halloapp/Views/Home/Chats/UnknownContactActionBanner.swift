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
    var blockAction: (() -> ()) = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        addSubview(mainView)
        mainView.constrain(to: self)
    }

    private lazy var mainView: UIStackView = {
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        let bottomSpacer = UIView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ topSpacer, acceptToMessageBubble, blockBubble, bottomSpacer ])
        view.axis = .vertical
        view.alignment = .fill
        view.spacing = 15

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 155).isActive = true

        return view
    }()

    private lazy var acceptToMessageBubble: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ acceptToMessageLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.chatOwnBubbleBg
        view.layer.cornerRadius = 30

        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAcceptAction)))

        return view
    }()

    private lazy var acceptToMessageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .systemFont(ofSize: 20)
        label.textColor = .primaryBlue

        label.text = Localizations.unknownContactAcceptToMessage

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
    
    @objc private func tapBlockAction() {
        blockAction()
    }
}

private extension Localizations {

    static var unknownContactAcceptToMessage: String {
        NSLocalizedString("unknown.contact.accept.to.message", value: "Accept Message To Reply", comment: "Text for action label that lets the user accept messages from unknown contacts")
    }

}
