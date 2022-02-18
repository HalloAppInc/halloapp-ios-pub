//
//  AudioSessionManager.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Foundation

/*
 Consumer must hold a strong reference to an active AudioSession, it is ended on release
 */
class AudioSession {

    enum Category: Int, Comparable {
        case play = 0, record = 1, audioCall = 2, videoCall = 3

        // The associated integer is a priority, where the highest priority session category configures
        // the shared audio session
        static func < (lhs: AudioSession.Category, rhs: AudioSession.Category) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    enum PortOverride: Int {
        case none, speaker
    }

    let category: Category

    var portOverride: PortOverride {
        didSet {
            AudioSessionManager.updateSharedAudioSession()
        }
    }

    init(category: Category, portOverride: PortOverride = .none) {
        self.category = category
        self.portOverride = portOverride
    }

    deinit {
        AudioSessionManager.endSession(self)
    }
}

class AudioSessionManager {

    private struct AudioSessionHolder {
        weak var audioSession: AudioSession?
    }

    private static var activeAudioSessionHolders: [AudioSessionHolder] = [] {
        didSet {
            activeAudioSessionHolders.removeAll { $0.audioSession == nil }
        }
    }

    // Whether we have activated the audio session
    private static var isActive = false

    // Whether an external source has activated the audio session
    // Used for CallKit handoff
    private static var isExternallyActive = false

    private static var portOverride: AVAudioSession.PortOverride = .none

    private static var proximitySubscriber: AnyCancellable?
    private static var routeChangeSubscriber: AnyCancellable?
    private static var interruptionSubscriber: AnyCancellable?

    static func isSessionActive(_ audioSession: AudioSession?) -> Bool {
        return audioSession != nil && activeAudioSessionHolders.contains { $0.audioSession === audioSession }
    }

    static func beginSession(_ audioSession: AudioSession?) {
        guard let audioSession = audioSession, !isSessionActive(audioSession) else {
            return
        }

        activeAudioSessionHolders.append(AudioSessionHolder(audioSession: audioSession))
        updateSharedAudioSession()
    }

    static func endSession(_ audioSession: AudioSession?) {
        guard let audioSession = audioSession, isSessionActive(audioSession) else {
            return
        }

        activeAudioSessionHolders.removeAll { $0.audioSession === audioSession }
        updateSharedAudioSession()
    }

    private static let initializeOnce: Void = {
        updateSharedAudioSession()
    }()

    static func initialize() {
        initializeOnce
    }

    fileprivate static func updateSharedAudioSession() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                updateSharedAudioSession()
            }
            return
        }

        let activeAudioSessions = activeAudioSessionHolders.compactMap(\.audioSession)
        let hasActiveAudioSession = !activeAudioSessionHolders.compactMap(\.audioSession).isEmpty
        let isPlayingOnDeviceSpeaker = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.builtInReceiver, .builtInSpeaker].contains($0.portType)
        }

        // Determine options per active category
        var category: AVAudioSession.Category = .playback
        var options: AVAudioSession.CategoryOptions = []
        var mode: AVAudioSession.Mode = .default
        var portOverride: AVAudioSession.PortOverride = .none
        var disableIdleTimer = false
        var monitorProximity = false

        var activeAudioSession: AudioSession? = nil
        // Find the last (most recently began) audio session with the hightest priority category
        for audioSession in activeAudioSessions {
            if let category = activeAudioSession?.category, audioSession.category < category {
                continue
            }
            activeAudioSession = audioSession
        }

        if let activeAudioSession = activeAudioSession {

            // set portOverride
            switch activeAudioSession.portOverride {
            case .speaker:
                portOverride = .speaker
            default:
                portOverride = .none
            }

            switch activeAudioSession.category {
            case .audioCall:
                category = .playAndRecord
                options = .allowBluetooth
                mode = .voiceChat
            case .videoCall:
                category = .playAndRecord
                options = .allowBluetooth
                mode = .videoChat
                portOverride = .speaker
            case .play:
                if isPlayingOnDeviceSpeaker, UIDevice.current.proximityState {
                    category = .playAndRecord
                } else {
                    category = .playback
                }
                if #available(iOS 14.5, *) {
                    options = .overrideMutedMicrophoneInterruption
                }
                disableIdleTimer = true
                monitorProximity = true
            case .record:
                category = .playAndRecord
                disableIdleTimer = true
            }
        }

        let sharedAudioSession = AVAudioSession.sharedInstance()
        if sharedAudioSession.category != category || sharedAudioSession.mode != mode || sharedAudioSession.categoryOptions != options {
            do {
                try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
                DDLogInfo("AudioSessionManager/updateSharedAudioSession: \(category) \(mode) \(options)")
            } catch {
                DDLogError("AudioSessionManager/updateSharedAudioSession/failedSetCategory: \(error)")
            }
        }

        if self.portOverride != portOverride {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(portOverride)
                self.portOverride = portOverride
                DDLogInfo("AudioSessionManager/portOverride: \(portOverride)")
            } catch {
                DDLogError("AudioSessionManager/failedSetOverrideAudioPort: \(error)")
            }
        }

        // Idle timer
        UIApplication.shared.isIdleTimerDisabled = disableIdleTimer

        // Monitor proximity to switch between receiver and speaker
        if monitorProximity, isPlayingOnDeviceSpeaker {
            UIDevice.current.isProximityMonitoringEnabled = true
            if proximitySubscriber == nil {
                proximitySubscriber = NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)
                    .sink { _ in
                        updateSharedAudioSession()
                    }
            }
        } else {
            UIDevice.current.isProximityMonitoringEnabled = false
            proximitySubscriber = nil
        }

        // Monitor route changes & external interruptions
        if hasActiveAudioSession {
            if routeChangeSubscriber == nil {
                routeChangeSubscriber = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
                    .sink(receiveValue: handleRouteChange(_:))
            }
            if interruptionSubscriber == nil {
                interruptionSubscriber = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
                    .sink(receiveValue: handleInterruption(_:))
            }
        } else {
            routeChangeSubscriber = nil
            interruptionSubscriber = nil
        }

        if !isExternallyActive, hasActiveAudioSession != isActive {
            do {
                try AVAudioSession.sharedInstance().setActive(hasActiveAudioSession, options: .notifyOthersOnDeactivation)
                isActive = hasActiveAudioSession
                DDLogInfo("AudioSessionManager/setActive: \(hasActiveAudioSession)")
            } catch {
                DDLogError("AudioSessionManager/failedSetActive: \(hasActiveAudioSession) \(error)")
            }
        }
    }

    private static func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                  return
              }

        DDLogInfo("AudioSessionManager/handleRouteChange/reason: \(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            // Pause when headphones are disconnected
            MainAppContext.shared.mediaDidStartPlaying.send(nil)
        default:
            break
        }

        updateSharedAudioSession()
    }

    private static func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                  return
              }

        DDLogInfo("AudioSessionManager/handleInterruption/type: \(type.rawValue)")

        switch type {
        case .began:
            MainAppContext.shared.mediaDidStartPlaying.send(nil)
        default:
            break
        }


        if #available(iOS 14.5, *) {
            guard let reasonValue = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt,
                  let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) else {
                      return
                  }
            DDLogInfo("AudioSessionManager/handleInterruption/reason: \(reason.rawValue)")
        }
    }

    static func unmanagedAudioSessionDidActivate() {
        if isExternallyActive {
            DDLogError("AudioSessionManager/unbalancedUnmanagedActivation")
        }
        isExternallyActive = true
        updateSharedAudioSession()
    }

    static func unmanagedAudioSessionDidDeactivate() {
        if !isExternallyActive {
            DDLogError("AudioSessionManager/unbalancedUnmanagedDeactivation")
        }
        isExternallyActive = false
        updateSharedAudioSession()
    }
}
