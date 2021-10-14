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
    func audioRecorder(_ recorder: AudioRecorder, at time: String)
}

class AudioRecorder {
    public weak var delegate: AudioRecorderDelegate?
    public var url: URL? { recorder?.url }
    public var isRecording = false
    public var duration: TimeInterval? { recorder?.currentTime }

    private var recorder: AVAudioRecorder?
    private lazy var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .dropTrailing
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()
    private var timer: Timer?
    private var savedSessionCategory: AVAudioSession.Category?
    private var savedSessionMode: AVAudioSession.Mode?
    private var savedSessionOptions: AVAudioSession.CategoryOptions?

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
                self.respectSilenceMode {
                    AudioServicesPlayAlertSound(1110)
                }

                // stop any audio or video currently playing
                MainAppContext.shared.mediaDidStartPlaying.send(nil)

                self.saveAudioSession()
                self.record()
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
                if let formatted = self.durationFormatter.string(from: duration) {
                    self.delegate?.audioRecorder(self, at: formatted)
                    return
                }
            }

            self.delegate?.audioRecorder(self, at: "0:00")
        }
    }

    func stop(cancel: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }

        timer?.invalidate()

        if let recorder = self.recorder, recorder.isRecording || isRecording {
            isRecording = false

            recorder.stop()
            restoreAudioSession()

            if cancel {
                recorder.deleteRecording()
            }

            respectSilenceMode {
                AudioServicesPlayAlertSound(1111)
            }

            delegate?.audioRecorderStopped(self)
        }
    }

    private func saveAudioSession() {
        let session = AVAudioSession.sharedInstance()

        savedSessionCategory = session.category
        savedSessionMode = session.mode
        savedSessionOptions = session.categoryOptions
    }

    private func restoreAudioSession() {
        guard let category = savedSessionCategory else { return }
        guard let mode = savedSessionMode else { return }
        guard let options = savedSessionOptions else { return }

        savedSessionCategory = nil
        savedSessionMode = nil
        savedSessionOptions = nil

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            return DDLogError("AudioRecorder/restoreAudioSession: \(error)")
        }
    }

    private func respectSilenceMode(callback: () -> ()) {
        saveAudioSession()

        let session = AVAudioSession.sharedInstance()

        // Respect silence mode
        do {
            try session.setCategory(.ambient)
            try session.setActive(true)
        } catch {
            return DDLogError("AudioRecorder/respectSilenceMode/default: \(error)")
        }

        callback()

        restoreAudioSession()
    }

    @objc func handleInterruption(notification: Notification) {
        stop(cancel: true)
    }
}
