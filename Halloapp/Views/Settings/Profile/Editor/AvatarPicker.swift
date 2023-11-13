//
//  AvatarPicker.swift
//  HalloApp
//
//  Created by Tanveer on 11/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Combine
import Core
import CoreCommon

struct AvatarPicker: View {

    let completion: (PendingMedia?) -> Void

    @State private var selected: [PendingMedia] = []
    @State private var edited: [PendingMedia] = []
    @State private var showCropper = false

    var body: some View {
        MediaPicker(configuration: .avatar, selected: $selected)
            .fullScreenCover(isPresented: $showCropper) {
                MediaEditor(configuration: .profile, media: $edited) { cancelled in
                    showCropper = false

                    if !cancelled {
                        completion(edited.first)
                    } else {
                        selected = []
                    }
                }
                .ignoresSafeArea(.all)
            }
            .onChange(of: selected) { selected in
                edited = selected
                showCropper = !selected.isEmpty
            }
    }
}

// MARK: - MediaPicker

struct MediaPicker: UIViewControllerRepresentable {

    let configuration: MediaPickerConfig
    @Binding var selected: [PendingMedia]

    func makeUIViewController(context: Context) -> UINavigationController {
        let viewController = MediaPickerViewController(config: configuration) { viewController, _, media, cancelled in
            selected = media
            viewController.reset(destination: nil, selected: [])

            if cancelled {
                context.environment.dismiss()
            }
        }

        return UINavigationController(rootViewController: viewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // no-op
    }
}

// MARK: - MediaEditor

struct MediaEditor: UIViewControllerRepresentable {

    let configuration: MediaEditConfig
    @Binding var media: [PendingMedia]
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let viewController = MediaEditViewController(config: configuration, mediaToEdit: media, selected: media.isEmpty ? nil : 0) { viewController, media, _, cancelled in
            self.media = media
            completion(cancelled)
        }

        return UINavigationController(rootViewController: viewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // no-op
    }
}

// MARK: - AvatarViewer

struct AvatarViewer: UIViewControllerRepresentable {

    let userID: UserID

    func makeUIViewController(context: Context) -> some UIViewController {
        let store = MainAppContext.shared.avatarStore
        let avatar = store.userAvatar(forUserId: userID)
        let future = Future<(URL?, UIImage?, CGSize), Never> { promise in
            store.loadFullSizeImage(for: avatar) { image in
                guard let image = image ?? store.userAvatar(forUserId: userID).image else {
                    promise(.success((nil, nil, .zero)))
                    return
                }

                promise(.success((nil, image.circularImage(), image.size)))
            }
        }

        return MediaExplorerController(imagePublisher: future.eraseToAnyPublisher())
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {

    }
}
