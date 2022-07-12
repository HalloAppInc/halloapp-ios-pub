//
//  ShadowView.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 12.07.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class ShadowView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
}
