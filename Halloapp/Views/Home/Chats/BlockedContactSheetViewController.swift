//
//  BlockedContactSheetViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//
import UIKit
import Core
import CoreCommon

class BlockedContactSheetViewController: UIViewController, UIViewControllerTransitioningDelegate {
    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [summaryLabel, unblockButton, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = .primaryBg
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 27, bottom: 0, right: 27)
        
        stack.setCustomSpacing(20, after: summaryLabel)
        stack.setCustomSpacing(15, after: unblockButton)
        
        return stack
    }()
    
    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.text = Localizations.contactIsBlockedTitleLabel
        
        return label
    }()
    
    private lazy var unblockButton: UIButton = {
        var unlockButtonConfiguration: UIButton.Configuration = .filledCapsule(backgroundColor: .primaryBlue)
        unlockButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20)
        unlockButtonConfiguration.attributedTitle = AttributedString(Localizations.unBlockButton,
                                                                     attributes: .init([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        let button = UIButton()
        button.configuration = unlockButtonConfiguration
        button.addTarget(self, action: #selector(pushedUnblock), for: .touchUpInside)
        
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizations.buttonCancel, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(pushedCancel), for: .touchUpInside)
        button.setTitleColor(.systemBlue, for: .normal)
        
        return button
    }()
    
    var unblockAction: (() -> Void)?
    var cancelAction: (() -> Void)?
    
    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalTransitionStyle = .coverVertical
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("Blocked contact sheet required init not implemented...")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: view.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return ContactSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: - button selectors
extension BlockedContactSheetViewController {
    @objc
    private func pushedUnblock(_ button: UIButton) {
        unblockAction?()
    }

    @objc
    private func pushedCancel(_ button: UIButton) {
        cancelAction?()
    }
}
