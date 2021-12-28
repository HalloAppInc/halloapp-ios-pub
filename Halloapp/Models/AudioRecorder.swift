//
//  AudioRecorder.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Foundation

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderMicrophoneAccessDenied(_ recorder: AudioRecorder)
    func audioRecorderStarted(_ recorder: AudioRecorder)
    func audioRecorderStopped(_ recorder: AudioRecorder)
    func audioRecorderInterrupted(_ recorder: AudioRecorder)
    func audioRecorder(_ recorder: AudioRecorder, at time: String)
}

class AudioRecorder {
    private static let fileNamePrefix = "audio-recording-"

    // keep recordings up to 48 hours
    private class var recordingExpiryDate: Date {
        return Date().addingTimeInterval(Date.hours(-48))
    }

    public weak var delegate: AudioRecorderDelegate?
    public var url: URL? { recorder?.url }
    private(set) var isRecording = false
    public var duration: TimeInterval? { recorder?.currentTime }

    private var recorder: AVAudioRecorder?
    private var task: DispatchWorkItem?
    private var displayLink: CADisplayLink?
    private var audioSession: AudioSession?
    private var pendingRecord: (() -> Void)?
    private var isMeteringEnabled = false {
        didSet {
            updateMeteringEnabled()
        }
    }

    lazy var meter: CurrentValueSubject<(averagePower: Float, peakPower: Float), Never> = {
        isMeteringEnabled = true
        return CurrentValueSubject((-160, -160))
    }()

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleInterruption),
                       name: AVAudioSession.interruptionNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleInterruption),
                       name: UIApplication.willResignActiveNotification,
                       object: nil)

        DispatchQueue.global().async {
            self.removeOldRecordings()
        }
    }

    deinit {
        stopTimer()
        NotificationCenter.default.removeObserver(self)
        stop(cancel: true)
    }

    func start() {
        let isAuthorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isAuthorized = true
        case .denied, .restricted:
            isAuthorized = false
            delegate?.audioRecorderMicrophoneAccessDenied(self)
        case .notDetermined:
            isAuthorized = false
            delegate?.audioRecorderStopped(self)
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { _ in })
        default:
            isAuthorized = false
            delegate?.audioRecorderMicrophoneAccessDenied(self)
            DDLogError("AudioRecorder/authorize unknown AVAuthorizationStatus")
        }

        guard isAuthorized else {
            return
        }

        isRecording = true
        delegate?.audioRecorderStarted(self)

        audioSession = AudioSession(category: .record)
        AudioSessionManager.beginSession(audioSession)

        // stop any audio or video currently playing
        MainAppContext.shared.mediaDidStartPlaying.send(nil)

        pendingRecord = record

        AudioServicesPlayAlertSoundWithCompletion(1110) { [weak self] in
            DispatchQueue.main.async {
                self?.pendingRecord?()
            }
        }
    }

    private func record() {
        if let recorder = recorder, recorder.isRecording {
            stop(cancel: true)
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("aac")
        let settings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRatePerChannelKey: 96000,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                stop(cancel: true)
                return DDLogError("AudioRecorder/start: recorder failed to start")
            }

            self.recorder = recorder
            updateMeteringEnabled()
        } catch {
            stop(cancel: true)
            return DDLogError("AudioRecorder/start: recorder failed init [\(error)]")
        }

        startTimer()
    }

    private func startTimer() {
        displayLink?.invalidate()
        let displayLink = CADisplayLink(weakTarget: self, selector: #selector(updateTimer))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopTimer() {
        displayLink?.invalidate()
    }

    @objc private func updateTimer() {
        if let duration = self.recorder?.currentTime {
            self.delegate?.audioRecorder(self, at: duration.formatted)
        } else {
            self.delegate?.audioRecorder(self, at: "0:00")
        }

        if isMeteringEnabled, let recorder = recorder {
            recorder.updateMeters()
            meter.send((averagePower: recorder.averagePower(forChannel: 0),
                        peakPower: recorder.peakPower(forChannel: 0)))
        }
    }

    private func updateMeteringEnabled() {
        recorder?.isMeteringEnabled = isMeteringEnabled
    }

    func stop(cancel: Bool) {
        stopTimer()
        pendingRecord = nil
        isRecording = false

        if let recorder = self.recorder, recorder.isRecording {
            recorder.stop()
            AudioSessionManager.endSession(audioSession)

            if cancel {
                recorder.deleteRecording()
            }

            AudioServicesPlayAlertSound(1111)
        }

        delegate?.audioRecorderStopped(self)
    }

    @objc func handleInterruption(notification: Notification) {
        if let duration = recorder?.currentTime, isRecording && duration > 1 {
            stop(cancel: false)
            delegate?.audioRecorderInterrupted(self)
        } else {
            stop(cancel: true)
        }
    }

    // MARK: Saving audio recordings

    func saveVoiceComment(for postId: String) -> URL? {
        return saveRecording(withId: "voice-comment-\(postId)")
    }

    class func voiceComment(for postId: String) -> URL? {
        return recording(withId: "voice-comment-\(postId)")
    }

    func saveVoiceNote(from: String, to: String) -> URL? {
        return saveRecording(withId: "voice-note-\(from)-\(to)")
    }

    class func voiceNote(from: String, to: String) -> URL? {
        return recording(withId: "voice-note-\(from)-\(to)")
    }

    func saveVoicePost() -> URL? {
        return saveRecording(withId: "voice-post-\(UUID().uuidString)")
    }

    func saveRecording(withId id: String) -> URL? {
        guard let url = recorder?.url else { return nil }
        guard let destination = Self.recordingUrl(withId: id) else { return nil }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            DDLogError("AudioRecorder/save: \(error)")
            return nil
        }

        return destination
    }

    class func recordingUrl(withId id: String) -> URL? {
        guard let key = id.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileNamePrefix)\(key)", isDirectory: false)
            .appendingPathExtension("aac")
    }

    class func recording(withId id: String) -> URL? {
        guard let url = recordingUrl(withId: id) else { return nil }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let limit = Self.recordingExpiryDate
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)

            // keep recordings up to 48 hours
            if let date = attrs[.creationDate] as? Date, date < limit {
                return nil
            }
        } catch {
            DDLogError("AudioRecorder/recording: missing attributes \(error)")
            return nil
        }

        return url
    }

    private func removeOldRecordings() {
        let limit = Self.recordingExpiryDate

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

            for url in contents {
                if url.lastPathComponent.hasPrefix(Self.fileNamePrefix) {
                    if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, date < limit {
                        try FileManager.default.removeItem(at: url)
                    }
                }
            }
        } catch {
            DDLogError("AudioRecorder/removeOldRecordings: \(error)")
        }
    }
}
