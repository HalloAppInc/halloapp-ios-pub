//
//  DestinationBackgroundDecorationView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class DestinationBackgroundDecorationView: UICollectionReusableView {
    public static var elementKind: String {
        return String(describing: DestinationBackgroundDecorationView.self)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feedPostBackground
        layer.cornerRadius = 10
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
