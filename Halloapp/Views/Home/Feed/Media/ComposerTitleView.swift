//
//  ComposerTitleView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/13/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class ComposerTitleView: UIView {

    enum Alignment {
        case leading, center
    }

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.9)

        return titleLabel
    }()

    private let subtitleLabel: UILabel = {
        let subtitleLabel = UILabel()
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.minimumScaleFactor = 0.5
        subtitleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.35)
        return subtitleLabel
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 2
        return stackView
    }()

    var alignment: Alignment = .center {
        didSet {
            if oldValue != alignment {
                updateAlignment()
            }
        }
    }

    var title: String? {
        didSet {
            titleLabel.text = title
            titleLabel.isHidden = title?.isEmpty ?? true
        }
    }

    var subtitle: String? {
        didSet {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }


    private func commonInit() {
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        stackView.constrain(to: self)

        updateAlignment()
    }

    private func updateAlignment() {
        switch alignment {
        case .leading:
            stackView.alignment = .leading
        case .center:
            stackView.alignment = .center
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        switch alignment {
        case .center:
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        case .leading:
            return CGSize(width: .greatestFiniteMagnitude, height: UIView.noIntrinsicMetric)
        }
    }
}
