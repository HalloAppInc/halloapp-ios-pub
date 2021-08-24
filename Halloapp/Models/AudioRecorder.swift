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
    public var isRecording: Bool { recorder?.isRecording == true }
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
    private var task: DispatchWorkItem?

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleInterruption),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance)
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
                AudioServicesPlaySystemSound(1110)

                // 300ms to avoid recording the start sound
                let task = DispatchWorkItem { self.record() }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: task)
                self.task = task
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
            AVCaptureDevice.requestAccess(for: .audio) { action($0) }
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
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [ .defaultToSpeaker])
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

            self.recorder = recorder
        } catch {
            return DDLogError("AudioRecorder/start: recorder failed init [\(error)]")
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
        task?.cancel()
        timer?.invalidate()

        if let recorder = self.recorder, recorder.isRecording {
            recorder.stop()

            if cancel {
                recorder.deleteRecording()
            }

            AudioServicesPlaySystemSound(1111)
        }

        delegate?.audioRecorderStopped(self)
    }

    @objc func handleInterruption(notification: Notification) {
        stop(cancel: true)
    }
}
