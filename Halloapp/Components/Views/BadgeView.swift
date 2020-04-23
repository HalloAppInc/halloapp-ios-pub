//
//  BadgeView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

class BadgeView: PillView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private let label: UILabel = UILabel()

    private func setupView() {
        self.layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        self.fillColor = .systemRed
        self.label.textColor = .white
        self.label.textAlignment = .center
        self.label.font = .preferredFont(forTextStyle: .footnote)
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        self.label.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        self.label.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.label.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.label.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
        self.widthAnchor.constraint(greaterThanOrEqualTo: self.heightAnchor).isActive = true
    }

    // MARK: Public

    public var text: String? {
        get { self.label.text }
        set { self.label.text = newValue }
    }

    public var font: UIFont! {
        get { self.label.font }
        set { self.label.font = newValue }
    }

    public var textColor: UIColor! {
        get { self.label.textColor }
        set { self.label.textColor = newValue }
    }

    override var backgroundColor: UIColor? {
        get { self.fillColor }
        set { self.fillColor = newValue }
    }

}
