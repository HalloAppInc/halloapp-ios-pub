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
import Combine
import Core
import AVFoundation

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

enum CameraType {
    case front
    case back
}

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    func didStartReceivingRemoteVideo()
}

final class WebRTCClient: NSObject {

    // The `RTCPeerConnectionFactory` is in charge of creating new RTCPeerConnection instances.
    // A new RTCPeerConnection should be created every new call, but the factory is shared.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    weak var delegate: WebRTCClientDelegate?
    private let callType: CallType
    private var peerConnection: RTCPeerConnection?
    private var audioSession: AudioSession?
    private let audioQueue = DispatchQueue(label: "audio")
    private lazy var mediaConstraints: [String: String] = {
        switch callType {
        case .audio:
            return [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue]
        case .video:
            return [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
        }
    }()
    private var localDataChannel: RTCDataChannel?
    private var remoteDataChannel: RTCDataChannel?
    private var callConfig: Server_CallConfig?
    private var selectedCameraType: CameraType = .front
    // private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var localRenderer: RTCVideoRenderer?
    private var remoteRenderer: RTCVideoRenderer?
    private var cancellableSet: Set<AnyCancellable> = []

    init(callType: CallType) {
        self.callType = callType
        super.init()

        // set AudioSession to useManualAudio.
        // We should activate/deactivate the audioSession based on the callback from ios.
        // This is done in CallManager - ProviderDelegate callbacks.
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.useManualAudio = true
        rtcAudioSession.add(self)

        // Create Media tracks, configure audio and video capture sessions.
        createMediaTracks()
        configureAudioSession()
        startVideoCapture()

        cancellableSet.insert(
            // Notification to stop capture if app goes to background.
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.videoCapturer?.stopCapture()
            }
        )

        cancellableSet.insert(
            // Notification to start capture if app goes to foreground.
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.startVideoCapture()
            })
    }

    func initialize(iceServers: [RTCIceServer], config: Server_CallConfig) {
        self.callConfig = config
        let rtcConfig = RTCConfiguration()
        rtcConfig.iceServers = iceServers
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.audioJitterBufferFastAccelerate = callConfig?.audioJitterBufferFastAccelerate ?? false
        switch callConfig?.iceTransportPolicy {
        case .all:
            rtcConfig.iceTransportPolicy = .all
        case .relay:
            rtcConfig.iceTransportPolicy = .relay
        case .UNRECOGNIZED, .none:
            rtcConfig.iceTransportPolicy = .all
        }
        rtcConfig.continualGatheringPolicy = .gatherOnce

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue])

        guard let peerConnection = WebRTCClient.factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: nil) else {
            fatalError("WebRTCClient/Could not create new RTCPeerConnection")
        }
        self.peerConnection = peerConnection
        self.peerConnection?.delegate = self
        addTracksToPeerConnection()
    }

    // MARK: Signaling
    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        self.peerConnection?.offer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            self.peerConnection?.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }

    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void)  {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        self.peerConnection?.answer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            self.peerConnection?.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }

    func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> ()) {
        self.peerConnection?.setRemoteDescription(remoteSdp, completionHandler: completion)
    }

    func set(remoteCandidate: RTCIceCandidate, completion: @escaping (Error?) -> ()) {
        self.peerConnection?.add(remoteCandidate, completionHandler: completion)
    }

    func restartIce() {
        self.peerConnection?.restartIce()
    }

    func end() {
        peerConnection?.close()
        peerConnection = nil
        audioSession = nil
        videoCapturer?.stopCapture()
        videoCapturer = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        localRenderer = nil
        remoteRenderer = nil
        RTCAudioSession.sharedInstance().remove(self)
    }

    // MARK: Media
    private func configureAudioSession() {
        let category: AudioSession.Category
        switch callType {
        case .audio:
            category = .audioCall
        case .video:
            category = .videoCall
        }
        audioSession = AudioSession(category: category)
        AudioSessionManager.beginSession(audioSession)
    }

    func startVideoCapture() {
        let camera: AVCaptureDevice
        switch selectedCameraType {
        case .front:
            guard let frontCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }) else {
                DDLogError("WebRTCClient/startVideoCapture/failed/frontCamera not available")
                return
            }
            camera = frontCamera
        case .back:
            guard let backCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .back }) else {
                DDLogError("WebRTCClient/startVideoCapture/failed/backCamera not available")
                return
            }
            camera = backCamera
        }

        guard let captureFormat = camera.formats.first(where: { format in
            let width = CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
            let height = CMVideoFormatDescriptionGetDimensions(format.formatDescription).height
            return width == 1280 && height == 720
        }) else {
            DDLogError("WebRTCClient/startVideoCapture/failed/formats: \(camera.formats)")
            return
        }
        // TODO: Need to capture more details and pick a format here.
        // TODO: Need to verify that call config parameters are not crazy before using them.
        // TODO: use call config here.
        // We need to have some fallback in these cases.

        let fps = 30

        DDLogInfo("WebRTCClient/startVideoCapture/camera: \(camera.description)")
        DDLogInfo("WebRTCClient/startVideoCapture/captureFormat: \(captureFormat)")
        DDLogInfo("WebRTCClient/startVideoCapture/fps: \(fps)")

        videoCapturer?.startCapture(with: camera, format: captureFormat, fps: fps)
    }

    func stopVideoCapture() {
        videoCapturer?.stopCapture()
    }

    func renderLocalVideo(to renderer: RTCVideoRenderer) {
        self.localRenderer = renderer
        if let localVideoTrack = localVideoTrack {
            DDLogInfo("WebRTCClient/renderLocalVideo")
            localVideoTrack.add(renderer)
        }
    }

    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        self.remoteRenderer = renderer
        if let remoteVideoTrack = remoteVideoTrack {
            remoteVideoTrack.add(renderer)
            self.delegate?.didStartReceivingRemoteVideo()
        }
    }

    private func createMediaTracks() {
        // Audio
        let audioTrack = self.createAudioTrack()
        self.localAudioTrack = audioTrack

        // Video
        if callType == .video {
            let videoTrack = self.createVideoTrack()
            self.localVideoTrack = videoTrack
            // self.remoteVideoTrack = self.peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
            // Think if we'll ever trigger this -- else clean this up.
        }

        // Data
        if let dataChannel = createDataChannel() {
            dataChannel.delegate = self
            self.localDataChannel = dataChannel
        }
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = WebRTCClient.factory.videoSource()
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        return videoTrack
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }

    func addTracksToPeerConnection() {
        let streamId = "stream"
        if let localAudioTrack = localAudioTrack {
            self.peerConnection?.add(localAudioTrack, streamIds: [streamId])
            DDLogInfo("WebRTCClient/addTracksToPeerConnection/localAudioTrack: \(localAudioTrack)")
        }
        if callType == .video,
           let localVideoTrack = localVideoTrack {
            self.peerConnection?.add(localVideoTrack, streamIds: [streamId])
            DDLogInfo("WebRTCClient/addTracksToPeerConnection/localVideoTrack: \(localVideoTrack)")
        }
    }

    // MARK: Data Channels
    private func createDataChannel() -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection?.dataChannel(forLabel: "WebRTCData", configuration: config) else {
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
        peerConnection?.statistics { report in
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

    func peerConnection(_ peerConnection: RTCPeerConnection, didChangeStandardizedIceConnectionState newState: RTCIceConnectionState) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeStandardizedIceConnectionState: \(newState.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChangeLocalCandidate local: RTCIceCandidate, remoteCandidate remote: RTCIceCandidate, lastReceivedMs lastDataReceivedMs: Int32, changeReason reason: String) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeLocalCandidate/local: \(local.description)/remote: \(remote.description)/reason: \(reason)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DDLogDebug("WebRTCClient/peerConnection/didChangeRTCPeerConnectionState: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        DDLogDebug("WebRTCClient/peerConnection/didStartReceivingOnRTCRtpTransceiver: \(transceiver.description)")
        if transceiver.mediaType == .video {
            self.remoteVideoTrack = transceiver.receiver.track as? RTCVideoTrack
            if let remoteRenderer = remoteRenderer {
                self.remoteVideoTrack?.add(remoteRenderer)
                self.delegate?.didStartReceivingRemoteVideo()
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        rtpReceiver.delegate = self
        DDLogDebug("WebRTCClient/peerConnection/didAddRTCRtpReceiver/rtpReceiver: \(rtpReceiver.description)/streams: \(mediaStreams.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        DDLogDebug("WebRTCClient/peerConnection/didRemoveRTCRtpReceiver: \(rtpReceiver.description)")
    }
}

extension WebRTCClient: RTCRtpReceiverDelegate {
    func rtpReceiver(_ rtpReceiver: RTCRtpReceiver, didReceiveFirstPacketFor mediaType: RTCRtpMediaType) {
        DDLogDebug("WebRTCClient/rtpReceiver/didReceiveFirstPacketFor: \(rtpReceiver.description)/mediaType: \(mediaType.rawValue)")
    }
}

extension WebRTCClient {

    // MARK:- Video control
    func muteVideo() {
        self.setVideoEnabled(false)
    }

    func unmuteVideo() {
        self.setVideoEnabled(true)
    }

    private func setVideoEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCVideoTrack.self, isEnabled: isEnabled)
    }

    func switchCamera() {
        let currentCameraType = selectedCameraType
        switch currentCameraType {
        case .front:
            selectedCameraType = .back
        case .back:
            selectedCameraType = .front
        }
        // stopVideoCapture() -- do we have to do this?
        startVideoCapture()
    }

    // MARK:- Audio control
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
        peerConnection?.transceivers
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
        DDLogDebug("WebRTCClient/audioSessionDidChangeRoute/\(session.description): \(reason.rawValue): \(previousRoute.description)")
    }

}
