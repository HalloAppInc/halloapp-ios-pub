//
//  CallViewController.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
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
}

class CallViewController: UIViewController {

    var muted: Bool = false
    var speakerOn: Bool = false

    // MARK: View Controller

    var callStatus = CallStatus.calling
    var useCallStatus: Bool = false
    let micOffImage = UIImage(systemName: "mic.slash.fill")
    let micOnImage = UIImage(systemName: "mic.fill")
    let speakerOffImage = UIImage(systemName: "speaker.slash.fill")
    let speakerOnImage = UIImage(systemName: "speaker.wave.3.fill")
    let endCallImage = UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate)
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
        let button = CallViewButton(image: micOnImage, title: Localizations.callMute)
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
        let button = CallViewButton(image: speakerOffImage, title: Localizations.callSpeaker)
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
    private var callDurationSec: Int {
        get {
            return Int(callManager.callDurationMs / 1000)
        }
    }

    init(peerUserID: UserID, isOutgoing: Bool, backAction: (() -> Void)?) {
        DDLogInfo("CallViewController/init/peerUserID: \(peerUserID)/isOutgoing: \(isOutgoing)")
        self.peerUserID = peerUserID
        self.callManager = MainAppContext.shared.callManager
        self.isOutgoing = isOutgoing
        self.backAction = backAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        DDLogInfo("CallViewController/viewDidLoad")
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let avatarView = AvatarView()
        avatarView.configure(with: peerUserID, using: MainAppContext.shared.avatarStore)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor).isActive = true

        // Action Buttons related stack view
        let buttonPanel = UIStackView()
        buttonPanel.translatesAutoresizingMaskIntoConstraints = false
        buttonPanel.axis = .horizontal
        buttonPanel.distribution  = .equalSpacing
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
        peerNameLabel.text = MainAppContext.shared.contactStore.fullName(for: peerUserID, showPushNumber: true)
        peerNameLabel.font = .systemFont(ofSize: 30)
        peerNameLabel.textColor = .white
        peerNameLabel.adjustsFontSizeToFitWidth = true
        peerNameLabel.textAlignment = .center
        peerNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Full stack view: contains all the components
        let fullCallView = UIStackView(arrangedSubviews: [stationIdentification, avatarView, peerNameLabel, callStatusLabel, buttonPanel])
        fullCallView.translatesAutoresizingMaskIntoConstraints = false
        fullCallView.axis = .vertical
        fullCallView.distribution = .fill
        fullCallView.alignment = .center
        fullCallView.spacing = 36
        fullCallView.setCustomSpacing(8, after: peerNameLabel)

        view.addSubview(fullCallView)
        view.addSubview(endCallButton)

        fullCallView.constrain(anchor: .leading, to: view, constant: 36)
        fullCallView.constrain(anchor: .trailing, to: view, constant: -36)
        buttonPanel.constrain(dimension: .width, to: fullCallView)

        endCallButton.constrain([.centerX], to: view)
        NSLayoutConstraint.activate([
            // Give end call button at least 16px of top padding...
            endCallButton.topAnchor.constraint(greaterThanOrEqualTo: fullCallView.bottomAnchor, constant: 16),
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
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewWillAppear")
        super.viewWillAppear(animated)
        updateCallStatusLabel()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    private func getCallStatusText() -> String {
        if isCallActive {
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
        muted = !muted
        DDLogInfo("CallViewController/micButtonTapped/muted: \(muted)")
        callManager.muteCall(muted: muted) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    DDLogError("CallViewController/endCall/failed: \(error)")
                case .success:
                    let micStatusImage = self.muted ? self.micOffImage : self.micOnImage
                    self.micButton.image = micStatusImage
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
                    let speakerStatusImage = self.speakerOn ? self.speakerOnImage : self.speakerOffImage
                    self.speakerButton.image = speakerStatusImage
                }
            }
        }
    }

    @objc func endCallButtonTapped(sender: UIButton) {
        DDLogInfo("CallViewController/endCallButtonTapped")
        callManager.endCall(reason: .ended) { [weak self] result in
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
}

extension CallViewController: CallViewDelegate {

    func startedOutgoingCall(call: Call) {
    }

    func callAccepted(call: Call) {
    }

    func callStarted() {
    }

    func callRinging() {
        callStatus = .ringing
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callConnected() {
        callStatus = .connecting
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callActive() {
        useCallStatus = false
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callDurationChanged(seconds: Int) {
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callEnded() {
    }

    func callReconnecting() {
        callStatus = .reconnecting
        useCallStatus = true
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callFailed() {
        callStatus = .failed
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
        circleView.constrain([.top, .leading, .trailing], to: self)
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
}

private extension Localizations {
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
            return NSLocalizedString("call.status.failed", value: "failed", comment: "Status displayed when call fails.")
        }
    }
}
