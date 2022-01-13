//
//  WebRTCClient.swift
//  HalloApp
//
//  Created by Murali Balusu on 10/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import WebRTC
import CocoaLumberjackSwift
import Core

extension RTCSignalingState {
    var description: String {
        switch self {
        case .closed: return "closed"
        case .haveLocalOffer: return "haveLocalOffer"
        case .haveRemoteOffer: return "haveRemoteOffer"
        case .haveLocalPrAnswer: return "haveLocalPrAnswer"
        case .haveRemotePrAnswer: return "haveRemotePrAnswer"
        case .stable: return "stable"
        default: return "unknown"
        }
    }
}

extension RTCIceConnectionState {
    var description: String {
        switch self {
        case .closed: return "closed"
        case .new: return "new"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .count: return "count"
        case .checking: return "checking"
        case .completed: return "completed"
        case .connected: return "connected"
        default: return "unknown"
        }
    }
}

extension RTCIceGatheringState {
    var description: String {
        switch self {
        case .new: return "new"
        case .complete: return "complete"
        case .gathering: return "gathering"
        default: return "unknown"
        }
    }
}

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
}

final class WebRTCClient: NSObject {

    // The `RTCPeerConnectionFactory` is in charge of creating new RTCPeerConnection instances.
    // A new RTCPeerConnection should be created every new call, but the factory is shared.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    weak var delegate: WebRTCClientDelegate?
    private let peerConnection: RTCPeerConnection
    private var audioSession: AudioSession?
    private let audioQueue = DispatchQueue(label: "audio")
    private let mediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue]
    private var localDataChannel: RTCDataChannel?
    private var remoteDataChannel: RTCDataChannel?

    init(iceServers: [RTCIceServer]) {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        // Enables fast accelerate mode of jitter buffer.
        config.audioJitterBufferFastAccelerate = true
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue])

        guard let peerConnection = WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            fatalError("WebRTCClient/Could not create new RTCPeerConnection")
        }

        self.peerConnection = peerConnection

        super.init()

        // set AudioSession to useManualAudio.
        // We should activate/deactivate the audioSession based on the callback from ios.
        // This is done in CallManager - ProviderDelegate callbacks.
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.useManualAudio = true
        rtcAudioSession.add(self)

        createMediaSenders()
        configureAudioSession()
        self.peerConnection.delegate = self
    }

    // MARK: Signaling
    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        self.peerConnection.offer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }

    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void)  {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        self.peerConnection.answer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }

    func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> ()) {
        self.peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
    }

    func set(remoteCandidate: RTCIceCandidate, completion: @escaping (Error?) -> ()) {
        self.peerConnection.add(remoteCandidate, completionHandler: completion)
    }

    func updateIceServers(stunServers: [Server_StunServer], turnServers: [Server_TurnServer]) {
        let iceServers = WebRTCClient.getIceServers(stunServers: stunServers, turnServers: turnServers)
        self.peerConnection.configuration.iceServers.append(contentsOf: iceServers)
    }

    func restartIce() {
        self.peerConnection.restartIce()
    }

    func end() {
        self.peerConnection.close()
        audioSession = nil
        RTCAudioSession.sharedInstance().remove(self)
    }

    // MARK: Media
    private func configureAudioSession() {
        audioSession = AudioSession(category: .call)
        AudioSessionManager.beginSession(audioSession)
    }

    private func createMediaSenders() {
        let streamId = "stream"

        // Audio
        let audioTrack = self.createAudioTrack()
        self.peerConnection.add(audioTrack, streamIds: [streamId])
//        let audioTracks = peerConnection.transceivers.compactMap { $0.sender.track as? RTCAudioTrack }
//        audioTracks.forEach { $0.isEnabled = true }

        // Data
        if let dataChannel = createDataChannel() {
            dataChannel.delegate = self
            self.localDataChannel = dataChannel
        }
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }

    // MARK: Data Channels
    private func createDataChannel() -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection.dataChannel(forLabel: "WebRTCData", configuration: config) else {
            DDLogError("WebRTCClient/Warning: Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }

    func sendData(_ data: Data) {
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        self.remoteDataChannel?.sendData(buffer)
    }

    static func getIceServers(stunServers: [Server_StunServer], turnServers: [Server_TurnServer]) -> [RTCIceServer] {
        var iceServers: [RTCIceServer] = []
        var urls: [String] = []
        for stunServer in stunServers {
            urls.append("stun:" + stunServer.host + ":" + String(stunServer.port))
        }
        if !urls.isEmpty {
            iceServers.append(RTCIceServer(urlStrings: urls))
        }
        for turnServer in turnServers {
            let url = "turn:" +  turnServer.host + ":" + String(turnServer.port)
            let iceServer = RTCIceServer(urlStrings: [url], username: turnServer.username, credential: turnServer.password)
            iceServers.append(iceServer)
        }
        return iceServers
    }

    func fetchPeerConnectionStats(completion: @escaping (RTCStatisticsReport) -> Void) {
        peerConnection.statistics { report in
            completion(report)
        }
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeSignalingState: \(stateChanged.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DDLogDebug("WebRTCClient/peerConnection/didAddStream/\(stream.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DDLogDebug("WebRTCClient/peerConnection/didRemoveStream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        DDLogDebug("WebRTCClient/peerConnectionShouldNegotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeIceConnectionState: \(newState.description)")
        self.delegate?.webRTCClient(self, didChangeConnectionState: newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeIceGatheringState: \(newState.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DDLogDebug("WebRTCClient/peerConnection/didGenerateIceCandidate")
        self.delegate?.webRTCClient(self, didDiscoverLocalCandidate: candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        DDLogDebug("WebRTCClient/peerConnection/didRemoveIceCandidate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DDLogDebug("WebRTCClient/peerConnection/didOpenDataChannel: \(dataChannel.description)")
        self.remoteDataChannel = dataChannel
    }
}

// MARK:- Audio control
extension WebRTCClient {
    func muteAudio() {
        self.setAudioEnabled(false)
    }

    func unmuteAudio() {
        self.setAudioEnabled(true)
    }

    // Fallback to the default playing device: headphones/bluetooth/ear speaker
    func speakerOff() {
        self.audioQueue.async { [weak self] in
            self?.audioSession?.portOverride = .none
        }
    }

    // Force speaker
    func speakerOn() {
        self.audioQueue.async { [weak self] in
            self?.audioSession?.portOverride = .speaker
        }
    }

    private func setAudioEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCAudioTrack.self, isEnabled: isEnabled)
    }

    private func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
        peerConnection.transceivers
            .compactMap { return $0.sender.track as? T }
            .forEach { $0.isEnabled = isEnabled }
    }
}

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DDLogDebug("WebRTCClient/dataChannelDidChangeState/\(dataChannel.description)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        DDLogDebug("WebRTCClient/dataChannel/didReceiveMessageWith: \(buffer.data)")
    }
}

extension WebRTCClient: RTCAudioSessionDelegate {

    func audioSessionMediaServerReset(_ session: RTCAudioSession) {
        DDLogDebug("WebRTCClient/audioSessionMediaServerReset/\(session.description)")
    }

    func audioSessionMediaServerTerminated(_ session: RTCAudioSession) {
        DDLogDebug("WebRTCClient/audioSessionMediaServerTerminated/\(session.description)")
    }

    func audioSessionDidBeginInterruption(_ session: RTCAudioSession) {
        DDLogDebug("WebRTCClient/audioSessionDidBeginInterruption/\(session.description)")
    }

    func audioSessionDidEndInterruption(_ session: RTCAudioSession, shouldResumeSession: Bool) {
        DDLogDebug("WebRTCClient/audioSessionDidEndInterruption/\(session.description): \(shouldResumeSession)")
    }

    func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        DDLogDebug("WebRTCClient/audioSessionDidStartPlayOrRecord/\(session.description)")
    }

    func audioSessionDidStopPlayOrRecord(_ session: RTCAudioSession) {
        DDLogDebug("WebRTCClient/audioSessionDidStopPlayOrRecord/\(session.description)")
    }

    func audioSession(_ session: RTCAudioSession, didChangeCanPlayOrRecord canPlayOrRecord: Bool) {
        DDLogDebug("WebRTCClient/audioSessionDidChangeCanPlayOrRecord/\(session.description): \(canPlayOrRecord)")
    }

    func audioSession(_ audioSession: RTCAudioSession, failedToSetActive active: Bool, error: Error) {
        DDLogDebug("WebRTCClient/audioSessionFailedToSetActive/\(audioSession.description): \(active): \(error)")
    }

    func audioSession(_ audioSession: RTCAudioSession, didSetActive active: Bool) {
        DDLogDebug("WebRTCClient/audioSessionDidSetActive/\(audioSession.description): \(active)")
    }

    func audioSession(_ audioSession: RTCAudioSession, willSetActive active: Bool) {
        DDLogDebug("WebRTCClient/audioSessionWillSetActive/\(audioSession.description): \(active)")
    }

    func audioSessionDidChangeRoute(_ session: RTCAudioSession, reason: AVAudioSession.RouteChangeReason, previousRoute: AVAudioSessionRouteDescription) {
        DDLogDebug("WebRTCClient/audioSessionDidChangeRoute/\(session.description): \(reason.rawValue)")
    }

}
