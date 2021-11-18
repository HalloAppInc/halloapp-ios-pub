//
//  AudioSessionManager.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Foundation

class AudioSessionManager {
    private var savedSessionCategory: AVAudioSession.Category?
    private var savedSessionMode: AVAudioSession.Mode?
    private var savedSessionOptions: AVAudioSession.CategoryOptions?

    private var session = AVAudioSession.sharedInstance()

    func save() {
        let session = AVAudioSession.sharedInstance()

        savedSessionCategory = session.category
        savedSessionMode = session.mode
        savedSessionOptions = session.categoryOptions
    }

    func restore() {
        guard let category = savedSessionCategory else { return }
        guard let mode = savedSessionMode else { return }
        guard let options = savedSessionOptions else { return }

        savedSessionCategory = nil
        savedSessionMode = nil
        savedSessionOptions = nil

        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            return DDLogError("AudioRecorder/restoreAudioSession: \(error)")
        }
    }

    func respectSilenceMode(callback: () -> ()) {
        save()

        // Respect silence mode
        do {
            try session.setCategory(.ambient)
            try session.setActive(true)
        } catch {
            return DDLogError("AudioRecorder/respectSilenceMode/default: \(error)")
        }

        callback()

        restore()
    }
}
