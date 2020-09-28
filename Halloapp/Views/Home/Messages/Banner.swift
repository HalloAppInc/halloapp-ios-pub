//
//  Banner.swift
//  HalloApp
//
//  Created by Tony Jiang on 9/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import UIKit

class Banner {
    static let animateDuration = 0.3
    static let bannerDuration: TimeInterval = 3
    
    static func show(title: String, body: String) {
        guard let superView = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        
        let width = superView.bounds.size.width
        let height: CGFloat = 120
        
        let bannerView = BannerView(frame: CGRect(x: 0, y: 0 - height, width: width, height: height))
        bannerView.configure(title: title, body: body)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        
        superView.addSubview(bannerView)
    
        bannerView.widthAnchor.constraint(equalToConstant: width).isActive = true
        bannerView.heightAnchor.constraint(equalToConstant: height).isActive = true
 
        let bannerTopConstraint = NSLayoutConstraint(item: bannerView, attribute: .top, relatedBy: .equal, toItem: superView, attribute: .top, multiplier: 1, constant: 0 - height)

        NSLayoutConstraint.activate([bannerTopConstraint])
        
        UIView.animate(withDuration: animateDuration) {
            bannerTopConstraint.constant = 0
            superView.layoutIfNeeded()
        }
        
        UIView.animate(withDuration: animateDuration, delay: bannerDuration, options: [], animations: {
            bannerTopConstraint.constant = 0 - bannerView.frame.height
            superView.layoutIfNeeded()
        }, completion: { finished in
            if finished {
                bannerView.removeFromSuperview()
            }
        })
    }
}


fileprivate class BannerView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configure(title: String, body: String) {
        titleLabel.text = title
        bodyLabel.text = body
    }
    
    private func setup() {
        
        backgroundColor = UIColor.systemGray
        
        addSubview(mainView)
    
        mainView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        mainView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    private lazy var mainView: UIStackView = {
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ spacer, titleRow, bodyRow ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 15, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.distribution = .equalCentering
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ titleLabel ])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 5, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let baseSubView = UIView(frame: view.bounds)
        baseSubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(baseSubView, at: 0)
        
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
      
        label.numberOfLines = 1
        label.font = UIFont.boldSystemFont(ofSize: 16.0)
        label.textColor = .label
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var bodyRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ bodyLabel ])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 10, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let baseSubView = UIView(frame: view.bounds)
        baseSubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(baseSubView, at: 0)
        
        return view
    }()
    
    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textColor = .label
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

}
