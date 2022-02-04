//
//  Call.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core
import CocoaLumberjackSwift
import WebRTC
import CallKit
import Reachability


public let importantStatKeys: Set = ["packetsReceived", "bytesReceived",
                                  "packetsLost", "packetsDiscarded",
                                  "packetsSent", "bytesSent",
                                  "headerBytesSent", "headerBytesReceived",
                                  "retransmittedBytesSent", "retransmittedPacketsSent",
                                  "insertedSamplesForDeceleration", "jitter",
                                  "jitterBufferDelay", "jitterBufferEmittedCount"]

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

class Call {

    // MARK: Metadata Properties
    let callID: CallID
    let isOutgoing: Bool
    let peerUserID: UserID
    var isAnswered: Bool = false
    var isConnected: Bool = false
    var isCallEndedLocally: Bool = false
    var iceIdx: Int32 = 0
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
                    MainAppContext.shared.mainDataStore.updateCall(with: callID) { call in
                        call.answered = true
                    }
                } else if state == .inactive {
                    callFailTImer?.cancel()
                    callFailTImer = nil
                    iceRestartTimer?.cancel()
                    iceRestartTimer = nil
                } else if state == .active {
                    // once active - we should never ring irrespective of call state.
                    canPlayRingtone = false
                }
            }
        }
    }
    private var callQueue = DispatchQueue(label: "com.halloapp.call", qos: .userInitiated)
    private var pendingLocalIceCandidates: [IceCandidateInfo] = []
    private var pendingRemoteIceCandidates: [IceCandidateInfo] = []
    private var pendingEndCallAction: DispatchWorkItem? = nil

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

    var isReadyToSendLocalIceCandidates: Bool {
        if isOutgoing {
            // state will be changed to 'connecting' after we send a 'startCall' packet successfully.
            // state will be changed to 'iceRestartConnecting' after we send an 'iceOffer' packet successfully.
            // send iceCandidates even after state is connected or active.
            return state == .connecting || state == .iceRestartConnecting || state == .connected || state == .active
        } else {
            // state will be changed to 'connected' after we send an 'answerCall' packet successfully.
            // state will be changed to 'connected' after we send an 'iceAnswer' packet successfully.
            // send iceCandidates even after state is active.
            return state == .connected || state == .active
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

    // MARK: Initialization
    init(id: CallID, peerUserID: UserID, direction: CallDirection = .incoming) {
        DDLogInfo("Call/init/id: \(id)/peerUserID: \(peerUserID)/direction: \(direction)")
        self.callID = id
        self.peerUserID = peerUserID
        self.isOutgoing = direction == .outgoing
        MainAppContext.shared.mainDataStore.saveCall(callID: callID, peerUserID: peerUserID, type: .audio, direction: direction)
        canPlayRingtone = true
    }

    func initializeWebRtcClient(iceServers: [RTCIceServer]) {
        DDLogInfo("Call/initializeWebRtcClient/id: \(callID)/iceServers: \(iceServers)")
        self.webRTCClient = WebRTCClient(iceServers: iceServers)
        webRTCClient?.delegate = self
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

    private func saveCallStatusAndSendReport(durationMs: Double, reason: EndCallReason) {
        // Save call status to CoreData
        MainAppContext.shared.mainDataStore.updateCall(with: callID) { call in
            call.durationMs = durationMs
            call.endReason = reason
        }
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
                                                                       type: "audio",
                                                                       direction: direction,
                                                                       networkType: networkType,
                                                                       answered: isAnswered,
                                                                       connected: isConnected,
                                                                       duration_ms: Int(durationMs),
                                                                       endCallReason: reasonStr,
                                                                       localEndCall: isCallEndedLocally,
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
        saveCallStatusAndSendReport(durationMs: durationMs, reason: reason)
        webRTCClient?.end()
        state = .inactive
        DDLogInfo("Call/\(callID)/end/success")
    }

    // MARK: Local User Actions

    func start(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/start/begin")
        callQueue.async { [self] in
            webRTCClient?.offer { sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .inactive
                    DDLogError("Call/\(callID)/start/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.startCall(id: callID, to: peerUserID, callType: .audio, payload: payload) { result in
                    switch result {
                    case .success(_):
                        state = .connecting
                        DDLogInfo("Call/\(callID)/start/success")
                        processPendingLocalIceCandidates()
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
            webRTCClient?.offer { sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .iceRestart
                    DDLogError("Call/\(callID)/iceRestartOffer/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.iceRestartOfferCall(id: callID, to: peerUserID, payload: payload, iceIdx: iceIdx) { result in
                    switch result {
                    case .success:
                        if rtcIceState == .connected {
                            state = .active
                        } else {
                            state = .iceRestartConnecting
                        }
                        DDLogInfo("Call/\(callID)/iceRestartOffer/success")
                        processPendingLocalIceCandidates()
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
            webRTCClient?.answer { sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .inactive
                    DDLogError("Call/\(callID)/answer/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.answerCall(id: callID, to: peerUserID, payload: payload) { result in
                    switch result {
                    case .success:
                        state = .connected
                        DDLogInfo("Call/\(callID)/answer/success")
                        processPendingLocalIceCandidates()
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
            }
        }
    }

    func iceRestartAnswer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/iceRestartAnswer/begin")
        callQueue.async { [self] in
            iceIdx += 1
            webRTCClient?.answer { sdpInfo in
                guard let payload = sdpInfo.sdp.data(using: .utf8) else {
                    state = .iceRestart
                    DDLogError("Call/\(callID)/iceRestartAnswer/failed")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                service.iceRestartAnswerCall(id: callID, to: peerUserID, payload: payload, iceIdx: iceIdx) { result in
                    switch result {
                    case .success:
                        if rtcIceState == .connected {
                            state = .active
                        } else {
                            state = .connected
                        }
                        DDLogInfo("Call/\(callID)/iceRestartAnswer/success")
                        processPendingLocalIceCandidates()
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

    func end(reason: EndCallReason) {
        DDLogInfo("Call/\(callID)/end/reason: \(reason)/begin")
        let durationMs = MainAppContext.shared.callManager.callDurationMs
        callQueue.async { [self] in
            pendingEndCallAction = DispatchWorkItem {
                endCall(durationMs: durationMs, reason: reason)
            }
            if isReadyToEndCall {
                pendingEndCallAction?.perform()
                pendingEndCallAction = nil
            } else {
                // We are in an inactive state.
                // So we'll check and process pendingEndCallAction on connecting.
                // Otherwise run in 5 seconds to end the call anyways.
                callQueue.asyncAfter(deadline: .now() + 5) {
                    pendingEndCallAction?.perform()
                    pendingEndCallAction = nil
                }
            }
        }
    }

    func hold(_ hold: Bool, completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/hold/hold: \(hold)/begin")
        callQueue.async { [self] in
            service.holdCall(id: callID, to: peerUserID, hold: hold) { result in
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
            DDLogInfo("Call/\(callID)/muteAudio/success")
        }
    }

    func unmuteAudio() {
        DDLogInfo("Call/\(callID)/unmuteAudio/begin")
        callQueue.async { [self] in
            webRTCClient?.unmuteAudio()
            DDLogInfo("Call/\(callID)/unmuteAudio/success")
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


    // MARK: Remote User actions.

    func didReceiveIncomingCall(sdpInfo: String, stunServers: [Server_StunServer], turnServers: [Server_TurnServer],
                                completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/didReceiveIncomingCall/begin")
        callQueue.async { [self] in
            state = .connecting
            service.sendCallRinging(id: callID, to: peerUserID)
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)/didReceiveIncomingCall/error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIncomingCall/success")
                    state = .ringing
                    processPendingRemoteIceCandidateInfo()
                    DispatchQueue.main.async {
                        completion(true)
                    }
                }
            }
        }
    }

    func didReceiveIceOffer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveIceOffer/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveIceOffer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIceOffer/success")
                    if rtcIceState == .connected {
                        state = .active
                    } else {
                        state = .iceRestartConnecting
                    }
                    processPendingRemoteIceCandidateInfo()
                    iceRestartAnswer() { _ in }
                }
            }
        }
    }

    func didReceiveAnswer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveAnswer/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveAnswer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveAnswer/success")
                    state = .connected
                    processPendingRemoteIceCandidateInfo()
                }
            }
        }
    }

    func didReceiveIceAnswer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveIceAnswer/begin")
        callQueue.async { [self] in
            webRTCClient?.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveIceAnswer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIceAnswer/success")
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

    func didReceiveRemoteIceInfo(sdpInfo: String, sdpMLineIndex: Int32, sdpMid: String) {
        let iceCandidateInfo = IceCandidateInfo(sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sdpInfo: sdpInfo)
        DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/\(sdpInfo)-\(sdpMLineIndex)-\(sdpMid)/begin")
        callQueue.async { [self] in
            // We need to hold remote ice candidates until we ready to process them.
            if !isReadyToProcessRemoteIceCandidates {
                DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/queue this to pendingRemoteIceCandidates")
                pendingRemoteIceCandidates.append(iceCandidateInfo)
            } else {
                webRTCClient?.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { error in
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
            saveCallStatusAndSendReport(durationMs: durationMs, reason: reason)
            webRTCClient?.end()
            state = .inactive
            DDLogInfo("Call/\(callID)/didReceiveEndCall/success")
        }
    }

    func didReceiveCallRinging() {
        DDLogInfo("Call/\(callID)/didReceiveCallRinging/begin")
        callQueue.async { [self] in
            if state == .connecting {
                state = .ringing
            }
            DDLogInfo("Call/\(callID)/didReceiveCallRinging/success")
        }
    }

    func didReceiveCallHold(_ hold: Bool) {
        DDLogInfo("Call/\(callID)/didReceiveCallHold/begin/hold: \(hold)")
        callQueue.async { [self] in
            DDLogInfo("Call/\(callID)/didReceiveCallHold/success")
            isOnHold = hold
        }
    }

    func logPeerConnectionStats() {
        callQueue.async { [self] in
            webRTCClient?.fetchPeerConnectionStats() { report in
                report.statistics.forEach { (key, stats) in
                    if stats.type == "inbound-rtp" || stats.type == "outbound-rtp" {
                        var statString = stats.type + "/"
                        let values = stats.values.filter { (statKey, statValue) in
                            return importantStatKeys.contains(statKey)
                        }
                        statString += values.description
                        DDLogInfo("Call/\(callID)/logPeerConnectionStats/report: \(statString)")
                    }
                }
            }
        }
    }


    // MARK: Internal functions

    private func processPendingLocalIceCandidates() {
        DDLogInfo("Call/\(callID)/processPendingLocalIceCandidates/count: \(pendingLocalIceCandidates.count)")
        callQueue.async { [self] in
            pendingLocalIceCandidates.forEach { candidate in
                service.sendIceCandidate(id: callID, to: peerUserID, iceCandidateInfo: candidate)
            }
            pendingLocalIceCandidates.removeAll()
            DDLogInfo("Call/\(callID)/processPendingLocalIceCandidates/success")
        }
    }

    func processPendingRemoteIceCandidateInfo() {
        DDLogInfo("Call/\(callID)/processPendingRemoteIceCandidateInfo/count: \(pendingRemoteIceCandidates.count)")
        callQueue.async { [self] in
            pendingRemoteIceCandidates.forEach { iceCandidateInfo in
                webRTCClient?.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { error in
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
                // We need to hold ice candidates until we send a startCall or answerCall packet successfully.
                if !isReadyToSendLocalIceCandidates {
                    pendingLocalIceCandidates.append(iceCandidateInfo)
                    DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didDiscoverLocalCandidate/queue this to pendingLocalIceCandidates")
                } else {
                    service.sendIceCandidate(id: callID, to: peerUserID, iceCandidateInfo: iceCandidateInfo)
                }
            }
        }
    }

    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState iceState: RTCIceConnectionState) {
        DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didChangeConnectionState/begin - \(iceState.description)")
        callQueue.async { [self] in
            rtcIceState = iceState
            switch iceState {
            case .disconnected:
                // check state and restart ice in 3 seconds.
                checkAndStartIceRestartTimer(deadline: .now() + DispatchTimeInterval.seconds(3))
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
                state = .active
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

}
