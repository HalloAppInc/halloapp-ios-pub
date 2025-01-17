//
//  AudioRecorderControlView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import Foundation
import UIKit

private extension Localizations {
    static var audioCancelMessage: String {
        NSLocalizedString("audio.control.cancel", value: "slide to cancel", comment: "Label shown on the cancel action")
    }
}

protocol AudioRecorderControlViewDelegate: AnyObject {
    func audioRecorderControlViewShouldStart(_ view: AudioRecorderControlView) -> Bool
    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView)
    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool)
    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView)
}

class AudioRecorderControlView: UIView {

    struct Configuration {
        fileprivate let mainImage: UIImage?
        fileprivate let expandMaxSize: CGFloat
        fileprivate let cancelButtonTranslationMultiplier: CGFloat

        static let post = Configuration(mainImage: UIImage(named: "Microphone"), expandMaxSize: 160, cancelButtonTranslationMultiplier: 0.25)

        static let unifiedPost = Configuration(mainImage: UIImage(named: "mic_big"), expandMaxSize: 160, cancelButtonTranslationMultiplier: 0.25)

        static let comment = Configuration(mainImage: UIImage(named: "Microphone"),
                                           expandMaxSize: 230,
                                           cancelButtonTranslationMultiplier: 1)
    }

    public var isEnabled = true {
        didSet {
            updateEnabledState()
        }
    }

    public weak var delegate: AudioRecorderControlViewDelegate?

    private let configuration: Configuration

    private var lockButtonAnimator: UIViewPropertyAnimator?
    
    override var intrinsicContentSize: CGSize {
        return mainButton.intrinsicContentSize
    }

    private lazy var mainButton: UIImageView = {
        let imageView = UIImageView(image: configuration.mainImage?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .primaryBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()

    private lazy var blurredBackground: UIView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false
        blurredEffectView.backgroundColor = UIColor(red: 143/255, green: 196/255, blue: 1, alpha: 0.6)
        blurredEffectView.layer.cornerRadius = configuration.expandMaxSize / 2
        blurredEffectView.layer.masksToBounds = true
        blurredEffectView.isUserInteractionEnabled = false

        return blurredEffectView
    }()

    private lazy var lockButton: UIView = {
        let icon = UIImageView(image: UIImage(systemName: "lock.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 16)))
        icon.translatesAutoresizingMaskIntoConstraints = false

        let button = UIView()
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .primaryBlue
        button.layer.cornerRadius = 19
        button.layer.masksToBounds = true

        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true

        button.addSubview(icon)
        icon.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true
        icon.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true

        return button
    } ()

    private lazy var cancelButton: UIView = {
        let button = UILabel()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.font = .systemFont(ofSize: 15)
        button.textColor = .primaryBlackWhite.withAlphaComponent(0.5)
        button.textAlignment = .right
        button.text = Localizations.audioCancelMessage

        button.heightAnchor.constraint(equalToConstant: 16).isActive = true

        return button
    } ()

    private lazy var leftArrow: UIView = {
        let config = UIImage.SymbolConfiguration(weight: .bold)
        let arrow = UIImageView(image: UIImage(systemName: "chevron.left", withConfiguration: config))
        arrow.tintColor = .primaryBlue
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.contentMode = .scaleAspectFit

        arrow.widthAnchor.constraint(equalToConstant: 21).isActive = true
        arrow.heightAnchor.constraint(equalToConstant: 21).isActive = true

        return arrow
    } ()

    private lazy var topArrow: UIView = {
        let config = UIImage.SymbolConfiguration(weight: .bold)
        let arrow = UIImageView(image: UIImage(systemName: "chevron.up", withConfiguration: config))
        arrow.tintColor = .primaryBlue
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.contentMode = .scaleAspectFit

        arrow.widthAnchor.constraint(equalToConstant: 21).isActive = true
        arrow.heightAnchor.constraint(equalToConstant: 21).isActive = true

        return arrow
    } ()

    private lazy var expandingContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = configuration.expandMaxSize / 2
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

        container.addSubview(leftArrow)
        leftArrow.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
        leftArrow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 7).isActive = true

        container.addSubview(topArrow)
        topArrow.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
        topArrow.topAnchor.constraint(equalTo: container.topAnchor, constant: 7).isActive = true

        return container
    }()

    private lazy var expandingContainerWidth: NSLayoutConstraint = {
        return expandingContainer.widthAnchor.constraint(equalToConstant: expandMinSize)
    }()
    private lazy var expandingContainerHeight: NSLayoutConstraint = {
        return expandingContainer.heightAnchor.constraint(equalToConstant: expandMinSize)
    }()
    private lazy var lockButtonVertical: NSLayoutConstraint = {
        return lockButton.bottomAnchor.constraint(equalTo: expandingContainer.topAnchor, constant: actionOffset)
    }()
    private lazy var cancelButtonHorizontal: NSLayoutConstraint = {
        return cancelButton.rightAnchor.constraint(equalTo: expandingContainer.leftAnchor, constant: actionOffset)
    }()

    private var isStarting = false
    private var hasStarted = false
    private var isCancelInProgress = false
    private var isLockInProgress = false
    private var startLocation: CGPoint = .zero

    private let expandMinSize: CGFloat = 40
    private let actionOffset: CGFloat = -8
    private let actionInProgressThreshold: CGFloat = 20
    private let actionActivationThreshold: CGFloat = 90
    private let actionDoneThreshold: CGFloat = 105

    private var isAnyCallOngoingCancellable: AnyCancellable?

    init(configuration: Configuration) {
        self.configuration = configuration

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

        lockButtonVertical.isActive = true
        cancelButtonHorizontal.isActive = true

        isAnyCallOngoingCancellable = MainAppContext.shared.callManager.isAnyCallOngoing.sink { [weak self] _ in
            self?.updateEnabledState()
        }

        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressGestureChanged(_:)))
        longPressGestureRecognizer.allowableMovement = -1
        longPressGestureRecognizer.delegate = self
        longPressGestureRecognizer.minimumPressDuration = 0
        addGestureRecognizer(longPressGestureRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func longPressGestureChanged(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        switch longPressGestureRecognizer.state {
        case .possible:
            break
        case .began:
            guard !isStarting, !hasStarted, delegate?.audioRecorderControlViewShouldStart(self) ?? false else {
                return
            }
            startLocation = longPressGestureRecognizer.location(in: self)
            show()
            isStarting = true
            hasStarted = false
        case .changed:
            guard hasStarted else {
                return
            }

            let location = longPressGestureRecognizer.location(in: self)
            let distanceX = startLocation.x - location.x
            let distanceY = startLocation.y - location.y

            if !isLockInProgress, !isCancelInProgress {
                if distanceX > distanceY, distanceX > actionInProgressThreshold {
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
                    leftArrow.alpha = 0
                    topArrow.alpha = 0
                    expandingContainerWidth.constant = expandMinSize
                    expandingContainerHeight.constant = expandMinSize
                    lockButton.alpha = 1 - progress

                    stopLockButtonLevitation()
                    lockButtonVertical.constant = actionOffset - (configuration.expandMaxSize - expandMinSize) / 2 - diff
                } else if distanceY > actionInProgressThreshold {
                    let progress = diff / (actionActivationThreshold - actionInProgressThreshold)
                    cancelButton.alpha = 1 - progress
                    leftArrow.alpha = 1 - progress
                    topArrow.alpha = 1 - progress
                    expandingContainerWidth.constant = (configuration.expandMaxSize - expandMinSize) * (1 - progress) + expandMinSize
                    expandingContainerHeight.constant = (configuration.expandMaxSize - expandMinSize) * (1 - progress) + expandMinSize
                    expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
                    blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
                    lockButton.alpha = 1

                    stopLockButtonLevitation()
                    lockButtonVertical.constant = actionOffset - (configuration.expandMaxSize - expandingContainerWidth.constant) / 2 - diff
                } else {
                    isLockInProgress = false
                    cancelButton.alpha = 1
                    leftArrow.alpha = 1
                    topArrow.alpha = 1
                    expandingContainerWidth.constant = configuration.expandMaxSize
                    expandingContainerHeight.constant = configuration.expandMaxSize
                    lockButton.alpha = 1
                    lockButtonVertical.constant = actionOffset

                    levitateLockButton()
                }
            } else if isCancelInProgress {
                let diff = (distanceX - actionInProgressThreshold)

                if distanceX > actionDoneThreshold {
                    delegate?.audioRecorderControlViewFinished(self, cancel: true)
                    hide()
                } else if distanceX > actionActivationThreshold {
                    let progress = (distanceX - actionActivationThreshold) / (actionDoneThreshold - actionActivationThreshold)
                    lockButton.alpha = 0
                    leftArrow.alpha = 0
                    topArrow.alpha = 0
                    expandingContainerWidth.constant = expandMinSize
                    expandingContainerHeight.constant = expandMinSize
                    cancelButton.alpha = 1 - progress
                    cancelButtonHorizontal.constant = actionOffset - (configuration.expandMaxSize - expandMinSize) / 2 - configuration.cancelButtonTranslationMultiplier * diff

                    stopLockButtonLevitation()
                } else if distanceX > actionInProgressThreshold {
                    let progress = diff / (actionActivationThreshold - actionInProgressThreshold)
                    lockButton.alpha = 1 - progress
                    leftArrow.alpha = 1 - progress
                    topArrow.alpha = 1 - progress
                    expandingContainerWidth.constant = (configuration.expandMaxSize - expandMinSize) * (1 - progress) + expandMinSize
                    expandingContainerHeight.constant = (configuration.expandMaxSize - expandMinSize) * (1 - progress) + expandMinSize
                    expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
                    blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
                    cancelButton.alpha = 1
                    cancelButtonHorizontal.constant = actionOffset - (configuration.expandMaxSize - expandingContainerWidth.constant) / 2 - configuration.cancelButtonTranslationMultiplier * diff
                    stopLockButtonLevitation()
                } else {
                    isCancelInProgress = false
                    lockButton.alpha = 1
                    leftArrow.alpha = 1
                    topArrow.alpha = 1
                    expandingContainerWidth.constant = configuration.expandMaxSize
                    expandingContainerHeight.constant = configuration.expandMaxSize
                    cancelButton.alpha = 1
                    cancelButtonHorizontal.constant = actionOffset

                    levitateLockButton()
                }
            }

            setNeedsLayout()
        case .ended:
            if isStarting || hasStarted {
                delegate?.audioRecorderControlViewFinished(self, cancel: false)
            }

            hide()
        case .cancelled, .failed:
            hide()
        @unknown default:
            break
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // slightly increase the tap target; helps when collapsed
        return bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    private func levitateLockButton(_ reversed: Bool = false) {
        let target = reversed ? lockButtonVertical.constant + 20 : lockButtonVertical.constant - 20

        lockButtonAnimator = UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.6, delay: 0, options: [.curveEaseInOut], animations: { [weak self] in
            self?.lockButtonVertical.constant = target
            self?.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.levitateLockButton(!reversed)
        })
    }

    private func stopLockButtonLevitation() {
        lockButtonAnimator?.stopAnimation(true)
        lockButtonAnimator = nil
    }

    private func show() {
        expandingContainer.isHidden = false
        expandingContainerWidth.constant = expandMinSize
        expandingContainerHeight.constant = expandMinSize
        expandingContainer.layer.cornerRadius = expandingContainerWidth.constant / 2
        blurredBackground.layer.cornerRadius = expandingContainerWidth.constant / 2
        setNeedsLayout()
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
            // using the same animation parameters as the FAB
            self.expandingContainerWidth.constant = self.configuration.expandMaxSize
            self.expandingContainerHeight.constant = self.configuration.expandMaxSize
            self.expandingContainer.layer.cornerRadius = self.expandingContainerWidth.constant / 2
            self.blurredBackground.layer.cornerRadius = self.expandingContainerWidth.constant / 2
            self.layoutIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(0.3)) {
            guard self.isStarting else { return }
            self.isStarting = false
            self.hasStarted = true
            self.levitateLockButton()
            self.delegate?.audioRecorderControlViewStarted(self)
        }
    }

    func hide() {
        expandingContainer.isHidden = true
        isStarting = false
        hasStarted = false
        isLockInProgress = false
        isCancelInProgress = false
        cancelButton.alpha = 1
        lockButton.alpha = 1
        leftArrow.alpha = 1
        topArrow.alpha = 1

        stopLockButtonLevitation()

        lockButtonVertical.constant = actionOffset
        cancelButtonHorizontal.constant = actionOffset
        setNeedsLayout()
    }
}

extension AudioRecorderControlView: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Take priority over all other gesture recongizers
        return true
    }

    private func updateEnabledState() {
        let isEnabled = self.isEnabled && MainAppContext.shared.callManager.isAnyCallOngoing.value == nil
        mainButton.alpha = isEnabled ? 1 : 0.42
        isUserInteractionEnabled = isEnabled
    }
}
