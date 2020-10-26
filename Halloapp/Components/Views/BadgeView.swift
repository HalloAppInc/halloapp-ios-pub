//
//  BadgeView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class BadgeView: CircleView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private let innerCircle: CircleView = {
        let innerCircle = CircleView()
        innerCircle.fillColor = .white
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        return innerCircle
    }()

    private func setupView() {
        layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        fillColor = .lavaOrange

        addSubview(innerCircle)
        innerCircle.constrainMargins(to: self)
    }

    // MARK: Public

    override var backgroundColor: UIColor? {
        get { fillColor }
        set { fillColor = newValue }
    }

}
