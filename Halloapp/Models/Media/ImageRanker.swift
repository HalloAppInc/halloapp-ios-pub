//
//  ImageRanker.swift
//  HalloApp
//
//  Created by Garrett on 8/16/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreML
import Foundation
import Photos
import Vision

struct ImageRankerAssetInfo {
    let isSelected: Bool
    let debugInfo: String
}

/// Maps identifier to debug info for display to internal users
typealias AssetInfoMap = [String: ImageRankerAssetInfo]

final class BurstAwareHighlightSelector {

    /// Photos taken with a gap shorter than this interval are considered part of the same "burst"
    let BurstThreshold = TimeInterval(15)

    /// Photos with feature distance below this threshold are considered too similar to be included in the same set of highlights
    let SimilarityThreshold = Float(0.7)

    /// We want to boost assets from large bursts (presumably the subject is important to the user).
    /// If some asset A with in-score Si(A) is from a burst of B assets out of N total assets, out-score So(A) = Si(A) * (1 + B/N * BurstShareFactor)
    /// (e.g., if 50% of assets are from the same burst and BSF=1, the highest scoring asset from the burst would get a 50% score boost)
    let BurstShareFactor = CGFloat(1)

    /// We boost favorited assets by multiplying their score by this factor.
    let FavoriteFactor = CGFloat(1.5)

    ///  Faces with an area greater than this fraction of the image are considered significant
    let SignificantFaceAreaThreshold = CGFloat(0.03)

    /// We boost images with significant faces by multiplying their score by this factor
    let SignificantFaceFactor = CGFloat(1.3)

    func selectHighlights(_ n: Int, from assets: [PHAsset]) async -> ([PHAsset], AssetInfoMap) {

        var debugInfo = [String: String]()

        // 1. Divide photos into bursts (sets of photos taken less than BurstThreshold apart)
        
        var bursts = [[PHAsset]]()
        let timeOrderedAssets = assets.sorted { a1, a2 in
            guard let t1 = a1.creationDate else { return false }
            guard let t2 = a2.creationDate else { return true }
            return t1 < t2
        }
        var burst = [PHAsset]()
        for a in timeOrderedAssets {
            guard let time = a.creationDate else {
                bursts.append([a])
                continue
            }
            guard let lastTime = burst.last?.creationDate else {
                burst.append(a)
                continue
            }
            if lastTime.addingTimeInterval(BurstThreshold) > time {
                burst.append(a)
            } else {
                bursts.append(burst)
                burst = [a]
            }
        }
        if !burst.isEmpty { bursts.append(burst) }
        
        DDLogInfo("selectHighlights/burst [found \(assets.count) bursts]")
        
        // 2. Take top scoring photo from each burst
        DDLogInfo("selectHighlights/scoring [\(assets.count) assets]")
        
        let scoredAssets = await ImageRanker.shared.scoreAssets(assets)
        var scoredAssetMap = [String: CGFloat]()
        for (asset, score) in scoredAssets {
            appendDebugLine(String(format: "ML: %.2f", score), for: asset.localIdentifier, in: &debugInfo)
            var adjustedScore = score
            let favoriteBoost = asset.isFavorite ? FavoriteFactor : 1
            if favoriteBoost > 1 {
                appendDebugLine(String(format: "FavBoost: %.2f", favoriteBoost), for: asset.localIdentifier, in: &debugInfo)
            }
            adjustedScore *= favoriteBoost
            if let faces = await ImageRanker.shared.faceObservationsForAsset(asset) {
                let significantArea = SignificantFaceAreaThreshold
                if faces.contains(where: { $0.boundingBox.height * $0.boundingBox.width > significantArea }) {
                    DDLogInfo("selectHighlights/face/foundSignificantFace")
                    adjustedScore *= SignificantFaceFactor
                    appendDebugLine(String(format: "FaceBoost: %.2f", SignificantFaceFactor), for: asset.localIdentifier, in: &debugInfo)
                }
            }
            scoredAssetMap[asset.localIdentifier] = adjustedScore
        }
        
        let candidates: [(PHAsset, CGFloat)] = bursts.enumerated().compactMap { (i, burst) in
            guard let asset = burst.max(by: {
                let s0 = scoredAssetMap[$0.localIdentifier] ?? 1
                let s1 = scoredAssetMap[$1.localIdentifier] ?? 1
                return s0 < s1
            }) else {
                return nil
            }
            let burstBoost = 1.0 + BurstShareFactor * CGFloat(burst.count) / CGFloat(assets.count)
            for rejected in burst.filter({ $0 != asset }) {
                appendDebugLine(String(format: "[not best of burst %d]", i), for: rejected.localIdentifier, in: &debugInfo)
            }
            appendDebugLine(String(format: "BurstBoost [%d]: %.2f", i, burstBoost), for: asset.localIdentifier, in: &debugInfo)
            return (asset, burstBoost * (scoredAssetMap[asset.localIdentifier] ?? 1))
        }.sorted {
            return $0.1 > $1.1
        }
        
        for (c, s) in candidates {
            DDLogInfo("selectHighlights/scoring [\(c.localIdentifier) \(s)")
            appendDebugLine(String(format: "Final: %.2f", s), for: c.localIdentifier, in: &debugInfo)
        }
        
        // 3. Select up to N highest scoring candidates
        var out = [PHAsset]()
        
        DDLogInfo("selectHighlights/similarity/analyzing [\(candidates.count) assets]")
        var featurePrintObservations = [String: VNFeaturePrintObservation]()
        for (c, _) in candidates {
            let candidateFPO: VNFeaturePrintObservation? = await {
                if let cached = featurePrintObservations[c.localIdentifier] {
                    return cached
                }
                guard let computed = await ImageRanker.shared.featurePrintObservationForAsset(c) else {
                    return nil
                }
                featurePrintObservations[c.localIdentifier] = computed
                return computed
            }()
            guard let candidateFPO else {
                // Include the candidate if no feature print exists for comparison
                out.append(c)
                continue
            }
            var distance = Float()
            var tooSimilar = false
            for incumbent in out {
                let incumbentFPO: VNFeaturePrintObservation? = await {
                    if let cached = featurePrintObservations[incumbent.localIdentifier] {
                        return cached
                    }
                    guard let computed = await ImageRanker.shared.featurePrintObservationForAsset(incumbent) else {
                        return nil
                    }
                    featurePrintObservations[incumbent.localIdentifier] = computed
                    return computed
                }()
                guard let incumbentFPO else {
                    continue
                }
                do {
                    try incumbentFPO.computeDistance(&distance, to: candidateFPO)
                    DDLogInfo("selectHighlights/similarity/distance [\(distance)]")
                } catch {
                    DDLogError("selectHighlights/similarity/computeDistance error [\(error)]")
                    continue
                }
                if distance < SimilarityThreshold {
                    DDLogInfo("selectHighlights/similarity/tooSimilar [\(distance)]")
                    appendDebugLine("[too similar]", for: c.localIdentifier, in: &debugInfo)
                    tooSimilar = true
                    break
                }
            }
            if !tooSimilar {
                DDLogInfo("selectHighlights/similarity/adding")
                out.append(c)
            }
        }

        let assetInfo = debugInfo.reduce(into: AssetInfoMap()) { assetInfo, kv in
            let (localIdentifier, info) = kv
            let isSelected = out.contains { $0.localIdentifier == localIdentifier }
            assetInfo[localIdentifier] = ImageRankerAssetInfo(isSelected: isSelected, debugInfo: info)
        }

        return (out, assetInfo)
    }

    private func appendDebugLine(_ line: String, for identifier: String, in dictionary: inout [String: String]) {
        var info = dictionary[identifier] ?? ""
        if !info.isEmpty { info += "\n" }
        dictionary[identifier] = info + line
    }

}

final class ImageRanker {
    
    static let shared = ImageRanker()

    private let cachingImageManager = PHCachingImageManager()

    private lazy var model = try? AestheticCoreML()

    /// Returns media IDs in decreasing order of aesthetic preference (excluding IDs for media items that could not be scored)
    public func rankMedia(_ media: [FeedMedia]) async -> [String]  {
        let scores = try? await withThrowingTaskGroup(
            of: (String, CGFloat)?.self,
            returning: [String].self,
            body: { taskGroup in
                for mediaItem in media {
                    guard let id = mediaItem.id else { continue }
                    guard mediaItem.type == .image else { continue }
                    taskGroup.addTask {
                        if let cachedScore = self.cachedScores[id] {
                            return (id, cachedScore)
                        }
                        if let image = mediaItem.image {
                            let score = self.computeScore(for: image)
                            self.cachedScores[id] = score
                            return (id, score)
                        }
                        
                        for try await image in mediaItem.imagePublisher.values {
                            guard let image else { continue }
                            let score = self.computeScore(for: image)
                            self.cachedScores[id] = score
                            return (id, score)
                        }

                        return nil
                    }
                }
                var scores = [(String, CGFloat)]()
                for try await result in taskGroup {
                    guard let result else { continue }
                    scores.append(result)
                }
                let sortedScores = scores.sorted { $0.1 > $1.1 }
                DDLogInfo("Sorted scores: \(sortedScores)")
                return sortedScores.map { $0.0 }
            })
        
        return scores ?? []
    }

    func faceObservationsForAsset(_ asset: PHAsset) async -> [VNFaceObservation]? {
        let image = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat

            var didReturnImage = false

            self.cachingImageManager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .default, options: options) { image, _ in
                guard !didReturnImage else {
                    return
                }
                didReturnImage = true
                continuation.resume(returning: image)
            }
        }
        guard let cgImage = image?.cgImage else { return nil }
        return faceObservationsForImage(cgImage)
    }

    func featurePrintObservationForAsset(_ asset: PHAsset) async -> VNFeaturePrintObservation? {
        let image = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat

            var didReturnImage = false

            self.cachingImageManager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .default, options: options) { image, _ in
                guard !didReturnImage else {
                    return
                }
                didReturnImage = true
                continuation.resume(returning: image)
            }
        }
        guard let cgImage = image?.cgImage else { return nil }
        return featurePrintObservationForImage(cgImage)
    }

    func faceObservationsForImage(_ image: CGImage) -> [VNFaceObservation]? {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        do {
            DDLogInfo("Detecting faces in image...")
            try requestHandler.perform([request])
            DDLogInfo("Received faces [\(request.results?.count ?? 0) found]")
            return request.results
        } catch {
            DDLogError("Vision error: \(error)")
            return nil
        }
    }

    func featurePrintObservationForImage(_ image: CGImage) -> VNFeaturePrintObservation? {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            DDLogInfo("Requesting FPO for image...")
            try requestHandler.perform([request])
            DDLogInfo("Received FPO")
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            DDLogError("Vision error: \(error)")
            return nil
        }
    }

    // Returns 1 for unscored assets

    public func scoreAssets(_ assets: [PHAsset]) async -> [(PHAsset, CGFloat)] {
        let scoredAssets = try? await withThrowingTaskGroup(
            of: (asset: PHAsset, score: CGFloat).self,
            returning: [(asset: PHAsset, score: CGFloat)].self,
            body: { taskGroup in
                for asset in assets {
                    taskGroup.addTask {
                        if let cachedScore = self.cachedScores[asset.localIdentifier] {
                            return (asset, cachedScore)
                        }
                        let image = await withCheckedContinuation { continuation in
                            let options = PHImageRequestOptions()
                            options.deliveryMode = .fastFormat

                            var didReturnImage = false

                            self.cachingImageManager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .default, options: options) { image, _ in
                                guard !didReturnImage else {
                                    return
                                }
                                didReturnImage = true
                                continuation.resume(returning: image)
                            }
                        }
                        if let image {
                            let score = self.computeScore(for: image)
                            self.cachedScores[asset.localIdentifier] = score
                            return (asset, score)
                        } else {
                            return (asset, 0)
                        }
                    }
                }
                var scores = [(PHAsset, CGFloat)]()
                for try await result in taskGroup {
                    scores.append(result)
                }
                return scores
            })

        return scoredAssets ?? []
    }

    public func rankMedia(_ assets: [PHAsset]) async -> [PHAsset]  {
        let sortedAssets = try? await withThrowingTaskGroup(
            of: (asset: PHAsset, score: CGFloat).self,
            returning: [PHAsset].self,
            body: { taskGroup in
                for asset in assets {
                    taskGroup.addTask {
                        if let cachedScore = self.cachedScores[asset.localIdentifier] {
                            return (asset, cachedScore)
                        }
                        let image = await withCheckedContinuation { continuation in
                            let options = PHImageRequestOptions()
                            options.deliveryMode = .fastFormat

                            var didReturnImage = false

                            self.cachingImageManager.requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .default, options: options) { image, _ in
                                guard !didReturnImage else {
                                    return
                                }
                                didReturnImage = true
                                continuation.resume(returning: image)
                            }
                        }
                        if let image {
                            let score = self.computeScore(for: image)
                            self.cachedScores[asset.localIdentifier] = score
                            return (asset, score)
                        } else {
                            return (asset, 0)
                        }
                    }
                }
                var scores = [(PHAsset, CGFloat)]()
                for try await result in taskGroup {
                    scores.append(result)
                }
                let sortedScores = scores.sorted { $0.1 > $1.1 }
                DDLogInfo("Sorted scores: \(sortedScores)")
                return sortedScores.map { $0.0 }
            })

        return sortedAssets ?? []
    }

    private var _cachedScores = [String: CGFloat]()

    private let cacheQueue = DispatchQueue(label: "com.halloapp.imagerankercache")

    private var cachedScores: [String: CGFloat] {
        get {
            cacheQueue.sync {
                _cachedScores
            }
        }

        set {
            cacheQueue.sync {
                _cachedScores = newValue
            }
        }
    }

    private func preprocess(image: UIImage) -> MLMultiArray? {
        let fillScale = max(224.0/image.size.height, 224.0/image.size.width)
        let fillSize = CGSize(width: image.size.width * fillScale, height: image.size.height * fillScale)
        guard let img = image.fastResized(to: fillSize)?.cgImage,
              let cropped = img.cropping(
                to: CGRect(
                    x: (fillSize.width - 224.0)/2,
                    y: (fillSize.height - 224.0)/2,
                    width: 224, height: 224)),
              let imgData = cropped.dataProvider?.data,
              let multiArray = try? MLMultiArray(shape: [1, 224, 224, 3], dataType: .float32) else
        {
            return nil
        }
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(imgData)
        let pixelCount = 224 * 224
        for px in 0..<pixelCount {
            let i_out = px * 3 // RGB
            let i_in = px * 4 // RGBA
            multiArray[i_out] = NSNumber(floatLiteral: CGFloat(data[i_in]) / 255.0)
            multiArray[i_out+1] = NSNumber(floatLiteral:CGFloat(data[i_in + 1]) / 255.0)
            multiArray[i_out+2] = NSNumber(floatLiteral:CGFloat(data[i_in + 2]) / 255.0)
        }
        return multiArray
    }
    
    public func computeScore(for image: UIImage) -> CGFloat {
        let score: CGFloat
        do {
            guard let multiArray = preprocess(image: image) else { return 0 }
            let input = AestheticCoreMLInput(input_1: MLShapedArray(multiArray))
            if let prediction = try model?.prediction(input: input).featureValue(for: "Identity")?.multiArrayValue?.float32Array {
                score = self.score(from: prediction)
            } else {
                score = 0
            }
        } catch {
            DDLogError("Aesthetic classifier error: \(error)")
            score = 0
        }
        return score
    }
    
    /// Takes in array of rating predictions (where ratingPredictions[i] is probability of receiving rating i+1) and returns overall score out of 10
    private func score(from ratingPredictions: [Float32]) -> CGFloat {
        guard !ratingPredictions.isEmpty else { return 0 }
        let predictionSum = ratingPredictions.reduce(0) { sum, next in sum + next }
        let normalizedPredictions = ratingPredictions.map { CGFloat($0 / predictionSum) }
        let step = 9.0 / CGFloat(normalizedPredictions.count) // Ratings range from 1-10
        let score = normalizedPredictions.enumerated().reduce(0) { sum, next in
            let (i, prob) = next
            return sum + (1.0 + CGFloat(i)*step) * prob
        }
        return score
    }
}

private extension MLMultiArray {
    var float32Array: [Float32]? {
        guard let buffer = try? UnsafeBufferPointer<Float32>(self) else {
            return nil
        }
        return Array(buffer)
    }
}
