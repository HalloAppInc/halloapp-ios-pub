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
        case play = 0, record = 1, call = 2

        // The associated integer is a priority, where the highest priority session category configures
        // the shared audio session
        static func < (lhs: AudioSession.Category, rhs: AudioSession.Category) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    let category: Category

    init(category: Category) {
        self.category = category
    }

    deinit {
        AudioSessionManager.endSession(self)
    }
}

class AudioSessionManager {

    private struct AudioSessionHolder {
        weak var audioSession: AudioSession?
    }

    private static var activeAudioSessionHolders: [AudioSessionHolder] = []
    private static var proximitySubscriber: AnyCancellable?
    private static var routeChangeSubscriber: AnyCancellable?
    private static var interruptionSubscriber: AnyCancellable?
    private static var isActive = false {
        didSet {
            guard oldValue != isActive else {
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(isActive, options: .notifyOthersOnDeactivation)
            } catch {
                DDLogError("AudioSessionManager/updateSharedAudioSession/setActive: \(error)")
            }
        }
    }

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

    private static func updateSharedAudioSession() {
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
        var category: AVAudioSession.Category = .ambient
        var options: AVAudioSession.CategoryOptions = []
        var mode: AVAudioSession.Mode = .default
        var disableIdleTimer = false
        var monitorProximity = false
        if let activeCategory = activeAudioSessions.map(\.category).max() {
            switch activeCategory {
            case .call:
                category = .playAndRecord
                options = .allowBluetooth
                mode = .voiceChat
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

        do {
            try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
        } catch {
            DDLogError("AudioSessionManager/updateSharedAudioSession/setCategory: \(error)")
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

        isActive = hasActiveAudioSession
    }

    private static func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                  return
              }

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

        switch type {
        case .began:
            MainAppContext.shared.mediaDidStartPlaying.send(nil)
        default:
            break
        }
    }
}
