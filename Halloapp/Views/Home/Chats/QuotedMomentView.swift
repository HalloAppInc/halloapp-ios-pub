//
//  QuotedMomentView.swift
//  HalloApp
//
//  Created by Tanveer on 5/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core

class QuotedMomentView: UIView {
    private static let cornerRadius: CGFloat = 7
    private static let imageCornerRadius: CGFloat = 5

    static var expiredIndicator: UIImage? {
        UIImage(systemName: "timelapse")
    }

    private(set) lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black.withAlphaComponent(0.75)
        view.layer.masksToBounds = true
        view.layer.cornerRadius = Self.imageCornerRadius
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        view.contentMode = .center
        view.tintColor = .white.withAlphaComponent(0.9)
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .feedPostBackground
        layer.cornerRadius = Self.cornerRadius

        layer.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 1
        layer.shadowOffset = .init(width: 0, height: 1)

        addSubview(imageView)
        let padding: CGFloat = 5
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding * 2),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("QuotedMomentView coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath
    }
}
