//
//  UITabBarController.swift
//  HalloApp
//
//  Created by Tony Jiang on 5/18/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit

extension UITabBarController {

    func hideTabBar(vc: UIViewController) {
        DispatchQueue.main.async {
            guard vc.view.window != nil else { return }
            guard let frame = vc.tabBarController?.tabBar.frame else { return }
            UIView.animate(withDuration: 0.2, animations: {
                vc.tabBarController?.tabBar.frame = CGRect(x: frame.origin.x, y: frame.origin.y + frame.height, width: frame.width, height: frame.height)
            }, completion: { _ in
                // put frame back to its original position so it won't affect other views
                vc.tabBarController?.tabBar.isHidden = true
                vc.tabBarController?.tabBar.frame = UITabBarController().tabBar.frame
            })
        }
    }

}
