//
//  TempCollectionView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 11/4/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class TempCollectionView: UICollectionView {
    var oldie:CGPoint = CGPoint(x: 0, y: 0)
    override var contentOffset: CGPoint {
        willSet {
            print("Nandini willset : \(oldie.y) \(newValue.y)")
        }

        didSet {
            print("Nandini didset : \(oldValue.y) to: \(contentOffset.y)")
            oldie = contentOffset
        }
    }
}
