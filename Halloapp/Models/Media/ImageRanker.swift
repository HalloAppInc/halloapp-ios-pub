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

final class ImageRanker {
    
    static let shared = ImageRanker()

    private let cachingImageManager = PHCachingImageManager()

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
            let model = try AestheticCoreML()
            let input = AestheticCoreMLInput(input_1: MLShapedArray(multiArray))
            if let prediction = try model.prediction(input: input).featureValue(for: "Identity")?.multiArrayValue?.float32Array {
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
