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
import CryptoKit
import Reachability

public typealias CallID = String

public enum CallType: Int, Codable {
    case audio = 0
    case video = 1
}

extension CallType {
    var serverCallType: Server_CallType {
        switch self {
        case .audio:
            return .audio
        case .video:
            return .video
        }
    }
}

public enum CallError: Error {
    case systemError
    case alreadyInCall
    case noActiveCall
}

public let importantStatKeys: Set = ["packetsReceived", "bytesReceived",
                                  "packetsLost", "packetsDiscarded",
                                  "packetsSent", "bytesSent",
                                  "headerBytesSent", "headerBytesReceived",
                                  "retransmittedBytesSent", "retransmittedPacketsSent",
                                  "insertedSamplesForDeceleration", "jitter",
                                  "jitterBufferDelay", "jitterBufferEmittedCount"]

public let unwantedStatTypes: Set = ["codec", "certificate", "media-source", "candidate-pair", "local-candidate", "remote-candidate"]

public enum EndCallReason: Int, Codable {
    case ended = 0
    case canceled = 1
    case reject = 2
    case busy = 3
    case timeout = 4
    case systemError = 5
    case decryptionError = 6
    case encryptionError = 7
    case connectionError = 8
}

extension EndCallReason {
    var serverEndCallReason: Server_EndCall.Reason {
        switch self {
        case .ended:
            return .callEnd
        case .canceled:
            return .cancel
        case .reject:
            return .reject
        case .busy:
            return .busy
        case .timeout:
            return .timeout
        case .systemError:
            return .systemError
        case .encryptionError:
            return .encryptionFailed
        case .decryptionError:
            return .decryptionFailed
        case .connectionError:
            // TODO: update protobuf for connection error.
            return .systemError
        }
    }

    var serverEndCallReasonStr: String {
        switch self {
        case .ended:
            return "callEnd"
        case .canceled:
            return "cancel"
        case .reject:
            return "reject"
        case .busy:
            return "busy"
        case .timeout:
            return "timeout"
        case .systemError:
            return "systemError"
        case .encryptionError:
            return "encryptionFailed"
        case .decryptionError:
            return "decryptionFailed"
        case .connectionError:
            // TODO: update protobuf for connection error.
            return "systemError"
        }
    }
}

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

enum CallState {
    case inactive
    case connecting
    case ringing
    case active
    case held
    case disconnected
}

extension String {
    var callUUID: UUID {
        let hash = SHA256.hash(data: Data(self .utf8)).data
        let truncatedHash = Array(hash.prefix(16))
        let uuidString = NSUUID(uuidBytes: truncatedHash).uuidString
        return UUID(uuidString: uuidString)!
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
    private var webRTCClient: WebRTCClient
    let service: HalloService = MainAppContext.shared.callManager.service
    private(set) var state: CallState = .inactive {
        didSet {
            stateDelegate?.stateChanged(oldState: oldValue, newState: state)
            // state is set to active only when client answers or received an answer for the call.
            if state == .active {
                isAnswered = true
            }
        }
    }
    private var callQueue = DispatchQueue(label: "com.halloapp.call", qos: .userInitiated)
    private var pendingLocalIceCandidates: [IceCandidateInfo] = []
    private var pendingRemoteIceCandidates: [IceCandidateInfo] = []

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

    // MARK: Initialization
    init(id: CallID, peerUserID: UserID, iceServers: [RTCIceServer], isOutgoing: Bool = false) {
        DDLogInfo("Call/init/id: \(id)/peerUserID: \(peerUserID)/iceServers: \(iceServers)/isOutgoing: \(isOutgoing)")
        self.callID = id
        self.peerUserID = peerUserID
        self.isOutgoing = isOutgoing
        self.webRTCClient = WebRTCClient(iceServers: iceServers)
        webRTCClient.delegate = self
    }

    // MARK: Local User Actions

    func start(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/start/begin")
        callQueue.async { [self] in
            webRTCClient.offer { sdpInfo in
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
                    case .success(let startCallResult):
                        state = .connecting
                        DDLogInfo("Call/\(callID)/start/success")
                        processPendingLocalIceCandidates()
                        webRTCClient.updateIceServers(stunServers: startCallResult.stunServers, turnServers: startCallResult.turnServers)
                        DispatchQueue.main.async {
                            completion(true)
                        }
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

    func answer(completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/answer/begin")
        callQueue.async { [self] in
            webRTCClient.answer { sdpInfo in
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
                        state = .active
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
            }
        }
    }

    func end(reason: EndCallReason) {
        DDLogInfo("Call/\(callID)/end/reason: \(reason)/begin")
        callQueue.async { [self] in
            isCallEndedLocally = true
            service.endCall(id: callID, to: peerUserID, reason: reason)

            // Send call report to the server.
            let direction = isOutgoing ? "outgoing" : "incoming"
            let networkType = MainAppContext.shared.service.reachabilityConnectionType.lowercased()
            DDLogInfo("Call/\(callID)/end/networkType: \(networkType)/checking")
            webRTCClient.fetchPeerConnectionStats() { report in
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
                    let durationMs = MainAppContext.shared.callManager.callDurationMs
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

            webRTCClient.end()
            state = .inactive
            DDLogInfo("Call/\(callID)/end/success")
        }
    }

    func muteAudio() {
        DDLogInfo("Call/\(callID)/muteAudio/begin")
        callQueue.async { [self] in
            webRTCClient.muteAudio()
            DDLogInfo("Call/\(callID)/muteAudio/success")
        }
    }

    func unmuteAudio() {
        DDLogInfo("Call/\(callID)/unmuteAudio/begin")
        callQueue.async { [self] in
            webRTCClient.unmuteAudio()
            DDLogInfo("Call/\(callID)/unmuteAudio/success")
        }
    }

    func speakerOn() {
        DDLogInfo("Call/\(callID)/speakerOn/begin")
        callQueue.async { [self] in
            webRTCClient.speakerOn()
            DDLogInfo("Call/\(callID)/speakerOn/success")
        }
    }

    func speakerOff() {
        DDLogInfo("Call/\(callID)/speakerOff/begin")
        callQueue.async { [self] in
            webRTCClient.speakerOff()
            DDLogInfo("Call/\(callID)/speakerOff/success")
        }
    }


    // MARK: Remote User actions.

    func didReceiveIncomingCall(sdpInfo: String, stunServers: [Server_StunServer], turnServers: [Server_TurnServer],
                                completion: @escaping ((_ success: Bool) -> Void)) {
        DDLogInfo("Call/\(callID)/didReceiveIncomingCall/begin")
        callQueue.async { [self] in
            service.sendCallRinging(id: callID, to: peerUserID)
            webRTCClient.updateIceServers(stunServers: stunServers, turnServers: turnServers)
            webRTCClient.set(remoteSdp: RTCSessionDescription(type: .offer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)/didReceiveIncomingCall/error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveIncomingCall/success")
                    state = .connecting
                    processPendingRemoteIceCandidateInfo()
                    DispatchQueue.main.async {
                        completion(true)
                    }
                }
            }
        }
    }

    func didReceiveAnswer(sdpInfo: String) {
        DDLogInfo("Call/\(callID)/didReceiveAnswer/begin")
        callQueue.async { [self] in
            webRTCClient.set(remoteSdp: RTCSessionDescription(type: .answer, sdp: sdpInfo)) { error in
                if let error = error {
                    DDLogError("Call/\(callID)didReceiveAnswer/error: \(error.localizedDescription)")
                } else {
                    DDLogInfo("Call/\(callID)/didReceiveAnswer/success")
                    state = .active
                    processPendingRemoteIceCandidateInfo()
                }
            }
        }
    }

    func didReceiveRemoteIceInfo(sdpInfo: String, sdpMLineIndex: Int32, sdpMid: String) {
        let iceCandidateInfo = IceCandidateInfo(sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sdpInfo: sdpInfo)
        DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/\(sdpInfo)-\(sdpMLineIndex)-\(sdpMid)/begin")
        callQueue.async { [self] in
            if state != .connecting && state != .active {
                DDLogInfo("Call/\(callID)/didReceiveRemoteIceInfo/queue this to pendingRemoteIceCandidates")
                pendingRemoteIceCandidates.append(iceCandidateInfo)
            } else {
                webRTCClient.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { error in
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

    func didReceiveEndCall() {
        DDLogInfo("Call/\(callID)/didReceiveEndCall/begin")
        callQueue.async { [self] in
            // TODO: send call report to the server.
            webRTCClient.end()
            state = .inactive
            DDLogInfo("Call/\(callID)/didReceiveEndCall/success")
        }
    }

    func didReceiveCallRinging() {
        DDLogInfo("Call/\(callID)/didReceiveCallRinging/begin")
        callQueue.async { [self] in
            state = .ringing
            DDLogInfo("Call/\(callID)/didReceiveCallRinging/success")
        }
    }

    func logPeerConnectionStats() {
        callQueue.async { [self] in
            webRTCClient.fetchPeerConnectionStats() { report in
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
                webRTCClient.set(remoteCandidate: iceCandidateInfo.rtcIceCandidate) { error in
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
                if state == .inactive {
                    // Hold ice candidates until we sent a startCall packet successfully.
                    pendingLocalIceCandidates.append(iceCandidateInfo)
                    DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didDiscoverLocalCandidate/queue this to pendingLocalIceCandidates")
                } else {
                    service.sendIceCandidate(id: callID, to: peerUserID, iceCandidateInfo: iceCandidateInfo)
                }
            }
        }
    }

    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didChangeConnectionState/begin")
        callQueue.async { [self] in
            switch state {
            case .disconnected, .closed, .failed:
                self.state = .disconnected
            case .connected:
                isConnected = true
            default:
                break
            }
            DDLogInfo("Call/\(callID)/WebRTCClientDelegate/didChangeConnectionState/success")
        }
    }

}
