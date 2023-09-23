//
//  OnboardingFriendsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

class OnboardingFriendsViewController: SegmentedFriendsViewController {

    private let onboarder: any Onboarder

    init(onboarder: any Onboarder) {
        self.onboarder = onboarder
        super.init(initialState: .friends)
    }

    required init(coder: NSCoder) {
        fatalError("OnboardingFriendsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(false, animated: false)

        let barButton = UIBarButtonItem(systemItem: .done, primaryAction: .init { [weak self] action in
            guard let self else {
                return
            }

            if let viewController = self.onboarder.nextViewController() {
                self.navigationController?.pushViewController(viewController, animated: true)
            }
        })

        navigationItem.leftBarButtonItem = barButton
    }
}
