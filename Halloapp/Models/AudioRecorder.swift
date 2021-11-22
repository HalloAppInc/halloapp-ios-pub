//
//  AudioRecorder.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Foundation

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderMicrphoneAccessDenied(_ recorder: AudioRecorder)
    func audioRecorderStarted(_ recorder: AudioRecorder)
    func audioRecorderStopped(_ recorder: AudioRecorder)
    func audioRecorderInterrupted(_ recorder: AudioRecorder)
    func audioRecorder(_ recorder: AudioRecorder, at time: String)
}

class AudioRecorder {
    private static let fileNamePrefix = "audio-recording-"

    public weak var delegate: AudioRecorderDelegate?
    public var url: URL? { recorder?.url }
    private(set) var isRecording = false
    public var duration: TimeInterval? { recorder?.currentTime }

    private var recorder: AVAudioRecorder?
    private var task: DispatchWorkItem?
    private var timer: Timer?
    private let sessionManager = AudioSessionManager()

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
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        stop(cancel: true)
    }

    func start() {
        authorize { [weak self] granted in
            guard let self = self else { return }

            if granted {
                // stop any audio or video currently playing
                MainAppContext.shared.mediaDidStartPlaying.send(nil)

                self.sessionManager.respectSilenceMode {
                    AudioServicesPlayAlertSound(1110)
                }

                // 300ms to avoid recording the start sound
                self.task?.cancel()
                self.task = DispatchWorkItem {
                    self.task = nil
                    self.sessionManager.save()
                    self.record()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: self.task!)
            } else {
                self.delegate?.audioRecorderMicrphoneAccessDenied(self)
            }
        }
    }

    private func authorize(action: @escaping (Bool) -> ()) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            action(true)
        case .denied, .restricted:
            action(false)
        case .notDetermined:
            delegate?.audioRecorderStopped(self)
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { _ in })
        default:
            DDLogError("AudioRecorder/authorize unknown AVAuthorizationStatus")
            action(false)
        }
    }

    private func record() {
        if let recorder = self.recorder, recorder.isRecording {
            stop(cancel: true)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
        } catch {
            return DDLogError("AudioRecorder/start: audio session [\(error)]")
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
                return DDLogError("AudioRecorder/start: recorder failed to start")
            }
            isRecording = true

            self.recorder = recorder
        } catch {
            return DDLogError("AudioRecorder/start: recorder failed init [\(error)]")
        }

        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        startTimer()
        delegate?.audioRecorderStarted(self)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {[weak self] _ in
            guard let self = self else { return }

            if let duration = self.recorder?.currentTime {
                self.delegate?.audioRecorder(self, at: duration.formatted)
            } else {
                self.delegate?.audioRecorder(self, at: "0:00")
            }
        }
    }

    func stop(cancel: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }

        timer?.invalidate()
        task?.cancel()

        if let recorder = self.recorder, recorder.isRecording || isRecording {
            isRecording = false

            recorder.stop()
            sessionManager.restore()

            if cancel {
                recorder.deleteRecording()
            }

            sessionManager.respectSilenceMode {
                AudioServicesPlayAlertSound(1111)
            }

            delegate?.audioRecorderStopped(self)
        }
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
            let limit = Date().addingTimeInterval(-TimeInterval(60 * 60 * 48))
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
        // keep recordings up to 48 hours
        let limit = Date().addingTimeInterval(-TimeInterval(60 * 60 * 48))

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
