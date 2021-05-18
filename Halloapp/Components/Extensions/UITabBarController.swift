//
//  UITabBarController.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/18/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit

extension UITabBarController {

    func hideTabBar() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let frame = self.tabBar.frame
            UIView.animate(withDuration: 0.2, animations: {
                self.tabBar.frame = CGRect(x: frame.origin.x, y: frame.origin.y + frame.height, width: frame.width, height: frame.height)
            }, completion: { _ in
                // put frame back to its original position so it won't affect other views
                self.tabBar.isHidden = true
                self.tabBar.frame = UITabBarController().tabBar.frame
            })
        }
    }
}
