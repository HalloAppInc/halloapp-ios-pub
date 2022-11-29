//
//  CameraPreset.swift
//  HalloApp
//
//  Created by Tanveer on 10/31/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import CoreCommon
import Core

protocol CameraPresetConfigurable {
    func set(preset: CameraPreset, animator: UIViewPropertyAnimator?)
}

extension CameraPreset {

    struct Options: OptionSet {
        let rawValue: Int

        static let photo = Options(rawValue: 1 << 0)
        static let video = Options(rawValue: 1 << 1)
        static let observeOrientation = Options(rawValue: 1 << 2)
        static let galleryAccess = Options(rawValue: 1 << 3)
        static let cropToViewfinder = Options(rawValue: 1 << 4)
        static let mergeMulticamImages = Options(rawValue: 1 << 5)
        static let allowsChangingLayout = Options(rawValue: 1 << 6)
        static let allowsTogglingLayout = Options(rawValue: 1 << 7)
        static let takeDelayedSecondPhoto = Options(rawValue: 1 << 8)
    }
}

struct CameraPreset: Equatable {

    let name: String
    let options: Options
    let aspectRatio: CGFloat
    let initialLayout: ViewfinderLayout
    let title: String?
    let subtitle: String?
    let backgroundView: UIView?

    init(name: String,
         options: Options,
         aspectRatio: CGFloat,
         layout: ViewfinderLayout,
         title: String? = nil,
         subtitle: String? = nil,
         backgroundView: UIView? = nil) {

        self.name = name
        self.options = options
        self.aspectRatio = aspectRatio
        self.initialLayout = layout
        self.title = title
        self.subtitle = subtitle
        self.backgroundView = backgroundView
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.name == rhs.name &&
               lhs.options == rhs.options &&
               lhs.aspectRatio == rhs.aspectRatio &&
               lhs.initialLayout == rhs.initialLayout &&
               lhs.title == rhs.title &&
               lhs.subtitle == rhs.subtitle
    }
}

// MARK: - Common presets

extension CameraPreset {

    fileprivate static var supportsMulticam: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    static func moment(_ context: MomentContext) -> Self {
        let supportsMulticam = Self.supportsMulticam
        let layout: ViewfinderLayout
        var options: Options = [.photo]

        let title = Localizations.newMomentTitle
        let subtitle: String

        switch context {
        case .normal:
            subtitle = Localizations.newMomentCameraSubtitle
        case .unlock(let post):
            let name = MainAppContext.shared.contactStore.firstName(for: post.userID,
                                                                     in: MainAppContext.shared.contactStore.viewContext)
            subtitle = String(format: Localizations.newMomentCameraUnlockSubtitle, name)
        }

        let background = UIView()
        background.backgroundColor = .momentPolaroid

        if supportsMulticam {
            layout = .splitPortrait(leading: .back)
            options.insert([.allowsTogglingLayout])
        } else {
            layout = .fullPortrait(.back)
            options.insert([.takeDelayedSecondPhoto])
        }

        #if targetEnvironment(simulator)
            options.insert(.galleryAccess)
        #endif

        return CameraPreset(name: "Moment",
                         options: options,
                     aspectRatio: 1,
                          layout: layout,
                           title: title,
                        subtitle: subtitle,
                  backgroundView: background)
    }

    static var photo: Self {
        let supportsMulticam = Self.supportsMulticam
        let layout: ViewfinderLayout = .fullLandscape(.back)
        var options: Options = [
            .photo, .video, .observeOrientation,
            .galleryAccess, .cropToViewfinder,
        ]

        if supportsMulticam {
            options.insert([.allowsTogglingLayout, .allowsChangingLayout, .mergeMulticamImages])
        }

        return CameraPreset(name: "Photo",
                         options: options,
                     aspectRatio: CGFloat(4) / CGFloat(3),
                          layout: layout)
    }
}
