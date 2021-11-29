//
//  CallManager.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import SwiftUI
import Combine
import CallKit
import CocoaLumberjackSwift
import WebRTC
import AVFoundation

protocol CallViewDelegate: AnyObject {
    func callStarted()
    func callRinging()
    func callActive()
    func callDurationChanged(seconds: Int)
    func callEnded()
}

public struct CallDetails {
    var callID: CallID
    var peerUserID: UserID
}

final class CallManager: NSObject, CXProviderDelegate {
    // TODO: listen to connection state changes and act accordingly.

    // The app's provider configuration, representing its CallKit capabilities
    static var providerConfiguration: CXProviderConfiguration {
        let providerConfiguration = CXProviderConfiguration(localizedName: "HalloApp")
        providerConfiguration.supportsVideo = false
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]
        providerConfiguration.includesCallsInRecents = true
        return providerConfiguration
    }

    let callController = CXCallController()
    private let provider: CXProvider
    public var service: HalloService
    public var activeCall: Call? {
        didSet {
            if activeCall == nil {
                callDurationSec = 0
                callTimer?.invalidate()
                callTimer = nil
                cancelTimer?.cancel()
                cancelTimer = nil
                endReason = nil
            }
            isAnyCallActive.send(activeCall)
        }
    }
    public var callViewDelegate: CallViewDelegate?
    public var rtcAudioSession: RTCAudioSession = RTCAudioSession.sharedInstance()
    private var cancelTimer: DispatchSourceTimer?
    private var callTimer: Timer?
    private var callDurationSec: Int = 0
    private var endReason: EndCallReason? = nil
    private var callRingtonePlayer: AVAudioPlayer?

    // UUID to callID and peerUserID map: for all possible calls.
    // Call UUID can be generated from callID in a deterministic way.
    private var callDetailsMap = [UUID: CallDetails]()

    // Properties computed from activeCall details.
    public var activeCallID: CallID? {
        return activeCall?.callID
    }
    public var isOutgoing: Bool? {
        return activeCall?.isOutgoing
    }
    public var peerUserID: UserID? {
        if let activeCallID = activeCallID,
           let details = callDetailsMap[activeCallID.callUUID] {
            return details.peerUserID
        }
        return nil
    }

    public let isAnyCallActive = PassthroughSubject<Call?, Never>()

    // Initialize
    init(service: HalloService) {
        self.service = service
        self.provider = CXProvider(configuration: CallManager.providerConfiguration)
        super.init()
        self.provider.setDelegate(self, queue: .main)
        self.service.callDelegate = self
    }


    // MARK: User-Initiated Actions

    func startCall(to peerUserID: String, completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogError("CallManager/startCall/callID:\(callID)/failed call to \(peerUserID)")
            completion(.failure(.alreadyInCall))
        } else {
            let callID = PacketID.generate()
            callDetailsMap[callID.callUUID] = CallDetails(callID: callID, peerUserID: peerUserID)
            let handle = handle(for: peerUserID)
            DDLogInfo("CallManager/startCall/create/callID: \(callID)/handleValue: \(handle.value)")
            let startCallAction = CXStartCallAction(call: callID.callUUID, handle: handle)
            let transaction = CXTransaction()
            transaction.addAction(startCallAction)
            requestTransaction(transaction, completion: completion)
        }
    }

    func answerCall(completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogInfo("CallManager/answerCall/callID: \(callID)")
            let answerCallAction = CXAnswerCallAction(call: callID.callUUID)
            let transaction = CXTransaction()
            transaction.addAction(answerCallAction)
            requestTransaction(transaction, completion: completion)
        } else {
            DDLogError("CallManager/answerCall/callID is nil")
            completion(.failure(.noActiveCall))
        }
    }

    func endCall(reason: EndCallReason, completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogInfo("CallManager/endCall/callID: \(callID)")
            endReason = reason
            let endCallAction = CXEndCallAction(call: callID.callUUID)
            let transaction = CXTransaction()
            transaction.addAction(endCallAction)
            requestTransaction(transaction, completion: completion)
        } else {
            DDLogError("CallManager/endCall/callID is nil")
            completion(.failure(.noActiveCall))
        }
    }

    func muteCall(muted: Bool, completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogInfo("CallManager/muteCall/callID: \(callID)/muted: \(muted)")
            let muteCallAction = CXSetMutedCallAction(call: callID.callUUID, muted: muted)
            let transaction = CXTransaction()
            transaction.addAction(muteCallAction)
            requestTransaction(transaction, completion: completion)
        } else {
            DDLogError("CallManager/muteCall/callID is nil")
            completion(.failure(.noActiveCall))
        }
    }

    func setHeld(onHold: Bool, completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogInfo("CallManager/setHeld/callID: \(callID)/onHold: \(onHold)")
            let setHeldCallAction = CXSetHeldCallAction(call: callID.callUUID, onHold: onHold)
            let transaction = CXTransaction()
            transaction.addAction(setHeldCallAction)
            requestTransaction(transaction, completion: completion)
        } else {
            DDLogError("CallManager/setHeld/callID is nil")
            completion(.failure(.noActiveCall))
        }
    }

    func setSpeakerCall(speaker: Bool, completion: @escaping (Result<Void, CallError>) -> Void) {
        if let callID = activeCallID {
            DDLogInfo("CallManager/setSpeakerCall/callID: \(callID)/speaker: \(speaker)")
            speaker ? activeCall?.speakerOn() : activeCall?.speakerOff()
            completion(.success(()))
        } else {
            DDLogError("CallManager/setSpeakerCall/callID is nil")
            completion(.failure(.noActiveCall))
        }
    }


    // MARK: Private functions

    private func requestTransaction(_ transaction: CXTransaction, completion: ((Result<Void, CallError>) -> Void)? = nil) {
        callController.request(transaction) { error in
            if let error = error {
                DDLogError("CallManager/requestTransaction/Error requesting transaction: \(transaction)/error: \(error)")
                completion?(.failure(.systemError))
            } else {
                completion?(.success(()))
            }
        }
    }

    private func handle(for peerUserID: UserID) -> CXHandle {
        let handleValue = MainAppContext.shared.contactStore.fullNameIfAvailable(for: peerUserID, ownName: nil, showPushNumber: true) ?? Localizations.unknownContact
        return CXHandle(type: .generic, value: handleValue)
    }

    private func resetState() {
        DDLogInfo("CallManager/resetState/clearing whole state and ending calls.")
        // We should reset our whole state.
        callDetailsMap.removeAll()
        cancelTimer?.cancel()
        cancelTimer = nil
        activeCall?.end(reason: .systemError)
        activeCall = nil
        callViewDelegate?.callEnded()
    }

    private func endActiveCall(reason: EndCallReason) {
        if let activeCallID = activeCallID {
            callDetailsMap[activeCallID.callUUID] = nil
        }
        cancelTimer?.cancel()
        cancelTimer = nil
        activeCall?.end(reason: reason)
        activeCall = nil
        callViewDelegate?.callEnded()
    }

    private func startCancelTimer() {
        DDLogInfo("CallManager/startCancelTimer/begin")
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            DDLogInfo("CallManager/startCancelTimer/endCall now")
            self.endCall(reason: .timeout) { _ in }
        })
        timer.schedule(deadline: .now() + DispatchTimeInterval.seconds(ServerProperties.callWaitTimeoutSec))
        timer.resume()
        cancelTimer = timer
    }

    private func startCallDurationTimer() {
        DDLogInfo("CallManager/startCallDurationTimer")
        DispatchQueue.main.async {
            self.callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                self.callDurationSec += 1
                self.callViewDelegate?.callDurationChanged(seconds: self.callDurationSec)
            }
        }
    }

    // MARK: ProviderDelegate
    // TODO: Fulfill actions only on success responses from server - track iq results and message-acks.

    func providerDidReset(_ provider: CXProvider) {
        DDLogInfo("CallManager/providerDidReset/\(provider.description)")
        // We should reset our whole state.
        resetState()
    }

    func providerDidBegin(_ provider: CXProvider) {
        DDLogInfo("CallManager/providerDidBegin/\(provider.description)")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        DDLogInfo("CallManager/CXStartCallAction/callUUID: \(action.callUUID)/begin")
        if activeCallID == nil,
           let details = callDetailsMap[action.callUUID] {
            service.getCallServers(id: details.callID, for: details.peerUserID, callType: .audio) { [weak self] callServersResult in
                guard let self = self else { action.fail(); return }
                switch callServersResult {
                case .success(let callServers):
                    let iceServers = WebRTCClient.getIceServers(stunServers: callServers.stunServers, turnServers: callServers.turnServers)
                    self.activeCall = Call(id: details.callID, peerUserID: details.peerUserID, iceServers: iceServers, isOutgoing: true)
                    self.activeCall?.stateDelegate = self
                    DDLogInfo("CallManager/CXStartCallAction/callID: \(details.callID)/to: \(details.peerUserID)/iceServers success")
                    self.activeCall?.start { [weak self] success in
                        guard let self = self else { action.fail(); return }
                        DDLogInfo("CallManager/CXStartCallAction/result: \(success)")
                        if success {
                            action.fulfill()
                        } else {
                            DDLogError("CallManager/CXStartCallAction/failed")
                            self.resetState()
                            action.fail()
                        }
                    }
                case .failure(let error) :
                    DDLogError("CallManager/CXStartCallAction/failed: \(error.localizedDescription)")
                    self.resetState()
                    action.fail()
                }
            }
        } else {
            DDLogError("CallManager/CXStartCallAction/callUUID: \(action.callUUID)/unexpected failure")
            resetState()
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        DDLogInfo("CallManager/CXAnswerCallAction/\(action.callUUID)/begin")
        if let details = callDetailsMap[action.callUUID],
           details.callID == activeCallID {
            activeCall?.answer { [weak self] success in
                guard let self = self else { action.fail(); return }
                if success {
                    DDLogInfo("CallManager/CXAnswerCallAction/result: \(success)")
                    action.fulfill()
                } else {
                    DDLogError("CallManager/CXAnswerCallAction/failed")
                    self.resetState()
                    action.fail()
                }
            }
        } else {
            DDLogError("CallManager/CXAnswerCallAction/callUUID: \(action.callUUID)/unexpected failure")
            resetState()
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        DDLogInfo("CallManager/CXEndCallAction/\(action.callUUID)/begin")
        if let details = callDetailsMap[action.callUUID],
           details.callID == activeCallID {
            endActiveCall(reason: endReason ?? EndCallReason.ended)
            DDLogInfo("CallManager/CXEndCallAction/success")
            action.fulfill()
        } else {
            DDLogError("CallManager/CXEndCallAction/failed")
            resetState()
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        DDLogInfo("CallManager/CXSetMutedCallAction/\(action.callUUID)/begin")
        if let details = callDetailsMap[action.callUUID],
           details.callID == activeCallID {
            action.isMuted ? activeCall?.muteAudio() : activeCall?.unmuteAudio()
            DDLogInfo("CallManager/CXSetMutedCallAction/success")
            action.fulfill()
        } else {
            DDLogError("CallManager/CXSetMutedCallAction/failed")
            resetState()
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        DDLogError("CallManager/timedOutPerforming/\(action.description) - unimplemented")
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        DDLogError("CallManager/CXSetHeldCallAction/\(action.callUUID) - unimplemented")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        DDLogInfo("CallManager/didActivate/\(audioSession.description)")
        rtcAudioSession.audioSessionDidActivate(audioSession)
        rtcAudioSession.isAudioEnabled = true
        if isOutgoing ?? false {
            playCallRingtone()
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        DDLogInfo("CallManager/didDeactivate/\(audioSession.description)")
        rtcAudioSession.audioSessionDidDeactivate(audioSession)
        rtcAudioSession.isAudioEnabled = false
    }


    // MARK: Report to Provider

    func reportIncomingCall(id callID: CallID, from peerUserID: UserID, completion: @escaping (Result<Void, CallError>) -> Void) {
        DDLogInfo("CallManager/reportIncomingCall/callID: \(callID)/peerUserID: \(peerUserID)")
        let update = CXCallUpdate()
        update.remoteHandle = handle(for: peerUserID)
        provider.reportNewIncomingCall(with: callID.callUUID, update: update) { error in
            if let error = error {
                DDLogError("CallManager/reportNewIncomingCall/callID: \(callID)/error: \(error)")
                completion(.failure(.systemError))
            } else {
                DDLogInfo("CallManager/reportNewIncomingCall/callID: \(callID)/success")
                completion(.success(()))
            }
        }
    }

    func reportCallEnded(id callID: CallID) {
        DDLogInfo("CallManager/reportCallEnded/callID: \(callID)")
        provider.reportCall(with: callID.callUUID, endedAt: nil, reason: .remoteEnded)
    }

    func reportCallConnecting(id callID: CallID) {
        DDLogInfo("CallManager/reportCallConnecting/callID: \(callID)")
        provider.reportOutgoingCall(with: callID.callUUID, startedConnectingAt: nil)
    }

    func reportCallConnected(id callID: CallID) {
        DDLogInfo("CallManager/reportCallConnected/callID: \(callID)")
        provider.reportOutgoingCall(with: callID.callUUID, connectedAt: nil)
    }

    // MARK: Ringtone
    private func setupCallRingtone() {
        DDLogInfo("CallManager/setupCallRingtone")
        do {
            // Loop ringtone
            callRingtonePlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "us_ringback_tone", ofType: "mp3")!))
            callRingtonePlayer?.prepareToPlay()
            callRingtonePlayer?.numberOfLoops = -1
        } catch {
            DDLogError("CallManager/setCallRingtone/failed: \(error)")
        }
    }

    private func playCallRingtone() {
        DDLogInfo("CallManager/playCallRingtone/\(String(describing: callRingtonePlayer))")
        if callRingtonePlayer == nil {
            setupCallRingtone()
        }
        callRingtonePlayer?.play()
    }

    private func stopCallRingtone() {
        DDLogInfo("CallManager/stopCallRingtone/\(String(describing: callRingtonePlayer))")
        callRingtonePlayer?.stop()
        callRingtonePlayer = nil
    }

}


extension CallManager: HalloCallDelegate {
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIncomingCall incomingCall: Server_IncomingCall) {
        DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall/begin")
        let callID = incomingCall.callID
        let webrtcOffer = incomingCall.webrtcOffer

        let reportIncomingCallCompletion: (() -> Void) = {
            let encryptedData = EncryptedData(data: webrtcOffer.encPayload, identityKey: webrtcOffer.publicKey.isEmpty ? nil : webrtcOffer.publicKey, oneTimeKeyId: Int(webrtcOffer.oneTimePreKeyID))
            // TODO: Unify all these encryption and decryption api: easier to track counters.
            AppContext.shared.messageCrypter.decrypt(encryptedData, from: peerUserID) { result in
                switch result {
                case .success(let decryptedData):
                    DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall/decrypt/success")
                    if let sdpInfo = String(data: decryptedData, encoding: .utf8) {
                        self.activeCall?.didReceiveIncomingCall(sdpInfo: sdpInfo,
                                                                stunServers: incomingCall.stunServers,
                                                                turnServers: incomingCall.turnServers) { [weak self] result in
                            guard let self = self else { return }
                            if !result {
                                self.endCall(reason: .systemError) { _ in }
                            }
                        }
                    } else {
                        self.endCall(reason: .systemError) { _ in }
                    }
                case .failure(let failure):
                    DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall/decrypt/failure: \(failure)")
                    self.endCall(reason: .decryptionError) { _ in }
                }
            }
        }

        // Try to decrypt offer if no call is active and report to callkit provider.
        if activeCallID == incomingCall.callID {
            DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall: \(callID) from: \(peerUserID) duplicate packet")
        } else if activeCall != nil {
            MainAppContext.shared.service.endCall(id: callID, to: peerUserID, reason: .busy)
            DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall: \(callID) from: \(peerUserID)/end with reason busy")
        } else {
            DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall: \(callID)/callUUID: \(callID.callUUID)")
            callDetailsMap[callID.callUUID] = CallDetails(callID: callID, peerUserID: peerUserID)
            let iceServers = WebRTCClient.getIceServers(stunServers: incomingCall.stunServers, turnServers: incomingCall.turnServers)
            activeCall = Call(id: callID, peerUserID: peerUserID, iceServers: iceServers)
            activeCall?.stateDelegate = self
            reportIncomingCall(id: callID, from: peerUserID) { error in
                switch error {
                case .success:
                    DDLogInfo("CallManager/HalloCallDelegate/didReceiveIncomingCall/system/success")
                    reportIncomingCallCompletion()
                case .failure(let error):
                    DDLogError("CallManager/HalloCallDelegate/didReceiveIncomingCall/system/failed: \(error)")
                }
            }
        }
    }

    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveAnswerCall answerCall: Server_AnswerCall) {
        DDLogInfo("CallManager/HalloCallDelegate/didReceiveAnswerCall/begin")
        let callID = answerCall.callID
        let webrtcAnswer = answerCall.webrtcAnswer

        // Try and decrypt answer and then report to callkit provider.
        if activeCallID == callID {
            let encryptedData = EncryptedData(data: webrtcAnswer.encPayload, identityKey: webrtcAnswer.publicKey.isEmpty ? nil : webrtcAnswer.publicKey, oneTimeKeyId: Int(webrtcAnswer.oneTimePreKeyID))
            AppContext.shared.messageCrypter.decrypt(encryptedData, from: peerUserID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let decryptedData):
                    DDLogInfo("CallManager/HalloCallDelegate/didReceiveAnswerCall/decrypt/success")
                    self.reportCallConnected(id: callID)
                    self.activeCall?.didReceiveAnswer(sdpInfo: String(data: decryptedData, encoding: .utf8)!)
                case .failure(let failure):
                    DDLogInfo("CallManager/HalloCallDelegate/didReceiveAnswerCall/decrypt/failure: \(failure)")
                    MainAppContext.shared.service.endCall(id: callID, to: peerUserID, reason: .decryptionError)
                }
            }
        } else {
            DDLogError("CallManager/HalloCallDelegate/didReceiveAnswerCall: \(callID) from: \(peerUserID)/end with reason busy")
            MainAppContext.shared.service.endCall(id: callID, to: peerUserID, reason: .busy)
        }
    }

    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveCallRinging callRinging: Server_CallRinging) {
        DDLogInfo("CallManager/HalloCallDelegate/didReceiveCallRinging/begin")
        let callID = callRinging.callID
        if activeCallID == callID {
            reportCallConnecting(id: callID)
            activeCall?.didReceiveCallRinging()
        }
    }

    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIceCandidate iceCandidate: Server_IceCandidate) {
        DDLogInfo("CallManager/HalloCallDelegate/didReceiveIceCandidate/\(iceCandidate.sdp)-\(iceCandidate.sdpMediaLineIndex)-\(iceCandidate.sdpMediaID)/begin")
        let callID = iceCandidate.callID
        if activeCallID == callID {
            activeCall?.didReceiveRemoteIceInfo(sdpInfo: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMediaLineIndex, sdpMid: iceCandidate.sdpMediaID)
            DDLogInfo("CallManager/HalloCallDelegate/didReceiveIceCandidate/success")
        }
    }

    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveEndCall endCall: Server_EndCall) {
        DDLogInfo("CallManager/HalloCallDelegate/didReceiveEndCall/begin")
        let callID = endCall.callID
        if activeCallID == callID {
            reportCallEnded(id: callID)
            activeCall?.didReceiveEndCall()
            activeCall = nil
            DDLogInfo("CallManager/HalloCallDelegate/didReceiveEndCall/success")
        }
    }

}


extension CallManager: CallStateDelegate {

    func stateChanged(oldState: CallState, newState: CallState) {
        DDLogInfo("CallManager/stateChanged/oldState: \(oldState)/newState: \(newState)")
        switch newState {
        case .inactive:
            stopCallRingtone()
            // If call is no longer active - notify UI about call ending.
            callViewDelegate?.callEnded()
            // Cancel timer if call ended.
            cancelTimer?.cancel()
            cancelTimer = nil

        case .connecting:
            // If call just started - notify UI and start timer.
            callViewDelegate?.callStarted()
            startCancelTimer()

        case .ringing:
            // Update UI to show ringing status.
            callViewDelegate?.callRinging()

        case .active:
            stopCallRingtone()
            callViewDelegate?.callActive()
            // Cancel timer if call is active.
            cancelTimer?.cancel()
            cancelTimer = nil
            startCallDurationTimer()

        case .held:
            break

        case .disconnected:
            stopCallRingtone()
            if let callID = activeCallID {
                reportCallEnded(id: callID)
            }
            endActiveCall(reason: .connectionError)
        }
    }
}