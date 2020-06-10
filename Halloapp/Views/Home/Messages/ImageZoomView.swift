//
//  HalloApp
//
//  Created by Tony Jiang on 5/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import UIKit
import Core

class ImageZoomView: UIView, UIScrollViewDelegate {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func setup() {
        Log.d("Chat/imagezoomview/setup")

        self.addSubview(mainColumn)
        self.mainColumn.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        self.mainColumn.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.mainColumn.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.mainColumn.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        
        self.scrollView.addSubview(self.imageView)

        self.imageView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor).isActive = true
        self.imageView.heightAnchor.constraint(equalTo: self.scrollView.heightAnchor).isActive = true
    }

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.minimumZoomScale = 1.0
        view.maximumZoomScale = 2.0
        view.delegate = self
        return view
    }()
    
    private lazy var mainColumn: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.scrollView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    func update(with image: UIImage) {
        self.imageView.image = image
    }
    
    // MARK: UIScrollView Delegates
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
