//
//  AudioRecorderTimeView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class AudioRecorderTimeView: UILabel {

    override var isHidden: Bool {
        didSet {
            guard oldValue != isHidden else { return }
            guard !isHidden else { return }

            animate()
        }
    }

    private lazy var dot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .lavaOrange
        view.layer.cornerRadius = 5
        view.layer.masksToBounds = true

        view.widthAnchor.constraint(equalToConstant: 10).isActive = true
        view.heightAnchor.constraint(equalToConstant: 10).isActive = true

        return view
    }()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        font = .systemFont(ofSize: 21)
        textColor = .lavaOrange
        textAlignment = .left
        backgroundColor = .clear
        isHidden = true

        widthAnchor.constraint(equalToConstant: 80).isActive = true
        heightAnchor.constraint(equalToConstant: 33).isActive = true

        addSubview(dot)
        dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -14).isActive = true
        dot.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    private func animate() {
        alpha = 0.0
        dot.alpha = 1.0

        UIView.animate(withDuration: 0.8, animations: {
            self.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .autoreverse, .repeat], animations: { [weak self] in
                self?.dot.alpha = 0
            }, completion: nil)
        }
    }

}
