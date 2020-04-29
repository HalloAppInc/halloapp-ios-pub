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
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private let innerCircle: CircleView = {
        let innerCircle = CircleView()
        innerCircle.fillColor = .white
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        return innerCircle
    }()

    private func setupView() {
        self.layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        self.fillColor = .systemGreen

        self.addSubview(self.innerCircle)
        self.innerCircle.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        self.innerCircle.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.innerCircle.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.innerCircle.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    // MARK: Public

    override var backgroundColor: UIColor? {
        get { self.fillColor }
        set { self.fillColor = newValue }
    }

}
