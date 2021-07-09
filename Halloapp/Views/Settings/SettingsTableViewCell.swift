//
//  SettingsTableViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import UIKit

class SettingsTableViewCell: UITableViewCell {

    init(text: String, image: UIImage? = nil) {
        super.init(style: .default, reuseIdentifier: nil)
        textLabel?.text = text
        if let image = image {
            imageView?.image = image
            imageView?.tintColor = .lavaOrange
        }
        separatorInset = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
