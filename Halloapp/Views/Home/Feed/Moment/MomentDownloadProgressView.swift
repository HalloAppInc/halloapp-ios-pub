//
//  MomentDownloadProgressView.swift
//  HalloApp
//
//  Created by Tanveer on 10/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class MomentDownloadProgressView: UIView {

    private static var indicatorSize: CGFloat {
        30
    }

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "icon_fab_moment")?.withRenderingMode(.alwaysTemplate)
        view.tintColor = .white.withAlphaComponent(0.9)
        view.contentMode = .center
        return view
    }()

    private lazy var progressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.lineWidth = 3
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.strokeEnd = 0
        layer.transform = CATransform3DRotate(layer.transform, -.pi / 2, 0, 0, 1)
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.addSublayer(progressLayer)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.indicatorSize),
            imageView.heightAnchor.constraint(equalToConstant: Self.indicatorSize),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("MomentDownloadProgressView coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        progressLayer.frame = imageView.frame.insetBy(dx: -6, dy: -6)
        progressLayer.path = UIBezierPath(ovalIn: progressLayer.bounds).cgPath
    }

    func set(progress: Float) {
        let progress = CGFloat(progress)
        let animation = CABasicAnimation(keyPath: "strokeEnd")

        animation.fromValue = progressLayer.strokeEnd
        animation.toValue = progress
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        progressLayer.add(animation, forKey: nil)
        progressLayer.strokeEnd = progress
    }
}
