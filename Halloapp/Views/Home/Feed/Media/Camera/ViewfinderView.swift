//
//  ViewfinderView.swift
//  HalloApp
//
//  Created by Tanveer on 9/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import AVFoundation

protocol ViewfinderViewDelegate: AnyObject {
    func viewfinderDidToggleExpansion(_ view: ViewfinderView)
    func viewfinder(_ view: ViewfinderView, focusedOn point: CGPoint)
    func viewfinder(_ view: ViewfinderView, zoomedTo scale: CGFloat)
}

final class ViewfinderView: UIView {

    enum State { case split, full }
    var state: State = .full {
        didSet { refreshState() }
    }

    var hideToggle: Bool = true {
        didSet { refreshState() }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var cameraPosition: AVCaptureDevice.Position? {
        previewLayer.connection?.inputPorts.first?.sourceDevicePosition
    }

    private lazy var toggleButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.forward.circle.fill"), for: .normal)
        button.addTarget(self, action: #selector(toggleButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var focusIndicator: CircleView = {
        let diameter: CGFloat = 30
        let view = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
        view.fillColor = .clear
        view.lineWidth = 1.75
        view.strokeColor = .white
        view.alpha = 0
        return view
    }()

    private lazy var blurOverlay: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.effect = UIBlurEffect(style: .regular)
        return view
    }()

    private var hideFocusIndicator: DispatchWorkItem?
    weak var delegate: ViewfinderViewDelegate?

    private var connectionCancellable: AnyCancellable?
    private var placeholderSnapshot: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        addSubview(blurOverlay)
        addSubview(toggleButton)
        addSubview(focusIndicator)

        let padding: CGFloat = 10
        NSLayoutConstraint.activate([
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            toggleButton.topAnchor.constraint(equalTo: topAnchor, constant: padding),

            blurOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurOverlay.topAnchor.constraint(equalTo: topAnchor),
            blurOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(focusTap))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchToZoom))
        addGestureRecognizer(tap)
        addGestureRecognizer(pinch)

        connectionCancellable = previewLayer.publisher(for: \.connection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connection in
                self?.updateOverlay(with: connection)
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshState()
    }

    private func updateOverlay(with connection: AVCaptureConnection?) {
        if connection == nil {
            animateRemovedConnection()
        } else {
            animateAddedConnection()
        }
    }

    private func animateRemovedConnection() {
        guard let snapshot = snapshotView(afterScreenUpdates: false) else {
            return
        }

        snapshot.frame = bounds
        insertSubview(snapshot, belowSubview: blurOverlay)
        placeholderSnapshot = snapshot

        UIView.animate(withDuration: 0.3) {
            self.blurOverlay.effect = UIBlurEffect(style: .regular)
        }
    }

    private func animateAddedConnection() {
        UIView.animateKeyframes(withDuration: 0.3, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                self.placeholderSnapshot?.alpha = 0
            }

            UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.75) {
                self.blurOverlay.effect = nil
            }
        }
    }

    private func refreshState() {
        let transform: CGAffineTransform
        switch state {
        case .split:
            transform = .identity
        case .full:
            transform = CGAffineTransform(rotationAngle: .pi)
        }

        toggleButton.transform = transform
        toggleButton.isHidden = hideToggle
    }

    @objc
    private func toggleButtonPushed(_ button: UIButton) {
        delegate?.viewfinderDidToggleExpansion(self)
    }

    @objc
    private func focusTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let converted = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        showFocusIndicator(for: point)
        delegate?.viewfinder(self, focusedOn: converted)
    }

    private func showFocusIndicator(for point: CGPoint) {
        hideFocusIndicator?.cancel()

        focusIndicator.alpha = 0
        focusIndicator.center = point
        focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)

        UIView.animate(withDuration: 0.15,
                              delay: 0,
             usingSpringWithDamping: 0.7,
              initialSpringVelocity: 0.5,
                            options: [.allowUserInteraction])
        {
            self.focusIndicator.transform = .identity
            self.focusIndicator.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleFocusIndicatorHide()
        }
    }

    private func scheduleFocusIndicatorHide() {
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.15,
                                  delay: 0,
                 usingSpringWithDamping: 0.7,
                  initialSpringVelocity: 0.5,
                                options: [.allowUserInteraction])
            {
                self?.focusIndicator.alpha = 0
                self?.focusIndicator.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                self?.hideFocusIndicator = nil
            }
        }

        hideFocusIndicator = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    @objc
    private func pinchToZoom(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        gesture.scale = 1

        delegate?.viewfinder(self, zoomedTo: scale)
    }
}