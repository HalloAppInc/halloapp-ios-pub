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

class CallViewController: UIViewController {

    var muted: Bool = false
    var speakerOn: Bool = false

    // MARK: View Controller

    var callStatus = "calling"
    let micOffImage = UIImage(systemName: "mic.slash.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
    let micOnImage = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
    let speakerOffImage = UIImage(systemName: "speaker.slash.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
    let speakerOnImage = UIImage(systemName: "speaker.wave.3.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
    let endCallImage = UIImage(systemName: "phone.down.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
    let backImage = UIImage(named: "NavbarBack")?.imageFlippedForRightToLeftLayoutDirection()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapBack), for: [.touchUpInside])
        button.setImage(backImage, for: .normal)
        return button
    }()

    private lazy var callStatusLabel: UILabel = {
        let callStatusLabel = UILabel()
        callStatusLabel.widthAnchor.constraint(equalToConstant: self.view.frame.width).isActive = true
        callStatusLabel.heightAnchor.constraint(equalToConstant: 35.0).isActive = true
        callStatusLabel.text = getCallStatusText()
        callStatusLabel.font = UIFont.systemFont(ofSize: 20.0)
        callStatusLabel.textAlignment = .center
        return callStatusLabel
    }()

    private lazy var micButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(micOnImage, for: .normal)
        button.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 50).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.black.cgColor
        return button
    }()

    private lazy var speakerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(speakerOffImage, for: .normal)
        button.addTarget(self, action: #selector(speakerButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 50).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.black.cgColor
        return button
    }()

    private lazy var endCallButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(endCallImage, for: .normal)
        button.addTarget(self, action: #selector(endCallButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 50).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.black.cgColor
        return button
    }()

    private let peerUserID: UserID
    private var peerPhoneNumber: String {
        if let phoneNumber = MainAppContext.shared.contactStore.pushNumber(peerUserID) {
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
        view.backgroundColor = .feedBackground
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
        buttonPanel.spacing   = 45.0
        buttonPanel.addArrangedSubview(micButton)
        buttonPanel.addArrangedSubview(speakerButton)
        buttonPanel.addArrangedSubview(endCallButton)

        // Text Label
        let peerNameLabel = UILabel()
        peerNameLabel.text = MainAppContext.shared.contactStore.fullName(for: peerUserID, showPushNumber: true)
        peerNameLabel.font = UIFont.boldSystemFont(ofSize: 35.0)
        peerNameLabel.adjustsFontSizeToFitWidth = true
        peerNameLabel.textAlignment = .center

        // Full stack view: contains all the components
        let fullCallView   = UIStackView(arrangedSubviews: [peerNameLabel, callStatusLabel, avatarView, buttonPanel])
        fullCallView.axis  = .vertical
        fullCallView.distribution  = .fillProportionally
        fullCallView.alignment = .center
        fullCallView.spacing   = 16.0
        fullCallView.translatesAutoresizingMaskIntoConstraints = false

        fullCallView.setCustomSpacing(35, after: callStatusLabel)
        fullCallView.setCustomSpacing(185, after: avatarView)

        view.addSubview(fullCallView)

        fullCallView.constrainMargins([.leading, .trailing], to: view)

        if backAction == nil {
            // Center the call view
            fullCallView.constrain([.centerY], to: view)
        } else {
            view.addSubview(backButton)
            backButton.constrainMargins([.top, .leading], to: view)
            backButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            backButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

            // Center the call view if possible (but make sure it's below the back button)
            fullCallView.constrain([.centerY], to: view, priority: .defaultHigh)
            fullCallView.topAnchor.constraint(greaterThanOrEqualTo: backButton.bottomAnchor).isActive = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CallViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    private func getCallStatusText() -> String {
        if isOutgoing {
            return callStatus + " " + peerPhoneNumber + "..."
        } else {
            return peerPhoneNumber + "..."
        }
    }

    private func updateCallStatusLabel() {
        DDLogInfo("CallViewController/updateCallStatusLabel")
        if isCallActive {
            callStatusLabel.text = durationString(seconds: 0)
        } else {
            callStatusLabel.text = getCallStatusText()
        }
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
                    if self.muted {
                        self.micButton.setImage(self.micOffImage, for: .normal)
                    } else {
                        self.micButton.setImage(self.micOnImage, for: .normal)
                    }
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
                    if self.speakerOn {
                        self.speakerButton.setImage(self.speakerOnImage, for: .normal)
                    } else {
                        self.speakerButton.setImage(self.speakerOffImage, for: .normal)
                    }
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
    func callStarted() {
    }

    func callRinging() {
        callStatus = "ringing"
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callConnected() {
        callStatus = "connecting"
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callActive() {
        DispatchQueue.main.async {
            self.updateCallStatusLabel()
        }
    }

    func callDurationChanged(seconds: Int) {
        DispatchQueue.main.async {
            self.callStatusLabel.text = self.durationString(seconds: seconds)
        }
    }

    func callEnded() {
    }
}
