//
//  AudioRecorderControlView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

protocol AudioRecorderControlViewDelegate: AnyObject {
    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView)
    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool)
    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView)
}

class AudioRecorderControlView: UIView {
    public weak var delegate: AudioRecorderControlViewDelegate?

    private lazy var mainButton: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "Microphone")?.withTintColor(.primaryBlue))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()

    private lazy var blurredBackground: UIView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false
        blurredEffectView.backgroundColor = UIColor(red: 143/255, green: 196/255, blue: 1, alpha: 0.3)
        blurredEffectView.layer.cornerRadius = expandMaxSize / 2
        blurredEffectView.layer.masksToBounds = true
        blurredEffectView.isUserInteractionEnabled = false

        return blurredEffectView
    }()

    private lazy var lockButton: UIView = {
        let icon = UIImageView(image: UIImage(named: "Lock")?.withTintColor(.white))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let button = UIImageView(image: UIImage(named: "AudioDropTop"))
        button.translatesAutoresizingMaskIntoConstraints = false

        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 51).isActive = true

        button.addSubview(icon)
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        icon.topAnchor.constraint(equalTo: button.topAnchor, constant: 7).isActive = true
        icon.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true

        return button
    } ()

    private lazy var cancelButton: UIView = {
        let icon = UIImageView(image: UIImage(named: "NavbarTrashBinWithLid")?.withTintColor(.white))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let button = UIImageView(image: UIImage(named: "AudioDropLeft"))
        button.translatesAutoresizingMaskIntoConstraints = false

        button.widthAnchor.constraint(equalToConstant: 51).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true

        button.addSubview(icon)
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        icon.leftAnchor.constraint(equalTo: button.leftAnchor, constant: 7).isActive = true
        icon.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true

        return button
    } ()

    private lazy var expandingContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = expandMaxSize / 2
        container.isHidden = true

        container.addSubview(blurredBackground)
        blurredBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        blurredBackground.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        blurredBackground.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        blurredBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true

        container.addSubview(lockButton)
        lockButton.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true

        container.addSubview(cancelButton)
        cancelButton.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true

        return container
    }()

    private lazy var expandingContainerWidth: NSLayoutConstraint = {
        return expandingContainer.widthAnchor.constraint(equalToConstant: expandMinSize)
    }()
    private lazy var expandingContainerHeight: NSLayoutConstraint = {
        return expandingContainer.heightAnchor.constraint(equalToConstant: expandMinSize)
    }()
    private lazy var lockButtonTop: NSLayoutConstraint = {
        return lockButton.topAnchor.constraint(equalTo: expandingContainer.topAnchor, constant: actionOffset)
    }()
    private lazy var cancelButtonLeft: NSLayoutConstraint = {
        return cancelButton.leftAnchor.constraint(equalTo: expandingContainer.leftAnchor, constant: actionOffset)
    }()

    private var isActive = false
    private var isCancelInProgress = false
    private var isLockInProgress = false
    private var startLocation: CGPoint = .zero

    private let expandMinSize: CGFloat = 40
    private let expandMaxSize: CGFloat = 230
    private let actionOffset: CGFloat = 12
    private let actionInProgressThreshold: CGFloat = 20
    private let actionActivationThreshold: CGFloat = 115
    private let actionDoneThreshold: CGFloat = 135

    init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = true

        addSubview(expandingContainer)
        addSubview(mainButton)

        mainButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        mainButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        mainButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        mainButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        expandingContainer.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        expandingContainer.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        expandingContainerWidth.isActive = true
        expandingContainerHeight.isActive = true

        lockButtonTop.isActive = true
        cancelButtonLeft.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        startLocation = touch.location(in: self)
        show()
        isActive = true
        delegate?.audioRecorderControlViewStarted(self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isActive else { return }
        guard let touch = touches.first else { return }

        let location = touch.location(in: self)
        let distanceX = startLocation.x - location.x
        let distanceY = startLocation.y - location.y

        if !isLockInProgress && !isCancelInProgress {
            if distanceX > distanceY && distanceX > actionInProgressThreshold {
                isCancelInProgress = true
            } else if distanceY > actionInProgressThreshold {
                isLockInProgress = true
            }
        }

        if isLockInProgress {
            let diff = (distanceY - actionInProgressThreshold)

            if distanceY > actionDoneThreshold {
                delegate?.audioRecorderControlViewLocked(self)
                hide()
            } else if distanceY > actionActivationThreshold {
                let progress = (distanceY - actionActivationThreshold) / (actionDoneThreshold - actionActivationThreshold)
                cancelButton.alpha = 0
                expandingContainerWidth.constant = expandMinSize
                expandingContainerHeight.constant = expandMinSize
                lockButton.alpha = 1 - progress
                lockButtonTop.constant = 12 - (expandMaxSize - expandMinSize) / 2 - diff
            } else if distanceY > actionInProgressThreshold {
                let progress = diff / (actionActivationThreshold - actionInProgressThreshold)
                cancelButton.alpha = 1 - progress
                expandingContainerWidth.constant = 190 * (1 - progress) + 40
                expandingContainerHeight.constant = 190 * (1 - progress) + 40
                expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
                blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
                lockButton.alpha = 1
                lockButtonTop.constant = 12 - (expandMaxSize - expandingContainerWidth.constant) / 2 - diff
            } else {
                isLockInProgress = false
                cancelButton.alpha = 1
                expandingContainerWidth.constant = expandMaxSize
                expandingContainerHeight.constant = expandMaxSize
                lockButton.alpha = 1
                lockButtonTop.constant = actionOffset
            }
        } else if isCancelInProgress {
            let diff = (distanceX - actionInProgressThreshold)

            if distanceX > actionDoneThreshold {
                delegate?.audioRecorderControlViewFinished(self, cancel: true)
                hide()
            } else if distanceY > actionActivationThreshold {
                let progress = (distanceX - actionActivationThreshold) / (actionDoneThreshold - actionActivationThreshold)
                lockButton.alpha = 0
                expandingContainerWidth.constant = expandMinSize
                expandingContainerHeight.constant = expandMinSize
                cancelButton.alpha = 1 - progress
                cancelButtonLeft.constant = 12 - (expandMaxSize - expandMinSize) / 2 - diff
            } else if distanceX > actionInProgressThreshold {
                let progress = diff / (actionActivationThreshold - actionInProgressThreshold)
                lockButton.alpha = 1 - progress
                expandingContainerWidth.constant = 190 * (1 - progress) + 40
                expandingContainerHeight.constant = 190 * (1 - progress) + 40
                expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
                blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
                cancelButton.alpha = 1
                cancelButtonLeft.constant = 12 - (expandMaxSize - expandingContainerWidth.constant) / 2 - diff
            } else {
                isCancelInProgress = false
                lockButton.alpha = 1
                expandingContainerWidth.constant = expandMaxSize
                expandingContainerHeight.constant = expandMaxSize
                cancelButton.alpha = 1
                cancelButtonLeft.constant = actionOffset
            }
        }

        layoutIfNeeded()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isActive {
            delegate?.audioRecorderControlViewFinished(self, cancel: false)
        }

        hide()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        hide()
    }

    private func show() {
        expandingContainer.isHidden = false
        expandingContainerWidth.constant = expandMinSize
        expandingContainerHeight.constant = expandMinSize
        expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
        blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
        layoutIfNeeded()

        UIView.animate(withDuration: 0.3) {
            self.expandingContainerWidth.constant = self.expandMaxSize
            self.expandingContainerHeight.constant = self.expandMaxSize
            self.expandingContainer.layer.cornerRadius = self.expandingContainerWidth.constant / 2
            self.blurredBackground.layer.cornerRadius = self.expandingContainerWidth.constant / 2
            self.layoutIfNeeded()
        }
    }

    private func hide() {
        expandingContainer.isHidden = true
        isActive = false
        isLockInProgress = false
        isCancelInProgress = false
        cancelButton.alpha = 1
        lockButton.alpha = 1
        lockButtonTop.constant = actionOffset
        cancelButtonLeft.constant = actionOffset
        layoutIfNeeded()
    }
}
