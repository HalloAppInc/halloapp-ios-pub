//
//  CallViewController.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CoreCommon
import UIKit
import SwiftUI
import Combine
import CocoaLumberjackSwift

enum CallStatus {
    case calling
    case ringing
    case connecting
    case reconnecting
    case failed
    case held
    case busy
    case muted
}

// TODO: consider making this only a protocol instead of an abstract class.
class CallViewController: UIViewController, CallViewDelegate {
    private var type: CallType

    init(type: CallType) {
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startedOutgoingCall(call: Call) {
        fatalError("must-override")
    }

    func callAccepted(call: Call) {
        fatalError("must-override")
    }

    func callStarted() {
        fatalError("must-override")
    }

    func callRinging() {
        fatalError("must-override")
    }

    func callConnected() {
        fatalError("must-override")
    }

    func callActive() {
        fatalError("must-override")
    }

    func callDurationChanged(seconds: Int) {
        fatalError("must-override")
    }

    func callEnded() {
        fatalError("must-override")
    }

    func callReconnecting() {
        fatalError("Must Override")
    }

    func callFailed() {
        fatalError("Must Override")
    }

    func callHold(_ hold: Bool) {
        fatalError("Must Override")
    }

    func callBusy() {
        fatalError("Must Override")
    }
}

class AudioCallViewController: CallViewController {

    var isLocalAudioMuted: Bool = false
    var speakerOn: Bool = false

    // MARK: View Controller

    var callStatus = CallStatus.calling
    var useCallStatus: Bool = false
    let micImage = UIImage(systemName: "mic.slash.fill")
    let speakerImage = UIImage(systemName: "speaker.wave.3.fill")
    let endCallImage = UIImage(systemName: "phone.down.fill")?.withRenderingMode(.alwaysTemplate)
    let chatImage = UIImage(systemName: "message.fill")
    let backImage = UIImage(named: "NavbarBack")?.imageFlippedForRightToLeftLayoutDirection().withRenderingMode(.alwaysTemplate)

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

    private lazy var micButton: CallViewButton = {
        let button = CallViewButton(image: micImage, title: Localizations.callMute)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var chatButton: CallViewButton = {
        let button = CallViewButton(image: chatImage, title: Localizations.callChat)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(chatButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var speakerButton: CallViewButton = {
        let button = CallViewButton(image: speakerImage, title: Localizations.callSpeaker)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(speakerButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var endCallButton: CallViewButton = {
        let button = CallViewButton(image: endCallImage, title: Localizations.callEnd, style: .destructive)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(endCallButtonTapped), for: .touchUpInside)
        return button
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
    private var isCallAnswered: Bool {
        get {
            return callManager.activeCall?.isAnswered ?? false
        }
    }
    private var isCallOnHold: Bool {
        get {
            return callManager.activeCall?.isOnHold ?? false
        }
    }
    private var isCallRemoteAudioMuted: Bool {
        get {
            return callManager.activeCall?.isRemoteAudioMuted.value ?? false
        }
    }
    private var callDurationSec: Int {
        get {
            return Int(callManager.callDurationMs / 1000)
        }
    }
    private var cancellableSet = Set<AnyCancellable>()

    init(peerUserID: UserID, isOutgoing: Bool, backAction: (() -> Void)?) {
        DDLogInfo("CallViewController/init/peerUserID: \(peerUserID)/isOutgoing: \(isOutgoing)")
        self.peerUserID = peerUserID
        self.callManager = MainAppContext.shared.callManager
        self.isOutgoing = isOutgoing
        self.backAction = backAction
        super.init(type: .audio)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        DDLogInfo("CallViewController/viewDidLoad")
        super.viewDidLoad()
        view.backgroundColor = .black.withAlphaComponent(0.6)
        view.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let blurEffect = UIBlurEffect(style: UIBlurEffect.Style.systemThinMaterialDark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = view.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurEffectView)

        let avatarView = AvatarView()
        avatarView.configure(with: peerUserID, using: MainAppContext.shared.avatarStore)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true

        // Action Buttons related stack view
        let buttonPanel = UIStackView()
        buttonPanel.translatesAutoresizingMaskIntoConstraints = false
        buttonPanel.axis = .horizontal
        buttonPanel.distribution  = .fillEqually
        buttonPanel.alignment = UIStackView.Alignment.center
        buttonPanel.addArrangedSubview(micButton)
        buttonPanel.addArrangedSubview(chatButton)
        buttonPanel.addArrangedSubview(speakerButton)
        if backAction == nil {
            // Chat action currently requires being able to exit call screen
            chatButton.isHidden = true
        }

        // Text Label
        let peerNameLabel = UILabel()
        peerNameLabel.text = MainAppContext.shared.contactStore.fullName(for: peerUserID, showPushNumber: true, in: MainAppContext.shared.contactStore.viewContext)
        peerNameLabel.font = .systemFont(ofSize: 30)
        peerNameLabel.textColor = .white
        peerNameLabel.adjustsFontSizeToFitWidth = true
        peerNameLabel.textAlignment = .center
        peerNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Text Label
        let encryptionLabel = UILabel()
        encryptionLabel.text = "🔒 " + Localizations.callEncryption
        encryptionLabel.font = .systemFont(ofSize: 15)
        encryptionLabel.textColor = .white
        encryptionLabel.adjustsFontSizeToFitWidth = true
        encryptionLabel.textAlignment = .center
        encryptionLabel.translatesAutoresizingMaskIntoConstraints = false

        // Full stack view: contains all the components
        let fullCallView = UIStackView(arrangedSubviews: [stationIdentification, encryptionLabel, avatarView, peerNameLabel, callStatusLabel])
        fullCallView.translatesAutoresizingMaskIntoConstraints = false
        fullCallView.axis = .vertical
        fullCallView.distribution = .fill
        fullCallView.alignment = .center
        fullCallView.spacing = 30
        fullCallView.setCustomSpacing(8, after: stationIdentification)
        fullCallView.setCustomSpacing(8, after: peerNameLabel)

        view.addSubview(fullCallView)
        view.addSubview(buttonPanel)
        view.addSubview(endCallButton)

        fullCallView.constrain(anchor: .leading, to: view, constant: 36)
        fullCallView.constrain(anchor: .trailing, to: view, constant: -36)

        buttonPanel.topAnchor.constraint(equalTo: fullCallView.bottomAnchor, constant: 36).isActive = true
        buttonPanel.constrain(anchor: .leading, to: view, constant: 16)
        buttonPanel.constrain(anchor: .trailing, to: view, constant: -16)

        endCallButton.constrain([.centerX], to: view)
        NSLayoutConstraint.activate([
            // Give end call button at least 16px of top padding...
            endCallButton.topAnchor.constraint(greaterThanOrEqualTo: buttonPanel.bottomAnchor, constant: 16),
            // ... and make sure bottom is inside margins...
            endCallButton.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor),
            // ... but has at most 64px of bottom padding.
            endCallButton.bottomAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor, constant: -64),
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
                activeCall.isRemoteAudioMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    guard activeCall.isActive else { return }
                    self.callStatus = .muted
                    self.useCallStatus = true
                    DispatchQueue.main.async {
                        self.updateCallStatusLabel()
                    }
                })

            cancellableSet.insert(
                activeCall.isLocalAudioMuted.sink { [weak self] muted in
                    guard let self = self else { return }
                    self.isLocalAudioMuted = muted
                })
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewWillAppear")
        super.viewWillAppear(animated)
        updateCallStatusLabel()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewDidDisappear")
        super.viewDidDisappear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
    }

    private func getCallStatusText() -> String {
        if isCallOnHold && useCallStatus {
            return Localizations.callStatus(callStatus, for: peerPhoneNumber)
        } else if isCallActive && isCallRemoteAudioMuted {
            return Localizations.callStatus(callStatus, for: peerPhoneNumber)
        } else if isCallActive {
            return durationString(seconds: callDurationSec)
        } else if isOutgoing || useCallStatus {
            return Localizations.callStatus(callStatus, for: peerPhoneNumber)
        } else {
            return Localizations.callIncoming
        }
    }

    private func updateCallStatusLabel() {
        callStatusLabel.text = getCallStatusText()
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

    @objc func chatButtonTapped(sender: UIButton) {
        MainAppContext.shared.openChatThreadRequest.send(peerUserID)
        backAction?()
    }

    @objc func micButtonTapped(sender: UIButton) {
        isLocalAudioMuted = !isLocalAudioMuted
        DDLogInfo("CallViewController/micButtonTapped/muted: \(isLocalAudioMuted)")
        callManager.muteAudio(muted: isLocalAudioMuted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("CallViewController/endCall/failed: \(error)")
                case .success:
                    self.micButton.isSelected = self.isLocalAudioMuted
                }
            }
        }
    }

    @objc func speakerButtonTapped(sender: UIButton) {
        speakerOn = !speakerOn
        DDLogInfo("CallViewController/speakerButtonTapped/speakerOn: \(speakerOn)")
        callManager.setSpeakerCall(speaker: speakerOn) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("CallViewController/endCall/failed: \(error)")
                case .success:
                    self.speakerButton.isSelected = self.speakerOn
                }
            }
        }
    }

    @objc func endCallButtonTapped(sender: UIButton) {
        DDLogInfo("CallViewController/endCallButtonTapped")
        let endReason: EndCallReason
        if isOutgoing && !isCallAnswered {
            endReason = .canceled
        } else {
            endReason = .ended
        }
        callManager.endCall(reason: endReason) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("CallViewController/endCall/failed: \(error)")
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
}

final class CallViewButton: UIControl {

    struct Style {
        var circleDiameter: CGFloat = 80
        var circleColor: UIColor = UIColor.white.withAlphaComponent(0.1)
        var iconHeight: CGFloat = 32

        static var normal: Style {
            Style()
        }

        static var destructive: Style {
            Style(
                circleDiameter: 72,
                circleColor: UIColor(red: 235.0/255, green: 77.0/255, blue: 61.0/255, alpha: 1),
                iconHeight: 26)
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
        label.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 4).isActive = true
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

    override var isSelected: Bool {
        didSet {
            if isSelected {
                circleView.backgroundColor = UIColor.white
                imageView.image  = image?.withTintColor(.black, renderingMode: .alwaysOriginal)
            } else {
                circleView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
                imageView.image  = image?.withTintColor(.white, renderingMode: .alwaysOriginal)
            }
        }
    }
}

extension Localizations {
    static var callMute: String {
        NSLocalizedString("call.button.mute", value: "mute", comment: "Label for button that toggles mute status during call")
    }
    static var callChat: String {
        NSLocalizedString("call.button.chat", value: "chat", comment: "Label for button that opens chat during call")
    }
    static var callSpeaker: String {
        NSLocalizedString("call.button.speaker", value: "speaker", comment: "Label for button that toggles speakerphone status during call")
    }
    static var callEnd: String {
        NSLocalizedString("call.button.end", value: "end call", comment: "Label for button that ends call")
    }
    static var callIncoming: String {
        NSLocalizedString("call.status.incoming", value: "incoming call", comment: "Status displayed when incoming call starts")
    }
    static var callEncryption: String {
        NSLocalizedString("call.encryption.text", value: "End-to-end encrypted", comment: "Text indicating that calls are end-to-end encrypted")
    }
    static func callStatus(_ status: CallStatus, for phoneNumber: String) -> String {
        switch status {
        case .calling:
            return NSLocalizedString("call.status.calling", value: "calling...", comment: "Status displayed when outgoing call starts")
        case .ringing:
            return NSLocalizedString("call.status.ringing", value: "ringing...", comment: "Status displayed while outgoing call is ringing")
        case .connecting:
            return NSLocalizedString("call.status.connecting", value: "connecting...", comment: "Status displayed while call is connecting")
        case .reconnecting:
            return NSLocalizedString("call.status.reconnecting", value: "reconnecting...", comment: "Status displayed when reconnecting during call")
        case .failed:
            return NSLocalizedString("call.status.failed", value: "call failed", comment: "Status displayed when call fails.")
        case .held:
            return NSLocalizedString("call.status.held", value: "on hold", comment: "Status displayed when call is on hold.")
        case .busy:
            return NSLocalizedString("call.status.busy", value: "on another call", comment: "Status displayed when the other side is busy.")
        case .muted:
            return NSLocalizedString("call.status.muted", value: "call muted", comment: "Status displayed when the other side mutes the audio.")
        }
    }
    static func remoteMuteStatus(isAudioMuted: Bool, isVideoMuted: Bool, for peerName: String) -> String {
        if isAudioMuted && isVideoMuted {
            let formatString = NSLocalizedString("call.mute.remote.audio.video", value: "%@'s camera and microphone are off", comment: "Status display when peer mutes both audio and video during a call.")
            return String(format: formatString, peerName)
        } else if isAudioMuted {
            let formatString = NSLocalizedString("call.mute.remote.audio", value: "%@ muted this call", comment: "Status display when peer mutes audio during a call.")
            return String(format: formatString, peerName)
        } else if isVideoMuted {
            let formatString = NSLocalizedString("call.mute.remote.video", value: "%@'s camera is off", comment: "Status display when peer mutes video during a call.")
            return String(format: formatString, peerName)
        } else {
            return ""
        }
    }
    static func localMuteStatus(isAudioMuted: Bool, isVideoMuted: Bool) -> String {
        if isAudioMuted && isVideoMuted {
            return NSLocalizedString("call.mute.local.audio.video", value: "camera and microphone are off", comment: "Status display when user mutes their own audio and video during a call.")
        } else if isAudioMuted {
            return NSLocalizedString("call.mute.local.audio", value: "microphone is off", comment: "Status display when user mutes their own audio during a call.")
        } else if isVideoMuted {
            return NSLocalizedString("call.mute.local.video", value: "camera is off", comment: "Status display when user mutes their own video during a call.")
        } else {
            return ""
        }
    }
}
