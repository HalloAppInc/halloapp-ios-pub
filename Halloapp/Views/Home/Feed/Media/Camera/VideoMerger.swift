//
//  VideoMerger.swift
//  HalloApp
//
//  Created by Tanveer on 10/28/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import AVFoundation
import CocoaLumberjackSwift

class VideoMerger {

    private(set) var isReady = false

    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue: MTLCommandQueue? = device?.makeCommandQueue()
    private var computePipelineState: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?

    private var outputPixelBufferPool: CVPixelBufferPool?
    private var inputFormatDescription: CMFormatDescription?
    private(set) var outputFormatDescription: CMFormatDescription?

    init() {
        guard
            let device,
            let library = device.makeDefaultLibrary(),
            let function = library.makeFunction(name: "videoShader")
        else {
            return
        }

        do {
            computePipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            DDLogError("VideoMerger/init/could not create compute pipeline state with error \(String(describing: error))")
        }
    }

    func prepare(formatDescription: CMFormatDescription) {
        reset()

        (outputPixelBufferPool, _, outputFormatDescription) = allocateOutputBufferPool(formatDescription: formatDescription) ?? (nil, nil, nil)
        guard outputPixelBufferPool != nil else {
            return
        }

        inputFormatDescription = formatDescription

        guard let device else {
            return
        }

        var textureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) != kCVReturnSuccess {
            DDLogError("VideoMerger/failed to create texture cache")
        } else {
            self.textureCache = textureCache
        }

        isReady = true
    }

    private func reset() {
        outputPixelBufferPool = nil
        outputFormatDescription = nil
        inputFormatDescription = nil
        textureCache = nil
        isReady = false

        if let textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
    }

    typealias BufferPool = (pool: CVPixelBufferPool?, colorSpace: CGColorSpace?, outputFormat: CMFormatDescription?)?

    private func allocateOutputBufferPool(formatDescription: CMFormatDescription) -> BufferPool {
        let bufferCount = 3
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)

        if mediaSubType != kCVPixelFormatType_Lossy_32BGRA && mediaSubType != kCVPixelFormatType_Lossless_32BGRA &&
            mediaSubType != kCVPixelFormatType_32BGRA {
            return nil
        }

        var bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: UInt(mediaSubType),
            kCVPixelBufferWidthKey as String: Int(1024),
            kCVPixelBufferHeightKey as String: Int(768),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]

        var colorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
        if let formatDescriptionExtension = CMFormatDescriptionGetExtensions(formatDescription) as Dictionary? {
            let colorPrimaries = formatDescriptionExtension[kCVImageBufferColorPrimariesKey]

            if let colorPrimaries {
                var colorSpaceProperties: [String: AnyObject] = [
                    kCVImageBufferColorPrimariesKey as String: colorPrimaries
                ]

                if let yCbCrMatrix = formatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey as String] = yCbCrMatrix
                }

                if let transferFunction = formatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey as String] = transferFunction
                }

                bufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
            }

            if let cvColorSpce = formatDescriptionExtension[kCVImageBufferCGColorSpaceKey], CFGetTypeID(cvColorSpce) == CGColorSpace.typeID {
                colorSpace = (cvColorSpce as! CGColorSpace)
            } else if colorPrimaries as? String == kCVImageBufferColorPrimaries_P3_D65 as String {
                colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
            }
        }

        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: bufferCount]
        var bufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as NSDictionary, bufferAttributes as NSDictionary?, &bufferPool)

        guard let bufferPool else {
            DDLogError("VideoMerge/allocate-buffer-pool/failed to allocate pool")
            return nil
        }

        preallocateBuffers(pool: bufferPool, threshold: bufferCount)

        var buffer: CVPixelBuffer?
        var outputFormatDescription: CMFormatDescription?
        let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: bufferCount] as NSDictionary
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, bufferPool, auxAttributes, &buffer)

        if let buffer {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: buffer,
                                              formatDescriptionOut: &outputFormatDescription)
        }

        buffer = nil
        return (bufferPool, colorSpace, outputFormatDescription)
    }

    private func preallocateBuffers(pool: CVPixelBufferPool, threshold: Int) {
        var buffers = [CVPixelBuffer]()
        var error = kCVReturnSuccess

        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: threshold] as NSDictionary
        var buffer: CVPixelBuffer?

        while error == kCVReturnSuccess {
            error = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)

            if let buffer {
                buffers.append(buffer)
            }

            buffer = nil
        }

        buffers.removeAll()
    }

    func merge(primaryBuffer: CVPixelBuffer, secondaryBuffer: CVPixelBuffer, portrait: Bool) -> CVPixelBuffer? {
        guard isReady, let outputPixelBufferPool else {
            DDLogInfo("VideoMerger/merge/no pixel buffer pool")
            return nil
        }

        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool, &outputPixelBuffer)
        guard let outputPixelBuffer else {
            DDLogError("VideoMerger/merge/failed to create output pixel buffer")
            return nil
        }

        guard
            let outputTexture = texture(from: outputPixelBuffer),
            let leftTexture = texture(from: primaryBuffer),
            let rightTexture = texture(from: secondaryBuffer)
        else {
            DDLogError("VideoMerger/merge/could not create textures from pixel buffers")
            return nil
        }

        guard
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder = commandBuffer.makeComputeCommandEncoder(),
            let piplineState = computePipelineState
        else {
            if let textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }

            return nil
        }

        commandEncoder.label = "mixer"
        commandEncoder.setComputePipelineState(piplineState)
        commandEncoder.setTexture(leftTexture, index: 0)
        commandEncoder.setTexture(rightTexture, index: 1)
        commandEncoder.setTexture(outputTexture, index: 2)

        var portrait = portrait
        withUnsafeMutablePointer(to: &portrait) { pointer in
            commandEncoder.setBytes(pointer, length: MemoryLayout<Bool>.size, index: 0)
        }

        let width = piplineState.threadExecutionWidth
        let height = piplineState.maxTotalThreadsPerThreadgroup / width

        let threadsPerGroup = MTLSizeMake(width, height, 1)
        let threadGroupsPerGrid = MTLSize(width: (outputTexture.width + width - 1) / width,
                                         height: (outputTexture.height + height - 1) / height,
                                          depth: 1)

        commandEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()

        return outputPixelBuffer
    }

    private func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else {
            return nil
        }

        let (width, height) = (CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))
        var cvTexture: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }

        return texture
    }
}
