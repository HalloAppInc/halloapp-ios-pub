//
//  NewPostsIndicator.swift
//  HalloApp
//
//  Created by Tony Jiang on 2/25/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

final class NewPostsIndicator: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    private func setup() {
        addSubview(newPostsIndicator)
        newPostsIndicator.constrain(to: self)
    }
    
    private lazy var newPostsIndicator: UIStackView = {
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        let bottomSapacer = UIView()
        bottomSapacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ topSpacer, newPostsIndicatorLabelBox, bottomSapacer ])
        view.axis = .vertical
        view.alignment = .center
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    

    private lazy var newPostsIndicatorLabelBox: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ newPostsIndicatorLabel ])
        view.axis = .vertical
        view.alignment = .center
        view.backgroundColor = UIColor.label.withAlphaComponent(0.4)
        view.layer.cornerRadius = 25

        view.layoutMargins = UIEdgeInsets(top: 10, left: 30, bottom: 10, right: 30)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        return view
    }()
    
    private lazy var newPostsIndicatorLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.backgroundColor = .clear
        label.font = .systemFont(forTextStyle: .callout, weight: .semibold)
        label.textColor = .secondarySystemGroupedBackground
        
        label.text = Localizations.feedNewPostsIndicatorText
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
}

extension Localizations {
    static var feedNewPostsIndicatorText: String {
        return NSLocalizedString("feed.new.posts.indicator", value: "New Posts", comment: "Text shown in indicator when new posts come in while user is scrolled down")
    }
}

