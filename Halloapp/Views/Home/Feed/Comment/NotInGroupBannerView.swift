//
//  NotInGroupBanner.swift
//  HalloApp
//
//  Created by Tony Jiang on 2/23/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class NotInGroupBannerView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        addSubview(notInGroupBanner)
        notInGroupBanner.constrain(to: self)
    }
    
    private lazy var notInGroupBanner: UIStackView = {
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        let bottomSapacer = UIView()
        bottomSapacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ topSpacer, notInGroupLabelBox, bottomSapacer ])
        view.axis = .vertical
        view.alignment = .fill
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 100).isActive = true

        return view
    }()
    
    
    private lazy var notInGroupLabelBox: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ notInGroupLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.searchBarBg.withAlphaComponent(0.95)
        view.layer.cornerRadius = 25

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        return view
    }()
    
    private lazy var notInGroupLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.backgroundColor = .clear
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        
        label.text = Localizations.notInGroupBannerText
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
}

private extension Localizations {

    static var notInGroupBannerText: String {
        NSLocalizedString("not.in.group.banner.text", value: "You're no longer in this group", comment: "Text shown to indicate user is not in the group anymore")
    }

}
