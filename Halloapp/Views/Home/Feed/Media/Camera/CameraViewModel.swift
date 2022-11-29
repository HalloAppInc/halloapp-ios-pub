//
//  CameraViewModel.swift
//  HalloApp
//
//  Created by Tanveer on 11/3/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Combine
import AVFoundation
import CoreMotion
import CocoaLumberjackSwift

extension CameraViewModel {

    enum Action {
        case willAppear, onDisappear, pause, resume
        case selectedPreset(CameraPreset), changedPreset
        case pushedNextLayout, pushedToggleLayout, completedNextLayout
        case tappedFocus(CameraPosition, CGPoint), pinchedZoom(CameraPosition, CGFloat)
        case toggleFlash, flipCamera
        case tappedShutter, beganShutterLongPress, endedShutterLongPress
    }

    struct ViewfinderState: Equatable {
        let layout: ViewfinderLayout
        let allowsChangingLayout: Bool
        let allowsTogglingLayout: Bool
    }
}

class CameraViewModel: ObservableObject {

    private var cancellables: Set<AnyCancellable> = []
    let presets: [CameraPreset]

    private lazy var sessionManager: CameraSessionManager = {
        let manager = CameraSessionManager()
        manager.delegate = self
        return manager
    }()

    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private lazy var impactGenerator = UIImpactFeedbackGenerator(style: .light)

    let actions = PassthroughSubject<Action, Never>()
    let photos = PassthroughSubject<[CaptureResult], Never>()
    let videos = PassthroughSubject<URL, Never>()

    @Published private(set) var cameraModel: CameraSessionManager?
    @Published private(set) var activePreset: CameraPreset?
    @Published private(set) var viewfinderState: ViewfinderState?
    @Published private(set) var orientation = UIDeviceOrientation.portrait
    @Published private(set) var isFlashEnabled = false
    @Published private(set) var error: CameraSessionError?
    @Published private(set) var isRecordingVideo = false
    @Published private(set) var videoDuration: Double?

    private(set) var isCurrentlyChangingPreset = false
    private var orientationObserver: Task<Void, Never>?

    init(presets: [CameraPreset], initial: Int) {
        self.presets = presets

        formSubscriptions()
        actions.send(.selectedPreset(presets[initial]))

        orientationObserver = Task { @MainActor [weak self] in
            for await orientation in CMDeviceMotion.orientations {
                guard self?.activePreset?.options.contains(.observeOrientation) ?? false else {
                    continue
                }

                self?.orientation = orientation
            }
        }
    }

    deinit {
        orientationObserver?.cancel()
    }

    private func formSubscriptions() {
        actions
            .sink { [weak self, sessionManager] action in
                guard let self else {
                    return
                }

                switch action {
                case .willAppear, .resume:
                    sessionManager.start()

                case .onDisappear, .pause:
                    sessionManager.stop(teardown: false)

                case .selectedPreset(let preset):
                    guard preset != self.activePreset else {
                        return
                    }

                    let oldPreset = self.activePreset
                    self.activePreset = preset
                    self.isCurrentlyChangingPreset = true
                    self.viewfinderState = self.viewfinderState(preset: preset)

                    if !preset.options.contains(.observeOrientation) {
                        self.orientation = .portrait
                    }

                    if oldPreset != nil {
                        self.selectionGenerator.selectionChanged()
                    }

                case .changedPreset:
                    self.isCurrentlyChangingPreset = false

                case .pushedNextLayout:
                    self.selectionGenerator.selectionChanged()
                    self.impactGenerator.prepare()
                    let next = self.viewfinderState?.layout.next
                    self.viewfinderState = self.viewfinderState(layout: next)

                case .pushedToggleLayout:
                    self.selectionGenerator.selectionChanged()
                    let toggled = self.viewfinderState?.layout.toggled
                    self.viewfinderState = self.viewfinderState(layout: toggled)

                case .completedNextLayout:
                    self.impactGenerator.impactOccurred()

                case .tappedFocus(let position, let point):
                    self.sessionManager.focus(position, on: point)

                case .pinchedZoom(let position, let scale):
                    self.sessionManager.zoom(position, to: scale)

                case .toggleFlash:
                    self.isFlashEnabled = !self.isFlashEnabled

                case .flipCamera:
                    guard sessionManager.isUsingMultipleCameras else {
                        return sessionManager.flipCamera()
                    }

                    let flipped = self.viewfinderState?.layout.flipped
                    self.viewfinderState = self.viewfinderState(layout: flipped)

                case .tappedShutter:
                    self.takePhotoIfPossible()

                case .beganShutterLongPress:
                    Task { await self.recordVideoIfPossible() }

                case .endedShutterLongPress:
                    self.stopRecordingVideo()
                }
            }
            .store(in: &cancellables)

        $isRecordingVideo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                guard
                    let self, let options = self.activePreset?.options,
                    let state = self.viewfinderState
                else {
                    return
                }

                let allowsChanging = options.contains(.allowsChangingLayout) && !isRecording
                let allowsToggling = options.contains(.allowsTogglingLayout) && !isRecording

                self.viewfinderState = .init(layout: state.layout,
                               allowsChangingLayout: allowsChanging,
                               allowsTogglingLayout: allowsToggling)
            }
            .store(in: &cancellables)
    }

    private func viewfinderState(preset: CameraPreset? = nil, layout: ViewfinderLayout? = nil) -> ViewfinderState? {
        guard let preset = preset ?? activePreset else {
            return nil
        }

        let allowsChangingLayout = preset.options.contains(.allowsChangingLayout)
        let allowsTogglingLayout = preset.options.contains(.allowsTogglingLayout)
        let layout = layout ?? preset.initialLayout

        return ViewfinderState(layout: layout,
                 allowsChangingLayout: allowsChangingLayout,
                 allowsTogglingLayout: allowsTogglingLayout)
    }

    private func takePhotoIfPossible() {
        guard let activePreset, var layout = viewfinderState?.layout else {
            return
        }

        if !sessionManager.isUsingMultipleCameras, layout.primaryCameraPosition != sessionManager.activeCamera {
            layout = layout.flipped
        }

        let isMulticam = sessionManager.isUsingMultipleCameras
        let takeDelayedPhoto = !isMulticam && activePreset.options.contains(.takeDelayedSecondPhoto)
        let request = PhotoCaptureRequest(layout: layout,
                                orientation: orientation,
                     takeDelayedSecondPhoto: takeDelayedPhoto)

        if let request, sessionManager.takePhoto(with: request) {
            Task { await handlePhotoResults(for: request) }
        }
    }

    @MainActor
    private func handlePhotoResults(for request: PhotoCaptureRequest) async {
        let deliverResultsOnArrival = !sessionManager.isUsingMultipleCameras
        var results = [CaptureResult]()

        do {
            for try await result in request.progress {
                if deliverResultsOnArrival {
                    photos.send([result])
                    continue
                }

                results.append(result)
            }
        } catch {
            DDLogError("CameraViewModel/handlePhotoResults/error \(String(describing: error))")
        }

        if !results.isEmpty {
            photos.send(results)
        }
    }

    private func recordVideoIfPossible() async {
        guard
            activePreset?.options.contains(.video) ?? false,
            !isRecordingVideo,
            let layout = viewfinderState?.layout,
            let request = VideoCaptureRequest(layout: layout, orientation: orientation)
        else {
            return
        }

        if await sessionManager.startRecording(with: request) {
            isRecordingVideo = true
            await handleVideoResults(for: request)
        }
    }

    @MainActor
    private func handleVideoResults(for request: VideoCaptureRequest) async {
        let durations = request.duration

        do {
            for try await duration in durations {
                videoDuration = duration
            }
        } catch {
            DDLogError("CameraViewModel/handleVideoResults/error \(String(describing: error))")
            stopRecordingVideo()
        }

        if let url = request.result {
            videos.send(url)
        }
    }

    private func stopRecordingVideo() {
        sessionManager.stopRecording()
        isRecordingVideo = false
        videoDuration = nil
    }
}

// MARK: - CameraModelDelegate methods

extension CameraViewModel: CameraSessionManagerDelegate {

    func sessionManager(_ model: CameraSessionManager, couldNotStart withError: Error) {
        guard let error = withError as? CameraSessionError else {
            DDLogError("CameraViewModel/modelCouldNotStart/un-handled error [\(String(describing: error))]")
            return
        }

        self.error = error
    }

    func sessionManagerWillStart(_ sessionManager: CameraSessionManager) {
        cameraModel = sessionManager
    }

    func sessionManagerDidStart(_ sessionManager: CameraSessionManager) {

    }

    func sessionManagerDidStop(_ sessionManager: CameraSessionManager) {

    }
}
