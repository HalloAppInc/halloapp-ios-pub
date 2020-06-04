//
//  ContactTableViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

class ContactTableViewCell: UITableViewCell {
    var userId: UserID? {
        didSet {
            reloadContactData()
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.textLabel?.font = .preferredFont(forTextStyle: .body)
    }

    private func reloadContactData() {
        // TODO: contact picture
    }
}
