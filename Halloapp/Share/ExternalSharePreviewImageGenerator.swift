//
//  ExternalSharePreviewImageGenerator.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

class ExternalSharePreviewImageGenerator {

    private struct Constants {
        static let preferredMaxMediaSize = CGSize(width: 320, height: 400)
        static let scale: CGFloat = 2
    }

    static func image(for post: FeedPost, mediaIndex: Int?, addBottomPadding: Bool = false) -> UIImage {
        let orderedMedia = post.media?.sorted(by: { $0.order < $1.order })
        let mediaImage: UIImage?
        if let orderedMedia, !orderedMedia.isEmpty {
            if post.isMoment,
               orderedMedia.count >= 2,
               let frontImage = orderedMedia[0].mediaURL.flatMap({ UIImage(contentsOfFile: $0.path) }),
               let backImage = orderedMedia[1].mediaURL.flatMap({ UIImage(contentsOfFile: $0.path) }) {
                let selfieLeading = post.isMomentSelfieLeading
                mediaImage = UIImage.combine(leading: selfieLeading ? frontImage : backImage, trailing: selfieLeading ? backImage : frontImage)
            } else {
                let media: CommonMedia?
                if let mediaIndex = mediaIndex, mediaIndex < orderedMedia.count, orderedMedia[mediaIndex].mediaURL != nil {
                    media = orderedMedia[mediaIndex]
                } else {
                    media = orderedMedia.first { $0.mediaURL != nil }
                }

                if let media, let mediaURL = media.mediaURL {
                    switch media.type {
                    case .image:
                        mediaImage = UIImage(contentsOfFile: mediaURL.path)
                    case .video:
                        mediaImage = VideoUtils.videoPreviewImage(url: mediaURL)
                    case .audio, .document:
                        // not supported
                        mediaImage = nil
                    }
                } else {
                    mediaImage = nil
                }
            }
        } else if let linkPreviewMedia = post.linkPreviews?.first?.media?.first, linkPreviewMedia.type == .image, let mediaURL = linkPreviewMedia.mediaURL {
            mediaImage = UIImage(contentsOfFile: mediaURL.path)
        } else {
            mediaImage = nil
        }

        let contactStore = MainAppContext.shared.contactStore
        let text = contactStore.textWithMentions(post.rawText, mentions: post.orderedMentions, in: contactStore.viewContext)?.string

        let viewToRender: UIView
        if let mediaImage {
            viewToRender = MediaPreviewView(mediaImage: mediaImage, text: text, preferredMaxImageSize: Constants.preferredMaxMediaSize)
        } else if let text {
            viewToRender = TextPreviewView(text: text)
        } else {
            // Nothing to show!
            return UIImage()
        }

        let footerLabel = UILabel()
        footerLabel.attributedText = watermarkAttributedString
        footerLabel.numberOfLines = 0

        let stackedViews: [UIView]
        if addBottomPadding {
            // leave space for external app chrome on bottom, provided by stackview spacing
            let spacerView = UIView()
            NSLayoutConstraint.activate([
                spacerView.widthAnchor.constraint(equalToConstant: 0),
                spacerView.heightAnchor.constraint(equalToConstant: 0),
            ])
            stackedViews = [viewToRender, footerLabel, spacerView]
        } else {
            stackedViews = [viewToRender, footerLabel]
        }

        let footerStack = UIStackView(arrangedSubviews: stackedViews)
        footerStack.axis = .vertical
        footerStack.alignment = .center
        footerStack.spacing = 60

        let renderSize = footerStack.systemLayoutSizeFitting(CGSize(width: Constants.preferredMaxMediaSize.width, height: CGFloat.greatestFiniteMagnitude),
                                                              withHorizontalFittingPriority: .required,
                                                              verticalFittingPriority: .fittingSizeLevel)

        let bounds = CGRect(origin: .zero, size: renderSize)
        footerStack.frame = bounds

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        let imageBounds = bounds.applying(CGAffineTransform(scaleX: Constants.scale, y: Constants.scale))

        return UIGraphicsImageRenderer(bounds: imageBounds).image { context in
            footerStack.drawHierarchy(in: imageBounds, afterScreenUpdates: true)
        }
    }

    private class MediaPreviewView: UIStackView {

        init(mediaImage: UIImage, text: String?, preferredMaxImageSize: CGSize) {
            super.init(frame: .zero)

            alignment = .center
            axis = .vertical
            spacing = 16

            let imageView = UIImageView(image: mediaImage)
            imageView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 4

            let imageSize = AVMakeRect(aspectRatio: mediaImage.size, insideRect: CGRect(origin: .zero, size: preferredMaxImageSize)).size
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
                imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
            ])

            addArrangedSubview(imageView)

            if let text = text {
                let label = UILabel()
                label.font = .systemFont(ofSize: 16, weight: .regular)
                label.numberOfLines = 3
                label.text = text
                label.textColor = .white.withAlphaComponent(0.75)
                addArrangedSubview(label)
            }
        }

        required init(coder: NSCoder) {
            fatalError()
        }
    }

    private class TextPreviewView: UIView {

        init(text: String) {
            super.init(frame: .zero)

            layer.cornerRadius = 20
            backgroundColor = UIColor(red: 0.098, green: 0.094, blue: 0.086, alpha: 1)

            let label = UILabel()
            if text.count <= 140 {
                label.font = .systemFont(ofSize: 24, weight: .regular)
            } else {
                label.font = .systemFont(ofSize: 19, weight: .regular)
            }
            label.numberOfLines = 16
            label.text = text
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }

    private static let watermarkAttributedString: NSAttributedString = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.25
        paragraphStyle.alignment = .center

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1.0
        shadow.shadowOffset = CGSize(width: 0.0, height: 1.0)
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.1)

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.gothamFont(ofFixedSize: 17, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle,
            .shadow: shadow,
        ]

        let postedFromString = String(format: Localizations.postedFrom, Localizations.appNameHalloApp)
        let watermarkAttributedString = NSMutableAttributedString(string: postedFromString, attributes: defaultAttributes)
        watermarkAttributedString.append(NSAttributedString(string: "\nhalloapp.com", attributes: defaultAttributes))

        if let range = watermarkAttributedString.string.range(of: Localizations.appNameHalloApp) {
            watermarkAttributedString.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(range, in: watermarkAttributedString.string))
        }

        return watermarkAttributedString
    }()

    static func video(for mediaURL: URL, addWatermark: Bool = false) async -> URL? {
        let asset = AVAsset(url: mediaURL)

        let preset = addWatermark ? AVAssetExportPresetPassthrough : AVAssetExportPresetMediumQuality // can't add watermark with passthrough
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            return nil
        }

        let duration: CMTime
        do {
            if #available(iOS 15, *) {
                duration = try await asset.load(.duration)
            } else {
                duration = asset.duration
            }
        } catch {
            DDLogError("ExternalSharePreviewImageGenerator/video/error loading duration: \(error)")
            return nil
        }

        // Add watermark
        if addWatermark, let videoTrack = asset.tracks(withMediaType: .video).first {
            let logoLayer = await overlayLayerForVideo(videoSize: videoTrack.naturalSize)
            let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
            let trackID = asset.unusedTrackID()
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(additionalLayer: logoLayer, asTrackID: trackID)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, end: .positiveInfinity)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction()
            layerInstruction.trackID = trackID
            layerInstruction.setOpacity(1.0, at: .zero)
            let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            instruction.layerInstructions = [layerInstruction, videoLayerInstruction]
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition
        }

        exportSession.timeRange = CMTimeRange(start: .zero, end: CMTimeMinimum(CMTime(seconds: 15, preferredTimescale: 1), duration))
        exportSession.outputFileType = .mp4
        exportSession.outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("mp4")

        await exportSession.export()
        if let error = exportSession.error {
            DDLogError("ExternalSharePreviewImageGenerator/video/error exporting: \(error)")
            return nil
        }
        return exportSession.outputURL
    }

    @MainActor
    static func overlayLayerForVideo(videoSize: CGSize) -> CALayer {
        let backgroundLayer = CALayer()
        backgroundLayer.frame = CGRect(origin: .zero, size: videoSize)
        backgroundLayer.isGeometryFlipped = true

        let watermarkTextLayer = CATextLayer()
        watermarkTextLayer.string = watermarkAttributedString
        let watermarkSize = watermarkTextLayer.preferredFrameSize()
        watermarkTextLayer.alignmentMode = .center
        watermarkTextLayer.allowsFontSubpixelQuantization = true
        watermarkTextLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        watermarkTextLayer.frame = CGRect(origin: CGPoint(x: backgroundLayer.bounds.midX - watermarkSize.width * 0.5, y: backgroundLayer.bounds.maxY - 150),
                                          size: watermarkSize)

        let scale = 0.5 * videoSize.width / watermarkSize.width
        watermarkTextLayer.transform = CATransform3DMakeScale(scale, scale, 1.0)
        backgroundLayer.addSublayer(watermarkTextLayer)
        watermarkTextLayer.displayIfNeeded()

        return backgroundLayer
    }

    static func watermarkImage(size: CGSize) -> UIImage {
        let watermarkLabel = UILabel()
        watermarkLabel.attributedText = watermarkAttributedString
        watermarkLabel.numberOfLines = 0
        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        watermarkLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        watermarkLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let backgroundView = UIView()
        backgroundView.addSubview(watermarkLabel)

        let widthConstraint = backgroundView.widthAnchor.constraint(equalToConstant: size.width)
        widthConstraint.priority = .defaultLow

        let heightConstraint = backgroundView.heightAnchor.constraint(equalToConstant: size.height)
        heightConstraint.priority = .defaultLow

        let verticalPositionConstraint = NSLayoutConstraint(item: watermarkLabel, attribute: .centerY, relatedBy: .equal, toItem: backgroundView, attribute: .bottom, multiplier: 0.8, constant: 0)
        verticalPositionConstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            watermarkLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backgroundView.leadingAnchor),
            watermarkLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            watermarkLabel.topAnchor.constraint(greaterThanOrEqualTo: backgroundView.topAnchor),
            watermarkLabel.bottomAnchor.constraint(lessThanOrEqualTo: backgroundView.bottomAnchor),
            verticalPositionConstraint,
        ])

        let renderSize = backgroundView.systemLayoutSizeFitting(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                                       height: CGFloat.greatestFiniteMagnitude))

        let bounds = CGRect(origin: .zero, size: renderSize)
        backgroundView.frame = bounds

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        let imageBounds = bounds.applying(CGAffineTransform(scaleX: Constants.scale, y: Constants.scale))

        let img = UIGraphicsImageRenderer(bounds: imageBounds).image { context in
            backgroundView.drawHierarchy(in: imageBounds, afterScreenUpdates: true)
        }
        return img
    }
}

private extension Localizations {

    static var postedFrom: String {
        return NSLocalizedString("externalshare.postedFrom", value: "Posted from %@", comment: "Always 'Posted from HalloApp', but we are applying additional formatting to HalloApp")
    }
}
