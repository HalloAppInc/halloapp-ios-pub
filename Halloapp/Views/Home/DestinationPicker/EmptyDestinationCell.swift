//
//  EmptyDestinationCell.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/26/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class EmptyDestinationCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: EmptyDestinationCell.self)
    }

    private var imageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "person.2")?.withTintColor(.black.withAlphaComponent(0.3), renderingMode: .alwaysOriginal))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private(set) lazy var separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator

        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
