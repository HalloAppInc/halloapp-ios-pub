//
//  VideoCallViewController.swift
//  HalloApp
//
//  Created by Murali Balusu on 2/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CoreCommon
import UIKit
import SwiftUI
import Combine
import CocoaLumberjackSwift
import WebRTC

class VideoCallViewController: CallViewController {

    private enum VideoType {
        case local
        case remote
    }
    // This will be useful in the future.
    private var expandedVideo: VideoType = .local

    private var isLocalAudioMuted: Bool = false
    private var isLocalVideoMuted: Bool = false
    private var isRemoteAudioMuted: Bool = false
    private var isRemoteVideoMuted: Bool = false

    // MARK: View Controller

    private var callStatus = CallStatus.calling
    private var useCallStatus: Bool = false
    private var speakerOn: Bool = true
    var selectedOutputPortType: AVAudioSession.Port = .builtInSpeaker
    var selectedOutputName: String = Localizations.callSpeaker
    var routeChangeSubscriber: AnyCancellable?

    private let speakerImage = UIImage(systemName: "speaker.wave.3.fill")
    private let earphonesImage = UIImage(systemName: "earpods")
    private let carplayImage = UIImage(systemName: "car")
    private let camImage = UIImage(systemName: "arrow.triangle.2.circlepath.camera.fill")
    private let micImage = UIImage(systemName: "mic.slash.fill")
    private let videoImage = UIImage(systemName: "video.slash.fill")
    private let endCallImage = UIImage(systemName: "phone.down.fill")?.withRenderingMode(.alwaysTemplate)
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

    private lazy var peerNameLabel: UILabel = {
        let contactsViewContext = MainAppContext.shared.contactStore.viewContext
        let peerNameLabel = UILabel()
        peerNameLabel.text = MainAppContext.shared.contactStore.fullName(for: peerUserID, showPushNumber: true, in: contactsViewContext)
        peerNameLabel.font = .systemFont(ofSize: 30)
        peerNameLabel.textColor = .white
        peerNameLabel.adjustsFontSizeToFitWidth = true
        peerNameLabel.textAlignment = .center
        peerNameLabel.translatesAutoresizingMaskIntoConstraints = false
        return peerNameLabel
    }()

    private lazy var stationIdentification: UIView = {
        let imageView = UIImageView(image: UIImage(named: "AppIconSmall"))
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.appNameHalloApp
        label.textColor = .white
        label.font = .systemFont(forTextStyle: .title3)

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(label)

        imageView.constrain([.top, .bottom, .leading], to: view)
        label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10).isActive = true
        label.constrain([.top, .bottom, .trailing], to: view)
        return view
    }()

    private lazy var encryptionLabel: UILabel = {
        let encryptionLabel = UILabel()
        encryptionLabel.text = "🔒 " + Localizations.callEncryption
        encryptionLabel.font = .systemFont(ofSize: 15)
        encryptionLabel.textColor = .white
        encryptionLabel.adjustsFontSizeToFitWidth = true
        encryptionLabel.textAlignment = .center
        encryptionLabel.translatesAutoresizingMaskIntoConstraints = false
        return encryptionLabel
    }()

    private lazy var callNameStatusView: UIStackView = {
        let callNameStatusView = UIStackView(arrangedSubviews: [stationIdentification, encryptionLabel, peerNameLabel, callStatusLabel])
        callNameStatusView.translatesAutoresizingMaskIntoConstraints = false
        callNameStatusView.axis = .vertical
        callNameStatusView.distribution = .fill
        callNameStatusView.alignment = .center
        callNameStatusView.spacing = 36
        callNameStatusView.setCustomSpacing(8, after: peerNameLabel)
        return callNameStatusView
    }()

    private lazy var muteStatusLabel: UILabel = {
        let muteStatusLabel = UILabel()
        muteStatusLabel.text = ""
        muteStatusLabel.font = .systemFont(ofSize: 16)
        muteStatusLabel.textColor = .white
        muteStatusLabel.adjustsFontSizeToFitWidth = true
        muteStatusLabel.textAlignment = .center
        muteStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        muteStatusLabel.isHidden = true
        return muteStatusLabel
    }()

    // Action Buttons related stack view
    private lazy var buttonPanel: UIStackView = {
        let buttonPanel = UIStackView()
        buttonPanel.translatesAutoresizingMaskIntoConstraints = false
        buttonPanel.axis = .horizontal
        buttonPanel.distribution  = .fillEqually
        buttonPanel.alignment = UIStackView.Alignment.center
        buttonPanel.addArrangedSubview(camButton)
        buttonPanel.addArrangedSubview(videoButton)
        buttonPanel.addArrangedSubview(micButton)
        buttonPanel.addArrangedSubview(speakerButton)
        buttonPanel.addArrangedSubview(endCallButton)
        return buttonPanel
    }()

    private lazy var camButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: camImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(camButtonTapped), for: .touchUpInside)
        let edgeInset = (VideoCallViewButton.Style.normal.circleDiameter - VideoCallViewButton.Style.normal.iconHeight)/2
        button.contentEdgeInsets = UIEdgeInsets(top: edgeInset, left: 0, bottom: edgeInset, right: 0)
        return button
    }()

    private lazy var videoButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: videoImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(videoButtonTapped), for: .touchUpInside)
        let edgeInset = (VideoCallViewButton.Style.normal.circleDiameter - VideoCallViewButton.Style.normal.iconHeight)/2
        button.contentEdgeInsets = UIEdgeInsets(top: edgeInset, left: 0, bottom: edgeInset, right: 0)
        return button
    }()

    private lazy var micButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: micImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)
        let edgeInset = (VideoCallViewButton.Style.normal.circleDiameter - VideoCallViewButton.Style.normal.iconHeight)/2
        button.contentEdgeInsets = UIEdgeInsets(top: edgeInset, left: 0, bottom: edgeInset, right: 0)
        return button
    }()

    // TODO: perhaps merge with the mute button like whatsapp does.
    private lazy var speakerButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: speakerImage, title: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isSelected = true
        let edgeInset = (VideoCallViewButton.Style.normal.circleDiameter - VideoCallViewButton.Style.normal.iconHeight)/2
        button.contentEdgeInsets = UIEdgeInsets(top: edgeInset, left: 0, bottom: edgeInset, right: 0)
        return button
    }()

    func updateSpeakerButton() {
        if #available(iOS 14.0, *) {
            let inputs = RTCAudioSession.sharedInstance().session.availableInputs ?? []
            if inputs.count > 1 {
                speakerButton.showsMenuAsPrimaryAction = true
                var menuItems: [UIMenuElement] = []
                menuItems += inputs.compactMap { input in
                    let title = input.portName
                    if input.portType == .builtInMic {
                        return nil
                    } else {
                        var state: UIMenuElement.State = .off
                        if selectedOutputName == input.portName && speakerOn == false {
                            state = .on
                        } else {
                            state = .off
                        }
                        return UIAction(title: title,
                                        state: state,
                                        handler: { _ in
                            self.selectedOutputPortType = input.portType
                            self.selectedOutputName = input.portName
                            self.speakerOn = false
                            self.selectAudioInput(input: input)
                            self.updateSpeakerButton()
                        })
                    }
                }

                menuItems.append(UIAction(title: Localizations.callSpeaker, state: speakerOn ? .on : .off, handler: { _ in
                    self.selectedOutputPortType = .builtInSpeaker
                    self.selectedOutputName = Localizations.callSpeaker
                    self.speakerOn = true
                    self.setSpeakerOn()
                    self.updateSpeakerButton()
                }))
                if #available(iOS 15.0, *) {
                    speakerButton.menu = UIMenu(options: [.singleSelection], children: menuItems)
                } else {
                    // Fallback on earlier versions
                    speakerButton.menu = UIMenu(children: menuItems)
                }
                speakerButton.removeTarget(self, action: #selector(speakerButtonTapped), for: .touchUpInside)
            } else {
                speakerButton.showsMenuAsPrimaryAction = false
                speakerButton.menu = nil
                speakerButton.image = speakerImage
                speakerButton.addTarget(self, action: #selector(speakerButtonTapped), for: .touchUpInside)
            }
        } else {
            // handle this.
            speakerButton.image = speakerImage
            speakerButton.addTarget(self, action: #selector(speakerButtonTapped), for: .touchUpInside)
        }
    }

    private lazy var endCallButton: VideoCallViewButton = {
        let button = VideoCallViewButton(image: endCallImage, title: "", style: .destructive)
        button.tintColor = .red
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(endCallButtonTapped), for: .touchUpInside)
        let edgeInset = (VideoCallViewButton.Style.destructive.circleDiameter - VideoCallViewButton.Style.destructive.iconHeight)/2
        button.contentEdgeInsets = UIEdgeInsets(top: edgeInset, left: 0, bottom: edgeInset, right: 0)
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

    private var muteStatusText: String {
        get {
            switch expandedVideo {
            case .local:
                return Localizations.localMuteStatus(isAudioMuted: isLocalAudioMuted, isVideoMuted: isLocalVideoMuted)
            case .remote:
                let peerName = MainAppContext.shared.callManager.peerName(for: peerUserID)
                return Localizations.remoteMuteStatus(isAudioMuted: isRemoteAudioMuted, isVideoMuted: isRemoteVideoMuted, for: peerName)
            }
        }
    }

    private let peerUserID: UserID
    private var peerPhoneNumber: String {
        let viewContext = MainAppContext.shared.contactStore.viewContext
        if let phoneNumber = MainAppContext.shared.contactStore.normalizedPhoneNumber(for: peerUserID, using: viewContext) {
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
    private var hideControlsTimer: DispatchSourceTimer?
    private var hideControls: Bool  = false {
        didSet {
            let isHidden = hideControls
            if isHidden {
                self.stationIdentification.isHidden = true
                self.encryptionLabel.isHidden = true
            } else {
                self.stationIdentification.isHidden = false
                self.encryptionLabel.isHidden = false
            }
            UIView.animate(withDuration: 0.3) {
                if isHidden {
                    self.buttonPanel.alpha = 0
                    self.backButton.alpha = 0
                } else {
                    self.buttonPanel.alpha = 1
                    self.backButton.alpha = 1
                }
            }
        }
    }

    // TODO: This is not clean and has to be redone as per design.
    private var localViewLeadingConstraint: NSLayoutConstraint?
    private var localViewBottomConstraint: NSLayoutConstraint?
    private var localViewTrailingConstraint: NSLayoutConstraint?
    private var localViewTopConstraint: NSLayoutConstraint?
    private var remoteViewLeadingConstraint: NSLayoutConstraint?
    private var remoteViewBottomConstraint: NSLayoutConstraint?
    private var remoteViewTrailingConstraint: NSLayoutConstraint?
    private var remoteViewTopConstraint: NSLayoutConstraint?
    private var cancellableSet = Set<AnyCancellable>()

    private lazy var remoteBlurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = remoteRenderer.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return blurEffectView
    }()
    private lazy var localBlurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = localRenderer.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return blurEffectView
    }()
    // Using metal (arm64 only)
    private let remoteRenderer = RTCMTLVideoView()
    private let localRenderer = RTCMTLVideoView()

    init(peerUserID: UserID, isOutgoing: Bool, backAction: (() -> Void)?) {
        DDLogInfo("VideoCallViewController/init/peerUserID: \(peerUserID)/isOutgoing: \(isOutgoing)")
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
        DDLogInfo("VideoCallViewController/viewDidLoad")
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        localRenderer.transform = CGAffineTransform(scaleX: -1, y: 1)

        localRenderer.addSubview(localBlurView)
        localBlurView.isHidden = true
        remoteRenderer.addSubview(remoteBlurView)
        remoteBlurView.isHidden = true

        view.addSubview(remoteRenderer)
        view.addSubview(localRenderer)

        // Set self as delegate for remote view.
        remoteRenderer.delegate = self

        localRenderer.videoContentMode = .scaleAspectFill
        let localViewBottomAnchor = localRenderer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let localViewLeadingAnchor = localRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let localViewTrailingAnchor = localRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let localViewTopAnchor = localRenderer.topAnchor.constraint(equalTo: view.topAnchor)
        localViewBottomConstraint = localViewBottomAnchor
        localViewLeadingConstraint = localViewLeadingAnchor
        localViewTrailingConstraint = localViewTrailingAnchor
        localViewTopConstraint = localViewTopAnchor
        localViewBottomConstraint?.priority = .defaultHigh
        localViewLeadingConstraint?.priority = .defaultHigh
        localViewTrailingConstraint?.priority = .defaultHigh
        localViewTopConstraint?.priority = .defaultHigh
        let localViewWidthConstraint = localRenderer.widthAnchor.constraint(equalToConstant: 120)
        let localViewHeightConstraint = localRenderer.heightAnchor.constraint(equalToConstant: 160)
        let localViewDelayTrailingConstraint = localRenderer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15)
        let localViewDelayTopConstraint = localRenderer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        localViewWidthConstraint.priority = UILayoutPriority(rawValue: 500)
        localViewHeightConstraint.priority = UILayoutPriority(rawValue: 500)
        localViewDelayTrailingConstraint.priority = UILayoutPriority(rawValue: 500)
        localViewDelayTopConstraint.priority = UILayoutPriority(rawValue: 500)

        NSLayoutConstraint.activate([
            localViewTopAnchor,
            localViewTrailingAnchor,
            localViewBottomAnchor,
            localViewLeadingAnchor,
            localViewWidthConstraint,
            localViewHeightConstraint,
            localViewDelayTrailingConstraint,
            localViewDelayTopConstraint
        ])

        remoteRenderer.videoContentMode = .scaleAspectFill
        let remoteViewBottomAnchor = remoteRenderer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let remoteVideoLeadingAnchor = remoteRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let remoteVideoTrailingAnchor = remoteRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let remoteVideoTopAnchor = remoteRenderer.topAnchor.constraint(equalTo: view.topAnchor)
        remoteViewBottomConstraint = remoteViewBottomAnchor
        remoteViewLeadingConstraint = remoteVideoLeadingAnchor
        remoteViewTrailingConstraint = remoteVideoTrailingAnchor
        remoteViewTopConstraint = remoteVideoTopAnchor
        remoteViewBottomConstraint?.priority = .defaultHigh
        remoteViewLeadingConstraint?.priority = .defaultHigh
        remoteViewTrailingConstraint?.priority = .defaultHigh
        remoteViewTopConstraint?.priority = .defaultHigh
        let remoteVideoWidthConstraint = remoteRenderer.widthAnchor.constraint(equalToConstant: 120)
        let remoteVideoHeightConstraint = remoteRenderer.heightAnchor.constraint(equalToConstant: 160)
        let remoteVideoDelayTrailingConstraint = remoteRenderer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15)
        let remoteVideoDelayTopConstraint = remoteRenderer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        remoteVideoWidthConstraint.priority = UILayoutPriority(rawValue: 500)
        remoteVideoHeightConstraint.priority = UILayoutPriority(rawValue: 500)
        remoteVideoDelayTrailingConstraint.priority = UILayoutPriority(rawValue: 500)
        remoteVideoDelayTopConstraint.priority = UILayoutPriority(rawValue: 500)

        NSLayoutConstraint.activate([
            remoteVideoTopAnchor,
            remoteVideoTrailingAnchor,
            remoteViewBottomAnchor,
            remoteVideoLeadingAnchor,
            remoteVideoWidthConstraint,
            remoteVideoHeightConstraint,
            remoteVideoDelayTrailingConstraint,
            remoteVideoDelayTopConstraint
        ])

        localRenderer.clipsToBounds = true
        localRenderer.translatesAutoresizingMaskIntoConstraints = false
        remoteRenderer.clipsToBounds = true
        remoteRenderer.translatesAutoresizingMaskIntoConstraints = false

        MainAppContext.shared.callManager.activeCall?.renderLocalVideo(to: localRenderer)
        MainAppContext.shared.callManager.activeCall?.renderRemoteVideo(to: remoteRenderer)

        view.addSubview(callNameStatusView)
        view.addSubview(muteStatusLabel)
        view.addSubview(buttonPanel)

        callNameStatusView.constrain(anchor: .leading, to: view, constant: 36)
        callNameStatusView.constrain(anchor: .trailing, to: view, constant: -36)
        muteStatusLabel.constrain(anchor: .leading, to: view, constant: 36)
        muteStatusLabel.constrain(anchor: .trailing, to: view, constant: -36)

        NSLayoutConstraint.activate([
            buttonPanel.constrain(anchor: .leading, to: view, constant: 36),
            buttonPanel.constrain(anchor: .trailing, to: view, constant: -36),
            buttonPanel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
        ])

        if backAction == nil {
            callNameStatusView.constrainMargin(anchor: .top, to: view, constant: 44)
            muteStatusLabel.constrainMargin(anchor: .top, to: view, constant: 200)
        } else {
            view.addSubview(backButton)
            backButton.constrainMargins([.top, .leading], to: view)
            backButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            backButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

            callNameStatusView.topAnchor.constraint(greaterThanOrEqualTo: backButton.bottomAnchor).isActive = true
            muteStatusLabel.topAnchor.constraint(greaterThanOrEqualTo: backButton.bottomAnchor, constant: 200).isActive = true
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

            cancellableSet.insert(
                activeCall.mirrorVideo.sink { [weak self] mirror in
                    guard let self = self else { return }
                    self.mirrorVideo(mirror)
                })

            cancellableSet.insert(
                activeCall.isRemoteAudioMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    self.isRemoteAudioMuted = muted
                    DispatchQueue.main.async {
                        self.updateMuteStatusLabel()
                    }
                })

            cancellableSet.insert(
                activeCall.isRemoteVideoMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    self.isRemoteVideoMuted = muted
                    DispatchQueue.main.async {
                        self.handleRemoteVideoMuted(muted: muted)
                    }
                })

            cancellableSet.insert(
                activeCall.isLocalAudioMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    self.isLocalAudioMuted = muted
                })

            cancellableSet.insert(
                activeCall.isLocalVideoMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    self.isLocalVideoMuted = muted
                    DispatchQueue.main.async {
                        self.handleLocalVideoMuted(muted: muted)
                    }
                })
        }

        updateSpeakerButton()

        // Listen to route updates and update speaker button accordingly.
        routeChangeSubscriber?.cancel()
        routeChangeSubscriber = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink(receiveValue: { [weak self] notification in
                guard let self = self else { return }
                self.updateSpeakerButton()
            })
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
        setupHideControlsTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewDidDisappear")
        super.viewDidDisappear(animated)
        cancelHideControlsTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("VideoCallViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
    }

    private func updateCallStatusLabel() {
        callStatusLabel.text = callStatusText
    }

    private func updateMuteStatusLabel() {
        guard !self.muteStatusText.isEmpty else {
            self.muteStatusLabel.isHidden = true
            return
        }
        self.muteStatusLabel.text = self.muteStatusText
        self.muteStatusLabel.isHidden = false
    }

    override var shouldAutorotate: Bool {
        return false
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

    private func setupHideControlsTimer() {
        guard isCallActive else {
            return
        }
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                DDLogInfo("Call/setupHideControlsTimer/hiding controls now")
                self.hideControls = true
            }
        })
        timer.schedule(deadline: .now() + DispatchTimeInterval.seconds(5))
        timer.resume()
        hideControlsTimer = timer
    }

    private func cancelHideControlsTimer() {
        hideControlsTimer?.cancel()
        hideControlsTimer = nil
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
                    self.camButton.isSelected = true
                    UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction]) {
                        self.camButton.isSelected = false
                    }
                }
            }
        }
    }

    @objc func videoButtonTapped(sender: UIButton) {
        isLocalVideoMuted = !isLocalVideoMuted
        DDLogInfo("VideoCallViewController/videoButtonTapped/muted: \(isLocalVideoMuted)")
        callManager.muteVideo(muted: isLocalVideoMuted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/muteVideo/failed: \(error)")
                case .success:
                    self.videoButton.isSelected = self.isLocalVideoMuted
                }
            }
        }
    }

    @objc func micButtonTapped(sender: UIButton) {
        isLocalAudioMuted = !isLocalAudioMuted
        DDLogInfo("VideoCallViewController/micButtonTapped/muted: \(isLocalAudioMuted)")
        callManager.muteAudio(muted: isLocalAudioMuted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/muteCall/failed: \(error)")
                case .success:
                    self.micButton.isSelected = self.isLocalAudioMuted
                }
            }
        }
    }

    @objc func speakerButtonTapped(sender: UIButton) {
        speakerOn = !speakerOn
        let prevImage = self.speakerButton.image
        let prevSelectedState = self.speakerButton.isSelected
        self.speakerButton.image = self.speakerImage
        self.speakerButton.isSelected = self.speakerOn
        DDLogInfo("VideoCallViewController/speakerButtonTapped/speakerOn: \(speakerOn)")
        callManager.setSpeakerCall(speaker: speakerOn) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/speakerButtonTapped/failed: \(error)")
                    self.speakerButton.image = prevImage
                    self.speakerButton.isSelected = prevSelectedState
                case .success:
                    DDLogError("VideoCallViewController/speakerButtonTapped/success")
                    self.speakerButton.isSelected = self.speakerOn
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

    func selectAudioInput(input: AVAudioSessionPortDescription) {
        DDLogInfo("VideoCallViewController/selectAudioInput/input: \(input)")
        var speakerButtonImage = speakerImage
        var speakerButtonSelected = false
        switch input.portType {
        case .builtInMic:
            speakerOn = false
            speakerButtonSelected = false
        case .bluetoothHFP:
            speakerButtonImage = earphonesImage
            speakerButtonSelected = true
        case .carAudio:
            speakerButtonImage = carplayImage
            speakerButtonSelected = true
        default:
            speakerOn = true
            speakerButtonSelected = true
        }
        let prevImage = self.speakerButton.image
        let prevSelectedState = self.speakerButton.isSelected
        self.speakerButton.image = speakerButtonImage
        self.speakerButton.isSelected = speakerButtonSelected
        callManager.setPreferredInput(input: input) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("VideoCallViewController/selectAudioInput/failed: \(error)")
                    self.speakerButton.image = prevImage
                    self.speakerButton.isSelected = prevSelectedState
                case .success:
                    DDLogError("VideoCallViewController/selectAudioInput/success")
                }
            }
        }
    }

    func setSpeakerOn() {
        DDLogInfo("CallViewController/setSpeakerOn")
        speakerOn = true
        setSpeaker(speaker: speakerOn)
    }

    func setSpeakerOff() {
        DDLogInfo("CallViewController/setSpeakerOff")
        speakerOn = false
        setSpeaker(speaker: speakerOn)
    }

    func setSpeaker(speaker: Bool) {
        speakerOn = speaker
        DDLogInfo("CallViewController/setSpeakerOn/speakerOn: \(speakerOn)")
        callManager.setSpeakerCall(speaker: speakerOn) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("CallViewController/setSpeakerOn/failed: \(error)")
                case .success:
                    self.speakerButton.image = self.speakerImage
                    self.speakerButton.isSelected = self.speakerOn
                }
            }
        }
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
            self.callStatusLabel.isHidden = false
            self.updateCallStatusLabel()
        }
    }

    override func callActive() {
        useCallStatus = false
        DispatchQueue.main.async {
            self.callStatusLabel.isHidden = true
            self.updateCallStatusLabel()
        }
    }

    override func callDurationChanged(seconds: Int) {
        DispatchQueue.main.async {
            self.callStatusLabel.isHidden = true
            self.updateCallStatusLabel()
        }
    }

    override func callEnded() {
    }

    override func callReconnecting() {
        callStatus = .reconnecting
        useCallStatus = true
        DispatchQueue.main.async {
            self.callStatusLabel.isHidden = false
            self.updateCallStatusLabel()
        }
    }

    override func callFailed() {
        callStatus = .failed
        useCallStatus = true
        DispatchQueue.main.async {
            self.callStatusLabel.isHidden = false
            self.updateCallStatusLabel()
        }
    }

    override func callHold(_ hold: Bool) {
        if hold {
            callStatus = .held
        }
        useCallStatus = hold
        DispatchQueue.main.async {
            self.callStatusLabel.isHidden = false
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

    // Always called on the main queue.
    func handleRemoteVideoMuted(muted: Bool) {
        self.remoteRenderer.isEnabled = !muted
        self.remoteBlurView.isHidden = !muted
        self.updateMuteStatusLabel()
    }

    // Always called on the main queue.
    func handleLocalVideoMuted(muted: Bool) {
        self.localRenderer.isEnabled = !muted
        self.localBlurView.isHidden = !muted
        self.updateMuteStatusLabel()
    }

    func didStartReceivingRemoteVideo() {
        DDLogInfo("VideoCallViewController/didStartReceivingRemoteVideo")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stationIdentification.isHidden = true
            self.encryptionLabel.isHidden = true
            self.peerNameLabel.isHidden = true
            self.callStatusLabel.isHidden = true
            self.expandRemoteVideo()
            self.setupHideControlsTimer()
        }
    }

    func expandLocalVideo() {
        DDLogInfo("VideoCallViewController/expandLocalVideo")

        localViewBottomConstraint?.priority = .defaultHigh
        localViewLeadingConstraint?.priority = .defaultHigh
        localViewTrailingConstraint?.priority = .defaultHigh
        localViewTopConstraint?.priority = .defaultHigh
        localRenderer.layer.borderWidth = 0
        localRenderer.layer.cornerRadius = 0
        localRenderer.removeGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(localVideoTapped)))
        localRenderer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(screenTapped)))
        view.sendSubviewToBack(localRenderer)
        view.layoutIfNeeded()

        remoteViewTopConstraint?.priority = .defaultLow
        remoteViewBottomConstraint?.priority = .defaultLow
        remoteViewLeadingConstraint?.priority = .defaultLow
        remoteViewTrailingConstraint?.priority = .defaultLow
        remoteRenderer.layer.borderColor = UIColor.black.withAlphaComponent(0.2).cgColor
        remoteRenderer.layer.borderWidth = 0.5
        remoteRenderer.layer.cornerRadius = 10
        remoteRenderer.removeGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(screenTapped)))
        remoteRenderer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(remoteVideoTapped)))
        UIView.animate(withDuration: 0.5, animations: {
            self.view.layoutIfNeeded()
        })
        expandedVideo = .local
        self.updateMuteStatusLabel()
    }

    func expandRemoteVideo() {
        DDLogInfo("VideoCallViewController/expandRemoteVideo")

        remoteViewTopConstraint?.priority = .defaultHigh
        remoteViewBottomConstraint?.priority = .defaultHigh
        remoteViewLeadingConstraint?.priority = .defaultHigh
        remoteViewTrailingConstraint?.priority = .defaultHigh
        remoteRenderer.layer.borderWidth = 0
        remoteRenderer.layer.cornerRadius = 0
        remoteRenderer.removeGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(remoteVideoTapped)))
        remoteRenderer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(screenTapped)))
        view.sendSubviewToBack(remoteRenderer)
        view.layoutIfNeeded()

        localViewBottomConstraint?.priority = .defaultLow
        localViewLeadingConstraint?.priority = .defaultLow
        localViewTrailingConstraint?.priority = .defaultLow
        localViewTopConstraint?.priority = .defaultLow
        localRenderer.layer.borderColor = UIColor.black.withAlphaComponent(0.2).cgColor
        localRenderer.layer.borderWidth = 0.5
        localRenderer.layer.cornerRadius = 10
        localRenderer.removeGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(screenTapped)))
        localRenderer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(localVideoTapped)))
        UIView.animate(withDuration: 0.5, animations: {
            self.view.layoutIfNeeded()
        })
        expandedVideo = .remote
        self.updateMuteStatusLabel()
    }

    @objc private func localVideoTapped() {
        expandLocalVideo()
    }

    @objc private func remoteVideoTapped() {
        expandRemoteVideo()
    }

    @objc private func screenTapped() {
        hideControls.toggle()
        if !hideControls {
            setupHideControlsTimer()
        } else {
            cancelHideControlsTimer()
        }
    }

    func mirrorVideo(_ mirror: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.5, animations: {
                if mirror {
                    self.localRenderer.transform = CGAffineTransform(scaleX: -1, y: 1)
                } else {
                    self.localRenderer.transform = CGAffineTransform(scaleX: 1, y: 1)
                }
            })
        }
    }
}

extension VideoCallViewController: RTCVideoViewDelegate {
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DDLogInfo("VideoCallViewController/RTCVideoViewDelegate/didChangeVideoSize: \(size)")
    }

}

final class VideoCallViewButton: UIButton {

    struct Style {
        var circleDiameter: CGFloat = 48
        var circleColor: UIColor = UIColor.black.withAlphaComponent(0.6)
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
        self.image = image
        self.style = style
        imageView?.tintColor = .white
        imageView?.translatesAutoresizingMaskIntoConstraints = false
        setImage(image?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        setImage(image?.withTintColor(.black, renderingMode: .alwaysOriginal), for: .selected)
        label.text = title
        insertSubview(circleView, at: 0)
        addSubview(label)
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

    var image: UIImage?
    var style: Style = .normal

    override func setImage(_ image: UIImage?, for state: UIControl.State) {
        let configuredImage = image?.withConfiguration(UIImage.SymbolConfiguration(pointSize: style.iconHeight))
        super.setImage(configuredImage, for: state)
    }

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
        view.layer.cornerRadius = diameter / 2
        view.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        view.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        return view
    }()

    override var isSelected: Bool {
        didSet {
            if isSelected {
                circleView.backgroundColor = UIColor.white
            } else {
                circleView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
        }
    }
}
