//
//  DestinationPickerMoreView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol DestinationPickerMoreViewDelegate: AnyObject {
    func moreAction(_ view: DestinationPickerMoreView)
}

class DestinationPickerMoreView: UICollectionReusableView {
    static var elementKind: String {
        return String(describing: DestinationPickerMoreView.self)
    }

    weak var delegate: DestinationPickerMoreViewDelegate?

    private lazy var moreButton: UIButton = {
        let moreButton = UIButton()
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setTitle(Localizations.showMore, for: .normal)
        moreButton.setTitleColor(.primaryBlue, for: .normal)
        moreButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        moreButton.addTarget(self, action: #selector(moreAction), for: .touchUpInside)
        return moreButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(moreButton)
        NSLayoutConstraint.activate([
            moreButton.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            moreButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            moreButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func moreAction() {
        delegate?.moreAction(self)
    }
}
