//
//  AudioPostComposer.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import Combine
import SwiftUI
import Core

private extension Localizations {

    static let newAudioPost = NSLocalizedString("composer.audio.title",
                                                value: "New Audio Post",
                                                comment: "Title for audio post composer")

    static let tapToRecord = NSLocalizedString("composer.audio.instructions",
                                               value: "Tap to record",
                                               comment: "Instructions for audio post composer")

    static let addImagesA11yLabel = NSLocalizedString("composer.audio.a11y.addImages",
                                                      value: "Add Images",
                                                      comment: "Accessibility label for add images button")

    static let startRecordingA11yLabel = NSLocalizedString("composer.audio.a11y.startRecording",
                                                           value: "Start Recording",
                                                           comment: "Accessibility label for starting an audio recording")

    static let stopRecordingA11yLabel = NSLocalizedString("composer.audio.a11y.stopRecording",
                                                          value: "Stop Recording",
                                                          comment: "Accessibility label for stopping an audio recording")

    static let shareRecordingA11yLabel = NSLocalizedString("composer.audio.a11y.shareRecording",
                                                          value: "Share",
                                                          comment: "Accessibility label for sharing a post")
}

// MARK: - AudioPostComposer

fileprivate enum AudioPostComposerState {
    case ready, recording, recorded
}

struct AudioPostComposer<MediaPicker: View>: View {

    @ObservedObject var recorder: AudioComposerRecorder
    var isReadyToShare: Bool
    var shareAction: (() -> Void)
    @Binding var presentMediaPicker: Bool
    @ViewBuilder var mediaPicker: () -> MediaPicker
    @State private var showPermissionsAlert = false

    private var state: AudioPostComposerState {
        if recorder.voiceNote != nil {
            return .recorded
        } else if recorder.isRecording {
            return .recording
        } else {
            return .ready
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ZStack(alignment: .center) {
                Text(Localizations.newAudioPost)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.audioComposerTitleText)
                    .opacity(state != .recording ? 1 : 0)
                DurationView(time: recorder.duration)
                    .foregroundColor(.lavaOrange)
                    .opacity(state == .recording ? 1 : 0)
            }
            .frame(height: 64)
            ZStack(alignment: .top) {
                RecordButton(
                    isRecording: state == .recording,
                    // opacity(0) still renders as an accessibility element, so we must pass this through
                    // to the internal button so it can set accessibility(hidden)
                    isHidden: state == .recorded,
                    action: {
                        let status = AVCaptureDevice.authorizationStatus(for: .audio)
                        if !recorder.isRecording, [.denied, .restricted].contains(status) {
                            showPermissionsAlert = true
                        } else {
                            recorder.isRecording.toggle()
                        }
                    },
                    audioMeter: recorder.meter)
                    .padding(.top, 4)
                    .alert(isPresented: $showPermissionsAlert) {
                        Alert(title: Text(Localizations.micAccessDeniedTitle),
                              message: Text(Localizations.micAccessDeniedMessage),
                              primaryButton: .default(Text(Localizations.settingsAppName), action: {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }),
                              secondaryButton: .cancel(Text(Localizations.buttonCancel)))
                    }
                AudioComposerPlayer(recorder: recorder)
                    .padding(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .opacity(state == .recorded ? 1 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 48)
            Text(Localizations.tapToRecord)
                .font(.footnote)
                .foregroundColor(.audioComposerHelperText)
                .padding(.top, 12)
                .opacity(state == .ready ? 1 : 0)
            HStack(alignment: .center) {
                Button(action: { presentMediaPicker = true }) {
                    Image("icon_add_photo")
                        .foregroundColor(.audioComposerRecordButtonForeground)
                }
                .accessibility(label: Text(Localizations.addImagesA11yLabel))
                .accessibility(hidden: state != .recorded)
                .sheet(isPresented: $presentMediaPicker) {
                    mediaPicker()
                }
                .padding(EdgeInsets(top: 0, leading: 24, bottom: 24, trailing: 0))
                .opacity(state == .recorded ? 1 : 0)
                Spacer()
                Button(action: shareAction) {
                    Image("icon_share")
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle())
                        .accentColor(.lavaOrange)
                }
                .accessibility(label: Text(Localizations.shareRecordingA11yLabel))
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16))
                .disabled(!isReadyToShare)
            }
        }
        .animation(.default)
        .fixedSize(horizontal: false, vertical: true)
    }
}

fileprivate struct DurationView: View {

    var time: String

    @State private var isAnimating = false

    var body: some View {
        HStack {
            Circle()
                .fill()
                .frame(width: 8, height: 8)
                .padding(.trailing, 5)
                .opacity(isAnimating ? 1 : 0.2)
                .scaleEffect(isAnimating ? 1 : 0.8)
                .animation(Animation.easeInOut(duration: 0.6).repeatForever())
                .onAppear {
                    isAnimating.toggle()
                }
            Text(time)
                .font(.system(size: 21, weight: .medium).monospacedDigit())
        }
    }
}

fileprivate struct RecordButton: View {

    var isRecording: Bool
    var isHidden: Bool

    @State private var averagePowerScale: CGFloat = 1
    @State private var peakPowerScale: CGFloat = 1

    let action: () -> Void

    var audioMeter: CurrentValueSubject<(averagePower: Float, peakPower: Float), Never>

    private var currentBackgroundColor: Color {
        return isRecording ? .audioComposerRecordButtonBackground : .audioComposerRecordButtonForeground
    }

    var body: some View {
        ZStack(alignment: .center) {
            Group {
                Circle()
                    .fill(Color.audioComposerRecordButtonForeground.opacity(0.3))
                    .scaleEffect(peakPowerScale)
                Circle()
                    .fill(Color.audioComposerRecordButtonForeground.opacity(0.3))
                    .scaleEffect(averagePowerScale)
            }
            .animation(.default)
            .opacity(isRecording ? 1 : 0)
            Button(action: action) {
                Image(isRecording ? "icon_stop" : "icon_mic")
                    .frame(width: 76, height: 76)
                    .foregroundColor(isRecording ? .blue : .white)
                    .background(Circle()
                                    .strokeBorder(Color.audioComposerRecordButtonForeground, lineWidth: 2, antialiased: true)
                                    .background(Circle().fill(currentBackgroundColor))
                                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 0))
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)

            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                action()
            })
            .accessibility(label: Text(isRecording ? Localizations.stopRecordingA11yLabel : Localizations.startRecordingA11yLabel))
            .accessibility(hidden: isHidden)
        }
        .opacity(isHidden ? 0 : 1)
        .onReceive(audioMeter) { (averagePower: Float, peakPower: Float) in
            withAnimation {
                averagePowerScale = min(2, max(1, 1 + 1.5 * CGFloat(pow(10, (0.05 * peakPower)))))
                peakPowerScale = min(2, max(1, 1 + 3 * CGFloat(pow(10, (0.05 * averagePower)))))
            }
        }
    }
}

// MARK: - AudioComposerRecorder

class AudioComposerRecorder: NSObject, ObservableObject {

    @Published var duration = 0.formatted
    @Published var isRecording = false {
        didSet {
            if audioRecorder.isRecording != isRecording {
                isRecording ? audioRecorder.start() : audioRecorder.stop(cancel: false)
            }
        }
    }

    @Published var voiceNote: PendingMedia?

    var meter: CurrentValueSubject<(averagePower: Float, peakPower: Float), Never> {
        return audioRecorder.meter
    }

    private lazy var audioRecorder: AudioRecorder = {
        let audioRecorder = AudioRecorder()
        audioRecorder.delegate = self
        return audioRecorder
    }()
}

extension AudioComposerRecorder: AudioRecorderDelegate {

    func audioRecorderMicrphoneAccessDenied(_ recorder: AudioRecorder) {
        // no-op
    }

    func audioRecorderStarted(_ recorder: AudioRecorder) {
        isRecording = true
    }

    func audioRecorderStopped(_ recorder: AudioRecorder) {
        stopRecordingAndSaveIfNeeded()
    }

    func audioRecorderInterrupted(_ recorder: AudioRecorder) {
        stopRecordingAndSaveIfNeeded()
    }

    func audioRecorder(_ recorder: AudioRecorder, at time: String) {
        duration = time
    }

    private func stopRecordingAndSaveIfNeeded() {
        isRecording = false
        duration = 0.formatted

        guard let url = audioRecorder.saveVoicePost() else {
            return
        }

        let pendingMedia = PendingMedia(type: .audio)
        pendingMedia.fileURL = url
        pendingMedia.size = .zero
        pendingMedia.order = 0
        voiceNote = pendingMedia
    }
}

// MARK: - AudioComposerPlayer

fileprivate struct AudioComposerPlayer: UIViewRepresentable {

    @ObservedObject var recorder: AudioComposerRecorder

    func makeUIView(context: Context) -> PostAudioView {
        let postAudioView = PostAudioView(configuration: .composer)
        postAudioView.delegate = context.coordinator
        postAudioView.isSeen = true
        postAudioView.autoresizingMask = .flexibleWidth
        return postAudioView
    }

    func updateUIView(_ postAudioView: PostAudioView, context: Context) {
        postAudioView.url = recorder.voiceNote?.fileURL
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, PostAudioViewDelegate {

        private let postAudioPlayer: AudioComposerPlayer

        init(_ postAudioPlayer: AudioComposerPlayer) {
            self.postAudioPlayer = postAudioPlayer
        }

        func postAudioViewDidRequestDeletion(_ postAudioView: PostAudioView) {
            postAudioPlayer.recorder.voiceNote = nil
        }
    }
}
