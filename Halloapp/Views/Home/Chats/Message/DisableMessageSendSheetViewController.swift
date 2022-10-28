//
//  DisableMessageSendSheetViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

class DisableMessageSendSheetViewController: UIViewController, UIViewControllerTransitioningDelegate {

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [summaryLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = .primaryBg
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 27, bottom: 0, right: 27)
        
        return stack
    }()

    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.text = Localizations.nonMemberLabel
        
        return label
    }()

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
