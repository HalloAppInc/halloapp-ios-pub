//
//  Call.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CoreCommon
import CocoaLumberjackSwift
import WebRTC
import CallKit
import Reachability
import Combine


public let importantStatKeys: Set = [
    "packetsReceived", "bytesReceived",
    "packetsLost", "packetsDiscarded",
    "packetsSent", "bytesSent",
    "headerBytesSent", "headerBytesReceived",
    "retransmittedBytesSent", "retransmittedPacketsSent",
    "insertedSamplesForDeceleration", "jitter",
    "jitterBufferDelay", "jitterBufferEmittedCount",
    "framesReceived", "framesPerSecond",
    "framesDecoded", "keyFramesDecoded",
    "framesDropped", "partialFramesLost", "fullFramesLost"]

public let importantStatNoDiffKeys: Set = ["framesPerSecond"]

public let unwantedStatTypes: Set = ["codec", "certificate", "media-source", "candidate-pair", "local-candidate", "remote-candidate"]


public struct IceCandidateInfo {
    var sdpMid: String
    var sdpMLineIndex: Int32
    var sdpInfo: String
}

extension IceCandidateInfo {
    var rtcIceCandidate: RTCIceCandidate {
        return RTCIceCandidate(sdp: sdpInfo, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

protocol CallStateDelegate: AnyObject {
    func stateChanged(oldState: CallState, newState: CallState)
}

public class Call {

    // MARK: Metadata Properties
    let callID: CallID
    let isOutgoing: Bool
    let peerUserID: UserID
    let type: CallType
    public var callCapabilities: Server_CallCapabilities = Server_CallCapabilities()
    var isAnswered: Bool = false
    var isConnected: Bool = false
    var isCallEndedLocally: Bool = false
    var iceIdx: Int32 = 0
    var iceAnsweredDate: Date? = nil
    var iceConnectedDate: Date? = nil
    var iceTimeTakenMs: Int {
        get {
            if let answeredDate = iceAnsweredDate,
               let connectedDate = iceConnectedDate {
                return Int(connectedDate.timeIntervalSince(answeredDate) * 1000)
            } else {
                return 0
            }
        }
    }
    private var rtcIceState: RTCIceConnectionState = .new
    private var iceRestartTimer: DispatchSourceTimer?
    private var callFailTImer: DispatchSourceTimer?
    private var webRTCClient: WebRTCClient?
    let service: HalloService = MainAppContext.shared.callManager.service
    private(set) var state: CallState = .inactive {
        didSet {
            callQueue.async { [self] in
                stateDelegate?.stateChanged(oldState: oldValue, newState: state)
                // state is set to connected only when client answers or received an answer for the call.
                if state == .connected {
                    isAnswered = true
                    iceAnsweredDate = Date()
                } else if state == .inactive {
                    callFailTImer?.cancel()
                    callFailTImer = nil
                    iceRestartTimer?.cancel()
                    iceRestartTimer = nil
                } else if state == .active {
                    // once active - we should never ring irrespective of call state.
                    isAnswered = true
                    canPlayRingtone = false
                    iceConnectedDate = Date()
                }
            }
        }
    }
    private var callQueue = DispatchQueue(label: "com.halloapp.call", qos: .userInitiated)
    private var pendingRemoteIceCandidates: [IceCandidateInfo] = []
    private var pendingEndCallAction: DispatchWorkItem? = nil
    private var lastReport: [String: RTCStatistics]? = nil
    public let hasStartedReceivingRemoteVideo = CurrentValueSubject<Bool, Never>(false)
    public let mirrorVideo = PassthroughSubject<Bool, Never>()
    public var isWaitingForWebRtcOffer: Bool
    public var answerCompletion: ((_ success: Bool) -> Void)? = nil

    public var isLocalAudioMuted = CurrentValueSubject<Bool, Never>(false)
    public var isLocalVideoMuted = CurrentValueSubject<Bool, Never>(false)
    public var isRemoteAudioMuted = CurrentValueSubject<Bool, Never>(false)
    public var isRemoteVideoMuted = CurrentValueSubject<Bool, Never>(false)

    var canPreAnswer: Bool {
        return callCapabilities.preAnswer && ServerProperties.preAnswerCalls
    }

    var stateDelegate: CallStateDelegate? = nil

    // MARK: Derived Properties
    var hasStartedConnecting: Bool {
        return state == .connecting
    }
    var isRinging: Bool {
        return state == .ringing
    }
    var hasEnded: Bool {
        return state == .inactive
    }
    var isActive: Bool {
        return state == .active
    }
    var isMissedCall: Bool {
        return !isOutgoing && !isAnswered
    }
    var isVideoCall: Bool {
        return type == .video
    }

    var isOnHold: Bool = false
    // keep track on whether we can play ringtone or not - irrespective of the state of the call.
    var canPlayRingtone: Bool = false

    var isReadyToProcessRemoteIceCandidates: Bool {
        if isOutgoing {
            // state will be changed to 'connected' after we received an 'answerCall' packet successfully.
            // state will be changed to 'connected' after we received an 'iceAnswer' packet successfully.
            // process iceCandidates even after state is active.
            return state == .connected || state == .active
        } else {
            // state will be changed to 'ringing' after we received an 'startCall' packet successfully.
            // state will be changed to 'iceRestartConnecting' after we received an 'iceOffer' packet successfully.
            // process iceCandidates even after state is active.
            return state == .ringing || state == .iceRestartConnecting || state == .active
        }
    }

    var isReadyToEndCall: Bool {
        if isOutgoing {
            // There could be a race condition where state is still inactive and the client is trying to end the call.
            return state != .inactive
        } else {
            return true
        }
    }
    private var iceRestartDelayMs: Int {
        if let callConfig = webRTCClient?.callConfig {
            return Int(callConfig.iceRestartDelayMs)
        } else {
            return 3000
        }

    }

    private var localVideoRenderer: RTCVideoRenderer?
    private var remoteVideoRenderer: RTCVideoRenderer?
    private var cancellableSet: Set<AnyCancellable> = []

    // MARK: Initialization
    init(id: CallID, peerUserID: UserID, type: CallType, direction: CallDirection = .incoming) {
        DDLogInfo("Call/init/id: \(id)/peerUserID: \(peerUserID)/direction: \(direction)")
        self.callID = id
        self.peerUserID = peerUserID
        self.type = type
        self.isOutgoing = direction == .outgoing
        self.isWaitingForWebRtcOffer = direction == .incoming
        self.answerCompletion = nil
        self.webRTCClient = WebRTCClient(callType: type)
        webRTCClient?.delegate = self
        canPlayRingtone = true

        self.cancellableSet.insert(
            // Notification to stop capture if app goes to background.
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.muteVideo()
            }
        )

        self.cancellableSet.insert(
            // Notification to start capture if app goes to foreground.
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.unmuteVideo()
            })
    }

    func initializeCallCapabilities(callCapabilities: Server_CallCapabilities) {
        callQueue.async { [self] in
            DDLogInfo("Call/initializeCallCapabilities/id: \(callID)/callCapabilities: \(callCapabilities)")
            self.callCapabilities = callCapabilities
        }
    }

    func initializeWebRtcClient(iceServers: [RTCIceServer], config: Server_CallConfig) {
        let addTracks = isOutgoing || !canPreAnswer
        callQueue.async { [self] in
            DDLogInfo("Call/initializeWebRtcClient/id: \(callID)/iceServers: \(iceServers)/call_config: \(config)/addTracks: \(addTracks)")
            self.webRTCClient?.initialize(iceServers: iceServers, config: config, addTracks: addTracks)
        }
    }

    public func renderLocalVideo(to localRenderer: RTCVideoRenderer) {
        callQueue.async { [self] in
            self.localVideoRenderer = localRenderer
            webRTCClient?.renderLocalVideo(to: localRenderer)
        }
    }

    public func renderRemoteVideo(to remoteRenderer: RTCVideoRenderer) {
        callQueue.async { [self] in
            self.remoteVideoRenderer = remoteRenderer
            webRTCClient?.renderRemoteVideo(to: remoteRenderer)
        }
    }

    private func checkAndStartIceRestartTimer(deadline: DispatchTime) {
        DDLogInfo("Call/startIceRestartTimer/begin")
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            DDLogInfo("Call/startIceRestartTimer/restartIce now")
            if self.rtcIceState != .connected {
                self.state = .iceRestart
                if self.isOutgoing {
                    self.iceRestartOffer() { _ in }
                }
            }
        })
        timer.schedule(deadline: deadline)
        timer.resume()
        iceRestartTimer = timer
    }

    private func checkAndStartCallFailedTimer(deadline: DispatchTime) {
        DDLogInfo("Call/checkAndStartCallFailedTimer/begin")
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            DDLogInfo("Call/checkAndStartCallFailedTimer/failed call now/rtcIceState: \(self.rtcIceState)")
            if self.rtcIceState != .connected {
                self.state = .disconnected
            }
        })
        timer.schedule(deadline: deadline)
        timer.resume()
        callFailTImer = timer
    }

    private func sendCallReport(durationMs: Double, reason: EndCallReason) {
        // Send call report to the server.
        let direction = isOutgoing ? "outgoing" : "incoming"
        let networkType = MainAppContext.shared.service.reachabilityConnectionType.lowercased()
        DDLogInfo("Call/\(callID)/end/networkType: \(networkType)/checking")
        webRTCClient?.fetchPeerConnectionStats() { [self] report in
            let filteredReport = report.statistics.filter { (key, stats) in
                return !unwantedStatTypes.contains(stats.type)
            }
            let modifiedReport = filteredReport.mapValues { stats -> [String: Any] in
                return ["id": stats.id,
                         "timestamp_us": stats.timestamp_us,
                         "type": stats.type,
                         "values": stats.values
                        ]
            }
            do {
                let reasonStr = reason.serverEndCallReasonStr
                let webrtcStatsData = try JSONSerialization.data(withJSONObject: modifiedReport, options: [.prettyPrinted, .withoutEscapingSlashes])
                if let webrtcStatsString = String(data: webrtcStatsData, encoding: .utf8) {
                    AppContext.shared.observeAndSave(event: .callReport(id: callID,
                                                                       peerUserID: peerUserID,
                                                                       type: type.rawValue,
                                                                       direction: direction,
                                                                       networkType: networkType,
                                                                       answered: isAnswered,
                                                                       connected: isConnected,
                                                                       duration_ms: Int(durationMs),
                                                                       endCallReason: reasonStr,
                                                                       localEndCall: isCallEndedLocally,
                                                                       iceTimeTakenMs: iceTimeTakenMs,
                                                                       webrtcStats: webrtcStatsString))
                } else {
                    DDLogError("Call/\(callID)/end/failed getting callReport data")
                }
            } catch {
                DDLogError("Call/\(callID)/end/failed getting callReport data")
            }
        }
    }

    private func endCall(durationMs: Double, reason: EndCallReason) {
        isCallEndedLocally = true
        service.endCall(id: callID, to: peerUserID, reason: reason)
        sendCallReport(durationMs: durationMs, reason: reason)
        webRTCClient?.end()
        state = .inactive
        DDLogInfo("Call/\(callID)/end/success")
    }

    // MARK: Local User Actions

    func start(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/start/begin")
        callQueue.async { [self] in
            webRTCClient?.offer { [self] sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .inactive
                    DDLogError("Call/\(callID)/start/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.startCall(id: callID, to: peerUserID, callType: type, payload: payload, callCapabilities: callCapabilities) { [self] result in
                    switch result {
                    case .success(_):
                        state = .connecting
                        DDLogInfo("Call/\(callID)/start/success")
                        DispatchQueue.main.async {
                            completion(true)
                        }
                        // Check pendingEndCallAction and perform.
                        pendingEndCallAction?.perform()
                        pendingEndCallAction = nil
                    case .failure(let error):
                        state = .inactive
                        DDLogError("Call/\(callID)/start/failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                    }
                }
            }
        }
    }

    func iceRestartOffer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/iceRestartOffer/begin")
        callQueue.async { [self] in
            iceIdx += 1
            webRTCClient?.restartIce()
            webRTCClient?.offer { [self] sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .iceRestart
                    DDLogError("Call/\(callID)/iceRestartOffer/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.iceRestartOfferCall(id: callID, to: peerUserID, payload: payload, iceIdx: iceIdx) { [self] result in
                    switch result {
                    case .success:
                        if rtcIceState == .connected {
                            state = isAnswered ? .active : .ringing
                        } else {
                            state = .iceRestartConnecting
                        }
                        DDLogInfo("Call/\(callID)/iceRestartOffer/success")
                        DispatchQueue.main.async {
                            completion(true)
                        }
                    case .failure(let error):
                        state = .iceRestart
                        DDLogError("Call/\(callID)/iceRestartOffer/failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                    }
                }
            }
        }
    }

    func answer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/answer/begin")
        callQueue.async { [self] in
            guard !isWaitingForWebRtcOffer else {
                DDLogInfo("Call/\(callID)/answer/isWaitingForWebRtcOffer: \(isWaitingForWebRtcOffer)/still waiting for offer.")
                answerCompletion = completion
                return
            }
            // completion after sending out the answer.
            let newCompletion: ((Result<Void, RequestError>) -> Void) = { [self] result in
                switch result {
                case .success:
                    if rtcIceState == .connected {
                        state = .active
                    } else {
                        state = .connected
                    }
                    DDLogInfo("Call/\(callID)/answer/success")
                    DispatchQueue.main.async {
                        completion(true)
                    }
                case .failure(let error):
                    state = .inactive
                    DDLogError("Call/\(callID)/answer/failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
            if canPreAnswer {
                webRTCClient?.addTracks()
                webRTCClient?.offer { [self] sdpInfo in
                    guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                        state = .inactive
                        DDLogError("Call/\(callID)/answer/failed")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                        return
                    }
                    service.answerCall(id: callID, to: peerUserID, offerPayload: payload, completion: newCompletion)
                }
            } else {
                // Without pre-answer - so send answer here.
                webRTCClient?.answer { [self] sdpInfo in
                    guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                        state = .inactive
                        DDLogError("Call/\(callID)/answer/failed")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                        return
                    }
                    service.answerCall(id: callID, to: peerUserID, answerPayload: payload, completion: newCompletion)
                }
            }
        }
    }

    func iceRestartAnswer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/iceRestartAnswer/begin")
        callQueue.async { [self] in
            iceIdx += 1
            webRTCClient?.answer { [self] sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .iceRestart
                    DDLogError("Call/\(callID)/iceRestartAnswer/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.iceRestartAnswerCall(id: callID, to: peerUserID, payload: payload, iceIdx: iceIdx) { [self] result in
                    switch result {
                    case .success:
                        if rtcIceState == .connected {
                            state = isAnswered ? .active : .ringing
                        } else {
                            state = .connected
                        }
                        DDLogInfo("Call/\(callID)/iceRestartAnswer/success")
                        DispatchQueue.main.async {
                            completion(true)
                        }
                    case .failure(let error):
                        state = .iceRestart
                        DDLogError("Call/\(callID)/iceRestartAnswer/failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            completion(false)
                        }
                    }
                }
            }
        }
    }

    // should be called on callQueue.
    private func preAnswer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/preAnswer/begin")
        webRTCClient?.answer { [self] sdpInfo in
            guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                DDLogError("Call/\(callID)/iceRestartAnswer/failed")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            service.sendCallRinging(id: callID, to: peerUserID, payload: payload) { [self] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/preAnswer/success")
                    DispatchQueue.main.async {
                        completion(true)
                    }
                case .failure(let error):
                    DDLogError("Call/\(callID)/preAnswer/failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }

    // should be called on callQueue.
    private func postAnswer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/postAnswer/begin")
        webRTCClient?.offer { [self] sdpInfo in
            guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                DDLogError("Call/\(callID)/postAnswer/failed")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            service.sendCallSdp(id: callID, to: peerUserID, payload: payload) { [self] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/postAnswer/success")
                    DispatchQueue.main.async {
                        completion(true)
                    }
                case .failure(let error):
                    DDLogError("Call/\(callID)/postAnswer/failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }

    func end(reason: EndCallReason) {
        DDLogInfo("Call/\(callID)/end/reason: \(reason)/begin")
        let durationMs = MainAppContext.shared.callManager.callDurationMs
        callQueue.async { [self] in
            pendingEndCallAction = DispatchWorkItem { [self] in
                endCall(durationMs: durationMs, reason: reason)
            }
            if isReadyToEndCall {
                pendingEndCallAction?.perform()
                pendingEndCallAction = nil
            } else {
                // We are in an inactive state.
                // So we'll check and process pendingEndCallAction on connecting.
                // Otherwise run in 5 seconds to end the call anyways.
                callQueue.asyncAfter(deadline: .now() + 5) { [self] in
                    pendingEndCallAction?.perform()
                    pendingEndCallAction = nil
                }
            }
        }
    }

    func hold(_ hold: Bool, completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/hold/hold: \(hold)/begin")
        callQueue.async { [self] in
            service.holdCall(id: callID, to: peerUserID, hold: hold) { [self] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/hold/success")
                    isOnHold = hold
                    DispatchQueue.main.async {
                        completion(true)
                    }
                case .failure(let error):
                    DDLogError("Call/\(callID)/hold/failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }

    func muteAudio() {
        DDLogInfo("Call/\(callID)/muteAudio/begin")
        callQueue.async { [self] in
            webRTCClient?.muteAudio()
            service.muteCall(id: callID, to: peerUserID, muted: true, mediaType: .audio) { [callID] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/muteAudio/success")
                case .failure(let error):
                    DDLogError("Call/\(callID)/muteAudio/failed: \(error.localizedDescription)")
                }
            }
            isLocalAudioMuted.send(true)
        }
    }

    func unmuteAudio() {
        DDLogInfo("Call/\(callID)/unmuteAudio/begin")
        callQueue.async { [self] in
            webRTCClient?.unmuteAudio()
            service.muteCall(id: callID, to: peerUserID, muted: false, mediaType: .audio) { [callID] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/unmuteAudio/success")
                case .failure(let error):
                    DDLogError("Call/\(callID)/unmuteAudio/failed: \(error.localizedDescription)")
                }
            }
            isLocalAudioMuted.send(false)
        }
    }

    func muteVideo() {
        DDLogInfo("Call/\(callID)/muteVideo/begin")
        callQueue.async { [self] in
            webRTCClient?.muteVideo()
            service.muteCall(id: callID, to: peerUserID, muted: true, mediaType: .video) { [callID] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/muteVideo/success")
                case .failure(let error):
                    DDLogError("Call/\(callID)/muteVideo/failed: \(error.localizedDescription)")
                }
            }
            isLocalVideoMuted.send(true)
        }
    }

    func unmuteVideo() {
        DDLogInfo("Call/\(callID)/unmuteVideo/begin")
        callQueue.async { [self] in
            webRTCClient?.unmuteVideo()
            service.muteCall(id: callID, to: peerUserID, muted: false, mediaType: .video) { [callID] result in
                switch result {
                case .success:
                    DDLogInfo("Call/\(callID)/unmuteVideo/success")
                case .failure(let error):
                    DDLogError("Call/\(callID)/unmuteVideo/failed: \(error.localizedDescription)")
                }
            }
            isLocalVideoMuted.send(false)
        }
    }

    func switchCamera() {
        DDLogInfo("Call/\(callID)/switchCamera/begin")
        callQueue.async { [self] in
            webRTCClient?.switchCamera()
            DDLogInfo("Call/\(callID)/switchCamera/success")
        }
    }

    func speakerOn() {
        DDLogInfo("Call/\(callID)/speakerOn/begin")
        callQueue.async { [self] in
            webRTCClient?.speakerOn()
            DDLogInfo("Call/\(callID)/speakerOn/success")
        }
    }

    func speakerOff() {
        DDLogInfo("Call/\(callID)/speakerOff/begin")
        callQueue.async { [self] in
            webRTCClient?.speakerOff()
            DDLogInfo("Call/\(callID)/speakerOff/success")
        }
    }

    func bluetoothOn() {
        DDLogInfo("Call/\(callID)/bluetoothOn/begin")
        callQueue.async { [self] in
            webRTCClient?.bluetoothOn()
            DDLogInfo("Call/\(callID)/bluetoothOn/success")
        }
    }

    func bluetoothOff() {
        DDLogInfo("Call/\(callID)/bluetoothOff/begin")
        callQueue.async { [self] in
            webRTCClient?.bluetoothOff()
            DDLogInfo("Call/\(callID)/bluetoothOff/success")
        }
    }

    func setPreferredInput(input: AVAudioSessionPortDescription?) {
        DDLogInfo("Call/\(callID)/setPreferredInput/begin")
        callQueue.async { [self] in
            webRTCClient?.setPreferredInput(input: input)
            DDLogInfo("Call/\(callID)/setPreferredInput/success")
        }
    }


    // MARK: Remote User actions.

    func didReceiveIncomingCall(sdpInfo: String, stunServers: [Server_StunServer], turnServers: [Server_TurnServer],
                                completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/didReceiveIncomingCall/begin")
        callQueue.async { [self] in
            guard isWaitingForWebRtcOffer else {
                DDLogInfo("Call/\(callID)/didReceiveIncomingCall/processed webrtc offer already - skip")
                // No need to call completion as well - since we processed offer already.
                return
            }
            state = .connecting
            if !canPreAnswer {
                service.sendCallRinging(id: callID, to: peerUserID)
            }
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: sdpInfo)) { [self] error in
                if let error = error {
                    DDLogError("Call/\(callID)/didReceiveIncomingCall/error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIncomingCall/success")
                    state = .ringing
                    if canPreAnswer {
                        preAnswer() { _ in }
                    }
                    processPendingRemoteIceCandidateInfo()
                    DispatchQueue.main.async {
                        completion(true)
                    }
                }
                isWaitingForWebRtcOffer = false
                if let completion = answerCompletion {
                    answer(completion: completion)
                    answerCompletion = nil
                }
            }
        }
    }

    func didReceiveIceOffer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveIceOffer/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: sdpInfo)) { [self] error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveIceOffer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIceOffer/success")
                    if rtcIceState == .connected {
                        state = isAnswered ? .active : .ringing
                    } else {
                        state = .iceRestartConnecting
                    }
                    processPendingRemoteIceCandidateInfo()
                    iceRestartAnswer() { _ in }
                }
            }
        }
    }

    // We can reuse this functions to set answer sdpInfo in webrtc.
    func didReceiveAnswer(answerSdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveAnswer/answerSdpInfo/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: answerSdpInfo)) { [self] error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveAnswer/answerSdpInfo/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveAnswer/answerSdpInfo/success")
                    if rtcIceState == .connected {
                        state = .active
                    } else {
                        state = .connected
                    }
                    processPendingRemoteIceCandidateInfo()
                }
            }
        }
    }

    // We can reuse this functions to set offer sdpInfo in webrtc.
    func didReceiveAnswer(offerSdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveAnswer/offerSdpInfo/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: offerSdpInfo)) { [self] error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveAnswer/offerSdpInfo/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveAnswer/offerSdpInfo/success")
                    if rtcIceState == .connected {
                        state = .active
                    } else {
                        state = .connected
                    }
                    postAnswer() { _ in }
                    processPendingRemoteIceCandidateInfo()
                }
            }
        }
    }

    func didReceiveIceAnswer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveIceAnswer/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: sdpInfo)) { [self] error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveIceAnswer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIceAnswer/success")
                    if rtcIceState == .connected {
                        state = isAnswered ? .active : .ringing
                    } else {
                        state = .connected
                    }
                    processPendingRemoteIceCandidateInfo()
                }
            }
        }
    }

    func didReceiveRemoteIceInfo(sdpInfo: String, sdpMLineIndex: Int32, sdpMid: String) {
        let iceCandidateInfo = IceCandidateInfo(sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sdpInfo: sdpInfo)
        DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/\(sdpInfo)-\(sdpMLineIndex)-\(sdpMid)/begin")
        callQueue.async { [self] in
            // We need to hold remote ice candidates until we ready to process them.
            if !isReadyToProcessRemoteIceCandidates {
                DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/queue this to pendingRemoteIceCandidates")
                pendingRemoteIceCandidates.append(iceCandidateInfo)
            } else {
                webRTCClient?.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { [self] error in
                    if let error = error {
                        DDLogError("Call/\(callID)/didReceiveRemoteIceInfo/error: \(String(describing: error))")
                        pendingRemoteIceCandidates.append(iceCandidateInfo)
                    } else {
                        DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/success")
                    }
                }
            }
        }
    }

    func didReceiveEndCall(reason: EndCallReason) {
        DDLogInfo("Call/\(callID)/didReceiveEndCall/begin")
        let durationMs = MainAppContext.shared.callManager.callDurationMs
        callQueue.async { [self] in
            isCallEndedLocally = false
            sendCallReport(durationMs: durationMs, reason: reason)
            webRTCClient?.end()
            state = .inactive
            DDLogInfo("Call/\(callID)/didReceiveEndCall/success")
        }
    }

    func didReceiveCallRinging() {
        DDLogInfo("Call/\(callID)/didReceiveCallRinging/begin")
        callQueue.async { [self] in
            callCapabilities.preAnswer = false
            if state == .connecting {
                state = .ringing
            }
            DDLogInfo("Call/\(callID)/didReceiveCallRinging/success")
        }
    }

    func didReceiveCallRinging(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveCallRinging/sdpInfo/begin")
        callQueue.async { [self] in
            callCapabilities.preAnswer = true
            if state == .connecting {
                state = .ringing
                webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: sdpInfo)) { [self] error in
                    if let error = error {
                        DDLogError("Call/\(callID)didReceiveCallRinging/sdpInfo/error: \(error.localizedDescription)")
                    } else {
                        DDLogInfo("Call/\(callID)/didReceiveCallRinging/sdpInfo/success")
                        processPendingRemoteIceCandidateInfo()
                    }
                }
            }
            DDLogInfo("Call/\(callID)/didReceiveCallRinging/sdpInfo/success")
        }
    }

    func didReceiveCallHold(_ hold: Bool) {
        DDLogInfo("Call/\(callID)/didReceiveCallHold/begin/hold: \(hold)")
        callQueue.async { [self] in
            DDLogInfo("Call/\(callID)/didReceiveCallHold/success")
            isOnHold = hold
        }
    }

    func didReceiveCallMute(_ muted: Bool, media: CallMediaType) {
        DDLogInfo("Call/\(callID)/didReceiveCallMute/begin/muted: \(muted)/media: \(media)")
        callQueue.async { [self] in
            DDLogInfo("Call/\(callID)/didReceiveCallMute/success")
            switch media {
            case .audio:
                isRemoteAudioMuted.send(muted)
            case .video:
                isRemoteVideoMuted.send(muted)
            }
        }
    }

    func logPeerConnectionStats() {
        callQueue.async { [self] in
            DDLogInfo("Call/logPeerConnectionStats/begin")
            webRTCClient?.fetchPeerConnectionStats() { [self] report in
                var currentReport: [String: RTCStatistics] = [:]
                for (key, stats) in report.statistics {
                    if stats.type == "inbound-rtp" || stats.type == "outbound-rtp" {
                        if currentReport[key] != nil {
                            continue
                        }
                        currentReport[key] = stats
                        var statString: String
                        if key.contains("Video") && key.contains("Inbound") {
                            statString = "video-in "
                        } else if key.contains("Video") && key.contains("Outbound") {
                            statString = "video-out "
                        } else if key.contains("Audio") && key.contains("Inbound") {
                            statString = "audio-in "
                        } else if key.contains("Audio") && key.contains("Outbound") {
                            statString = "audio-out "
                        } else {
                            statString = key + ":" + stats.type + " "
                        }
                        let impStats = stats.values.filter { (statKey, statValue) in
                            return importantStatKeys.contains(statKey)
                        }

                        // Fetch oldStats
                        let oldStats = lastReport?[key]
                        let oldImpStats = oldStats?.values.filter { (statKey, statValue) in
                            return importantStatKeys.contains(statKey)
                        }

                        // Log difference in stats - easier to notice what happened in the recent few seconds.
                        // Sort keys for easy debugging.
                        for (statKey, statValue) in Array(impStats).sorted(by: {$0.key < $1.key}) {
                            if importantStatNoDiffKeys.contains(statKey) {
                                statString += "\(statKey): \(statValue) "
                            } else if let oldImpStats = oldImpStats,
                                      let oldStatValue = oldImpStats[statKey] as? Int,
                                      let newStatValue = statValue as? Int {
                                statString += "\(statKey): \(newStatValue - oldStatValue) "
                            } else if let oldImpStats = oldImpStats,
                                      let oldStatValue = oldImpStats[statKey] as? Double,
                                      let newStatValue = statValue as? Double {
                                statString += "\(statKey): \(String(format: "%.3f", newStatValue - oldStatValue)) "
                            } else {
                                statString += "\(statKey): \(statValue) "
                            }
                        }
                        DDLogInfo("Call/\(callID)/logPeerConnectionStats/report/key: \(key)/\(statString)")
                    }
                }
                // Hold latest report
                lastReport = currentReport
                DDLogInfo("Call/logPeerConnectionStats/end")
            }
        }
    }


    // MARK: Internal functions

    func processPendingRemoteIceCandidateInfo() {
        DDLogInfo("Call/\(callID)/processPendingRemoteIceCandidateInfo/count: \(pendingRemoteIceCandidates.count)")
        callQueue.async { [self] in
            pendingRemoteIceCandidates.forEach { iceCandidateInfo in
                webRTCClient?.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { [self] error in
                    if let error = error {
                        DDLogError("Call/\(callID)/processPendingRemoteIceCandidateInfo/error: \(String(describing: error))")
                    }
                }
            }
            pendingRemoteIceCandidates.removeAll()
            DDLogInfo("Call/\(callID)/processPendingRemoteIceCandidateInfo/success")
        }
    }

}

extension Call: WebRTCClientDelegate {

    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didDiscoverLocalCandidate/\(candidate.sdp)-\(candidate.sdpMLineIndex)-\(candidate.sdpMid ?? "")/begin")
        callQueue.async { [self] in
            if let sdpMid = candidate.sdpMid {
                let iceCandidateInfo = IceCandidateInfo(sdpMid: sdpMid, sdpMLineIndex: candidate.sdpMLineIndex, sdpInfo: candidate.sdp)
                service.sendIceCandidate(id: callID, to: peerUserID, iceCandidateInfo: iceCandidateInfo)
            }
        }
    }

    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState iceState: RTCIceConnectionState) {
        DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didChangeConnectionState/begin - \(iceState.description)")
        callQueue.async { [self] in
            rtcIceState = iceState
            switch iceState {
            case .disconnected:
                // check state and restart ice in around 3 seconds - use config param from server.
                checkAndStartIceRestartTimer(deadline: .now() + DispatchTimeInterval.milliseconds(iceRestartDelayMs))
                // disconnect call if we dont recover in 30 seconds.
                checkAndStartCallFailedTimer(deadline: .now() + DispatchTimeInterval.seconds(30))
            case .failed:
                // check state and restart ice now.
                checkAndStartIceRestartTimer(deadline: .now())
                // disconnect call if we dont recover in 30 seconds.
                checkAndStartCallFailedTimer(deadline: .now() + DispatchTimeInterval.seconds(30))
            case .closed:
                // disconnect call if we dont recover in 10 seconds.
                checkAndStartCallFailedTimer(deadline: .now() + DispatchTimeInterval.seconds(10))
            case .connected:
                isConnected = true
                state = isAnswered ? .active : .ringing
                iceRestartTimer?.cancel()
                iceRestartTimer = nil
                callFailTImer?.cancel()
                callFailTImer = nil
            default:
                break
            }
            DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didChangeConnectionState/success")
        }
    }

    func didStartReceivingRemoteVideo() {
        hasStartedReceivingRemoteVideo.send(true)
    }

    func switchedCamera(to cameraType: CameraType) {
        switch cameraType {
        case .back: mirrorVideo.send(false)
        case .front: mirrorVideo.send(true)
        }
    }

}
