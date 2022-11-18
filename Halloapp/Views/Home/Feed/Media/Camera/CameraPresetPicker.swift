//
//  CameraPresetPicker.swift
//  HalloApp
//
//  Created by Tanveer on 11/4/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class CameraPresetPicker: UIView, CameraPresetConfigurable {

    private lazy var presetViews: [CameraPresetView] = []
    private var selectedPresetConstraint: NSLayoutConstraint?

    var onSelection: ((CameraPreset) -> Void)?

    init(presets: [CameraPreset]) {
        super.init(frame: .zero)
        insert(presets: presets)
    }

    required init?(coder: NSCoder) {
        fatalError("CameraPresetPicker coder init not implemented...")
    }

    private func insert(presets: [CameraPreset]) {
        var previous: CameraPresetView?
        var constraints = [NSLayoutConstraint]()

        for preset in presets {
            let view = CameraPresetView(preset: preset)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            presetViews.append(view)

            constraints.append(contentsOf: [
                view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])

            if let previous {
                constraints.append(view.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 12))
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
            view.addGestureRecognizer(tap)

            previous = view
        }

        NSLayoutConstraint.activate(constraints)
    }

    func set(preset: CameraPreset, animator: UIViewPropertyAnimator?) {
        guard let presetView = presetViews.first(where: { $0.preset == preset }) else {
            return
        }

        func updates() {
            for view in self.presetViews {
                view.label.textColor = .secondaryLabel
            }

            presetView.label.textColor = .white
            self.layoutIfNeeded()
        }

        selectedPresetConstraint?.isActive = false
        selectedPresetConstraint = presetView.centerXAnchor.constraint(equalTo: centerXAnchor)
        selectedPresetConstraint?.isActive = true

        animator?.addAnimations {
            updates()
        }

        if animator == nil {
            updates()
        }
    }

    @objc
    private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        if let preset = (gesture.view as? CameraPresetView)?.preset {
            onSelection?(preset)
        }
    }
}

fileprivate class CameraPresetView: UIView {

    let preset: CameraPreset

    private(set) lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        return label
    }()

    init(preset: CameraPreset) {
        self.preset = preset
        super.init(frame: .zero)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        label.text = preset.name.uppercased()
    }

    required init?(coder: NSCoder) {
        fatalError("CameraPresetView coder init not implemented...")
    }
}
