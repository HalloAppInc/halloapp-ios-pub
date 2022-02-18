//
//  VideoCallViewController.swift
//  HalloApp
//
//  Created by Murali Balusu on 2/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import UIKit
import SwiftUI
import Combine
import CocoaLumberjackSwift
import WebRTC

class VideoCallViewController: CallViewController {

    // Avoid storing local state here.
    private var muted: Bool = false
    private var videoMuted: Bool = false

    // MARK: View Controller

    private var callStatus = CallStatus.calling
    private var useCallStatus: Bool = false

    private let camImage = UIImage(systemName: "arrow.triangle.2.circlepath.camera.fill")
    private let micOffImage = UIImage(systemName: "mic.slash.fill")
    private let micOnImage = UIImage(systemName: "mic.fill")
    private let videoOffImage = UIImage(systemName: "video.slash.fill")
    private let videoOnImage = UIImage(systemName: "video.fill")
    private let endCallImage = UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate)
    private let backImage = UIImage(named: "NavbarBack")?.imageFlippedForRightToLeftLayoutDirection().withRenderingMode(.alwaysTemplate)

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapBack), for: [.touchUpInside])
        button.setImage(backImage, for: .normal)
        button.tintColor = .white
        return button
    }()

    private lazy var callStatusLabel: UILabel = {
        let callStatusLabel = UILabel()
        callStatusLabel.font = UIFont.systemFont(ofSize: 20.0)
        callStatusLabel.textAlignment = .center
        callStatusLabel.textColor = .white
        return callStatusLabel
    }()

    private lazy var camButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: camImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(camButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var videoButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: videoOnImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(videoButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var micButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: micOnImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var endCallButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: endCallImage, title: "", style: .destructive)
        button.tintColor = .red
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(endCallButtonTapped), for: .touchUpInside)
        return button
    }()

    private var callStatusText: String {
        get {
            if isCallOnHold && useCallStatus {
                return Localizations.callStatus(callStatus, for: peerPhoneNumber)
            } else if isCallActive {
                return durationString(seconds: callDurationSec)
            } else if isOutgoing || useCallStatus {
                return Localizations.callStatus(callStatus, for: peerPhoneNumber)
            } else {
                return Localizations.callIncoming
            }
        }
    }

    private let peerUserID: UserID
    private var peerPhoneNumber: String {
        if let phoneNumber = MainAppContext.shared.contactStore.normalizedPhoneNumber(for: peerUserID) {
            return phoneNumber.formattedPhoneNumber
        } else {
            return ""
        }
    }
    private let callManager: CallManager
    private let backAction: (() -> Void)?
    private var isOutgoing: Bool
    private var isCallActive: Bool {
        get {
            return callManager.activeCall?.isActive ?? false
        }
    }
    private var isCallOnHold: Bool {
        get {
            return callManager.activeCall?.isOnHold ?? false
        }
    }
    private var callDurationSec: Int {
        get {
            return Int(callManager.callDurationMs / 1000)
        }
    }
    private var hasStartedReceivingRemoteVideo: Bool {
        get {
            return callManager.activeCall?.hasStartedReceivingRemoteVideo.value ?? false
        }
    }

    private var leadingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var cancellableSet = Set<AnyCancellable>()

    init(peerUserID: UserID, isOutgoing: Bool, backAction: (() -> Void)?) {
        DDLogInfo("CallViewController/init/peerUserID: \(peerUserID)/isOutgoing: \(isOutgoing)")
        self.peerUserID = peerUserID
        self.callManager = MainAppContext.shared.callManager
        self.isOutgoing = isOutgoing
        self.backAction = backAction
        super.init(type: .video)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        DDLogInfo("CallViewController/viewDidLoad")
        super.viewDidLoad()
        view.backgroundColor = .black.withAlphaComponent(0.9)
        view.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        // Using metal (arm64 only)
        let remoteRenderer = RTCMTLVideoView()
        let localRenderer = RTCMTLVideoView()

        view.addSubview(remoteRenderer)
        view.addSubview(localRenderer)

        remoteRenderer.constrain(to: view)
        remoteRenderer.videoContentMode = .scaleAspectFill

        let bottomAnchor = localRenderer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        let leadingAnchor = localRenderer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        let trailingAnchor = localRenderer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        bottomConstraint = bottomAnchor
        leadingConstraint = leadingAnchor
        trailingConstraint = trailingAnchor
        localRenderer.videoContentMode = .scaleAspectFill
        bottomConstraint?.priority = .defaultHigh
        leadingConstraint?.priority = .defaultHigh
        trailingConstraint?.priority = .defaultHigh
        let widthConstraint = localRenderer.widthAnchor.constraint(equalToConstant: 120)
        let heightConstraint = localRenderer.heightAnchor.constraint(equalToConstant: 160)
        let delayTrailingConstraint = localRenderer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15)
        widthConstraint.priority = UILayoutPriority(rawValue: 500)
        heightConstraint.priority = UILayoutPriority(rawValue: 500)
        delayTrailingConstraint.priority = UILayoutPriority(rawValue: 500)

        NSLayoutConstraint.activate([
            localRenderer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            trailingAnchor,
            bottomAnchor,
            leadingAnchor,
            widthConstraint,
            heightConstraint,
            delayTrailingConstraint
        ])

        localRenderer.clipsToBounds = true
        localRenderer.translatesAutoresizingMaskIntoConstraints = false
        remoteRenderer.translatesAutoresizingMaskIntoConstraints = false

        MainAppContext.shared.callManager.activeCall?.renderLocalVideo(to: localRenderer)
        MainAppContext.shared.callManager.activeCall?.renderRemoteVideo(to: remoteRenderer)

        // Action Buttons related stack view
        let buttonPanel = UIStackView()
        buttonPanel.translatesAutoresizingMaskIntoConstraints = false
        buttonPanel.axis = .horizontal
        buttonPanel.distribution  = .fillEqually
        buttonPanel.alignment = UIStackView.Alignment.center
        buttonPanel.addArrangedSubview(camButton)
        buttonPanel.addArrangedSubview(videoButton)
        buttonPanel.addArrangedSubview(micButton)
        buttonPanel.addArrangedSubview(endCallButton)

        // Text Label
        let peerNameLabel = UILabel()
        peerNameLabel.text = MainAppContext.shared.contactStore.fullName(for: peerUserID, showPushNumber: true)
        peerNameLabel.font = .systemFont(ofSize: 30)
        peerNameLabel.textColor = .white
        peerNameLabel.adjustsFontSizeToFitWidth = true
        peerNameLabel.textAlignment = .center
        peerNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Full stack view: contains all the components
        let fullCallView = UIStackView(arrangedSubviews: [peerNameLabel, callStatusLabel])
        fullCallView.translatesAutoresizingMaskIntoConstraints = false
        fullCallView.axis = .vertical
        fullCallView.distribution = .fill
        fullCallView.alignment = .center
        fullCallView.spacing = 36
        fullCallView.setCustomSpacing(8, after: peerNameLabel)

        view.addSubview(fullCallView)
        view.addSubview(buttonPanel)

        fullCallView.constrain(anchor: .leading, to: view, constant: 36)
        fullCallView.constrain(anchor: .trailing, to: view, constant: -36)

        NSLayoutConstraint.activate([
            buttonPanel.constrain(anchor: .leading, to: view, constant: 36),
            buttonPanel.constrain(anchor: .trailing, to: view, constant: -36),
            buttonPanel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
        ])

        if backAction == nil {
            fullCallView.constrainMargin(anchor: .top, to: view, constant: 44)
        } else {
            view.addSubview(backButton)
            backButton.constrainMargins([.top, .leading], to: view)
            backButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            backButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

            fullCallView.topAnchor.constraint(greaterThanOrEqualTo: backButton.bottomAnchor).isActive = true
        }

        if let activeCall = MainAppContext.shared.callManager.activeCall {
            cancellableSet.insert(
                activeCall.hasStartedReceivingRemoteVideo.sink { [weak self] result in
                    guard let self = self else { return }
                    if result {
                        if self.isOutgoing {
                            self.didStartReceivingRemoteVideo()
                        } else {
                            // Adding a manual delay of 2 seconds for UI to show smooth animation.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                self.didStartReceivingRemoteVideo()
                            }
                        }
                    }
                })
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewWillAppear")
        super.viewWillAppear(animated)
        updateCallStatusLabel()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewDidDisappear")
        super.viewDidDisappear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
    }

    private func updateCallStatusLabel() {
        callStatusLabel.text = callStatusText
    }

    private func durationString(seconds : Int) -> String {
        let ss = (seconds % 3600) % 60
        let mm = (seconds % 3600) / 60
        let hh = seconds / 3600
        if hh > 0 {
            return String(format: "%02d:%02d:%02d", hh, mm, ss)
        } else {
            return String(format: "%02d:%02d", mm, ss)
        }
    }

    // Call Actions.

    @objc func camButtonTapped(sender: UIButton) {
        DDLogInfo("VideoCallViewController/camButtonTapped/")
        callManager.switchCamera() { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/switchCamera/failed: \(error)")
                case .success:
                    break
                }
            }
        }
    }

    @objc func videoButtonTapped(sender: UIButton) {
        videoMuted = !videoMuted
        DDLogInfo("VideoCallViewController/videoButtonTapped/muted: \(videoMuted)")
        callManager.muteVideo(muted: videoMuted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/muteVideo/failed: \(error)")
                case .success:
                    let videoStatusImage = self.videoMuted ? self.videoOffImage : self.videoOnImage
                    self.videoButton.image = videoStatusImage
                }
            }
        }
    }

    @objc func micButtonTapped(sender: UIButton) {
        muted = !muted
        DDLogInfo("VideoCallViewController/micButtonTapped/muted: \(muted)")
        callManager.muteAudio(muted: muted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/muteCall/failed: \(error)")
                case .success:
                    let micStatusImage = self.muted ? self.micOffImage : self.micOnImage
                    self.micButton.image = micStatusImage
                }
            }
        }
    }

    @objc func endCallButtonTapped(sender: UIButton) {
        DDLogInfo("VideoCallViewController/endCallButtonTapped")
        callManager.endCall(reason: .ended) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/endCall/failed: \(error)")
                case .success:
                    self.navigationController?.popViewController(animated: true)
                    self.dismiss(animated: true, completion: nil)
                }
            }
        }
    }

    @objc func didTapBack() {
        backAction?()
    }

    // MARK:- CallViewDelegate

    override func startedOutgoingCall(call: Call) {
    }

    override func callAccepted(call: Call) {
    }

    override func callStarted() {
    }

    override func callRinging() {
        callStatus = .ringing
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callConnected() {
        callStatus = .connecting
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callActive() {
        useCallStatus = false
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callDurationChanged(seconds: Int) {
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callEnded() {
    }

    override func callReconnecting() {
        callStatus = .reconnecting
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callFailed() {
        callStatus = .failed
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callHold(_ hold: Bool) {
        if hold {
            callStatus = .held
        }
        useCallStatus = hold
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callBusy() {
        callStatus = .busy
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    override func callMute(_ muted: Bool, media: CallMediaType) {
    }

    func didStartReceivingRemoteVideo() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            DDLogInfo("VideoCallViewController/didStartReceivingRemoteVideo")
            self.bottomConstraint?.priority = .defaultLow
            self.leadingConstraint?.priority = .defaultLow
            self.trailingConstraint?.priority = .defaultLow
            UIView.animate(withDuration: 0.5, animations: {
                self.view.layoutIfNeeded()
            })
        }
    }
}

extension VideoCallViewController: RTCVideoViewDelegate {
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DDLogInfo("VideoCallViewController/RTCVideoViewDelegate/didChangeVideoSize: \(size)")
    }

}

final class VideoCallViewButton: UIControl {

    struct Style {
        var circleDiameter: CGFloat = 48
        var circleColor: UIColor = UIColor.white.withAlphaComponent(0.3)
        var iconHeight: CGFloat = 20

        static var normal: Style {
            Style()
        }

        static var destructive: Style {
            Style(
                circleDiameter: 48,
                circleColor: UIColor(red: 235.0/255, green: 77.0/255, blue: 61.0/255, alpha: 1),
                iconHeight: 20)
        }
    }

    init(image: UIImage?, title: String, style: Style = .normal) {
        self.diameter = style.circleDiameter
        super.init(frame: .zero)
        circleView.backgroundColor = style.circleColor
        imageView.image = image
        label.text = title
        addSubview(circleView)
        addSubview(label)
        imageView.heightAnchor.constraint(equalToConstant: style.iconHeight).isActive = true
        circleView.isUserInteractionEnabled = false
        circleView.constrain([.top, .centerX], to: self)
        circleView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor).isActive = true
        label.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 2).isActive = true
        label.constrain([.bottom, .leading, .trailing], to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let diameter: CGFloat

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .subheadline, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var circleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.layer.cornerRadius = diameter / 2

        imageView.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        imageView.contentMode = .scaleAspectFit
        imageView.constrain([.centerX, .centerY], to: view)

        view.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        view.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        return view
    }()
}
